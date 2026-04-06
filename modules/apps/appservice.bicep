// This module creates an App Service Plan and a Web App configured to run a Docker image from Azure's registry.
//param tenantId string       = '6aa484b3-3f8f-4112-812e-161516a37550'  // Your AAD tenant ID
//param aadClientId string  = '805982c6-ef24-46bd-a249-34b0b76307a4'    // Client ID from AAD App Registration
param appID string = take(uniqueString(resourceGroup().id), 4)
param appServiceName string = 'xelaPlan${appID}'
param webAppName string = 'xelaweb${appID}'
param location string
param acrLoginServer string   // This should be the ACR login server -- 'acrd34c.azurecr.io'
param linuxFxVersion string
param allowPublicIP string    // allowed public IP from home net
param appInsightsResourceId string
@secure()
param acrUsername string // inject the ACR account during deployment
@secure()
param acrPassword string  // inject the ACR account during deployment
param keyVaultId string
param appSvcIdentityId string


// App Service Plan - Configured for Linux and Docker
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServiceName
  location: location
  tags: {
    webapp: 'AppService'
  }
  sku: {
    name: 'B1' // Basic plan SKU
    capacity: 1
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux App Service Plan
  }
}

/* Web App - Configured to run a Docker image from Azure's registry */
resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appSvcIdentityId}': {}
    }
  }
  tags: {
    Service: '${resourceGroup().id}/providers/Microsoft.Web/serverfarms/${appServicePlan.name}' //'hidden-related' was removed from the tags
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true // Set to true if you want to enforce HTTPS
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: linuxFxVersion // Should be 'DOCKER|acrd34c.azurecr.io/xelatech-webapp:latest'
      acrUseManagedIdentityCreds: false //set to true if using managed identity
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      webSocketsEnabled: false
      alwaysOn: false
        appSettings: [
          {
            name: 'DOCKER_CUSTOM_IMAGE_NAME'
            value: 'xelatech-webapp:latest' // This should be the image name in ACR
          }
          {
            name: 'DOCKER_ENABLE_CI'
            value: 'true' // Set to true if you want to enable continuous deployment
          }
          {
            name: 'DOCKER_REGISTRY_SERVER_URL'
            value: 'https://${acrLoginServer}' // This should be the ACR login server
          }
          {
            name: 'DOCKER_REGISTRY_SERVER_USERNAME'
            value: acrUsername // Use a secure password for the ACR admin user
          }
          {
            name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
            value: acrPassword // Use a secure password for the ACR admin user
          }
          {
            name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
            value: 'false' // Set to false if you don't need App Service storage
          }
        ]// Uncomment if you want to set app settings to user acr credentials
    }
  }
}
// imports cert to webapp but not needed if frontended by waf
param bindSsl bool = false // Set to true if you want to bind a custom domain with SSL
resource cert 'Microsoft.Web/certificates@2024-11-01' = if (bindSsl) {
  name: 'webapp-xelatech-net-cert'
  location: location
  properties: {
    keyVaultId: keyVaultId
    keyVaultSecretName: 'xelaSslCert' // This should be the secret name in Key Vault
    serverFarmId: appServicePlan.id
  }
}
// Bind custom domain
resource customDomain 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  name: 'webapp.xelatech.net'
  parent: webApp
  properties: {
    siteName: webApp.name
    hostNameType: 'Verified'
    customHostNameDnsRecordType: 'CName' // ✅ This is critical
  }
}
// Bind SSL certificate (must already be uploaded to the Web App)
resource sslBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (bindSsl) {
  name: 'webapp.xelatech.net-ssl'
  parent: webApp
  properties: {
    sslState: 'SniEnabled'
    thumbprint: cert.properties.thumbprint // Import thumbprint from Keyvault
    hostNameType: 'Verified'
    customHostNameDnsRecordType: 'CName'
  }
}
// Access restrictions moved to a separate resource
resource webAppAccessRestrictions 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: webApp
  name: 'web'
  properties: {
    publicNetworkAccess: 'Disabled' // Set to 'Disabled' if you want to restrict public access
    ipSecurityRestrictions: [
      {
        ipAddress: '${allowPublicIP}/32' // allowed public access from homenet
        action: 'Allow'
        tag: 'Default'
        priority: 100
        name: 'allowHomenet'
        description: 'Allow home Network'
      }
      {
        ipAddress: 'Any'
        action: 'Deny'
        priority: 2147483647
        name: 'Deny all'
        description: 'Deny all access'
      }
    ]
    ipSecurityRestrictionsDefaultAction: 'Deny'
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
  }
}

// AAD Authentication for Web App
/*resource webAppAuth 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '2.0'
    }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'AzureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: aadClientId
          openIdIssuer: '${environment().authentication.loginEndpoint}common/v2.0'  // openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0' for AAD tenant only
        }
        login: {
          disableWWWAuthenticate: false
          loginParameters: ['domain_hint=organizations']
        }
      }
      google: {
        enabled: false
        registration: {
          clientId: '<google-client-id>'
          clientSecretSettingName: 'GOOGLE_SECRET'
        }
      }
      apple: {
        enabled: false
        registration: {
          clientId: '<apple-client-id>'
          clientSecretSettingName: 'APPLE_SECRET'
        }
      }
    }
  }
  parent: webApp
}*/
// Private Endpoint for Web App
param dnsZoneIds array
param privateEPSubnetIds array

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: '${webApp.name}PrivateEP'
  location: location
  properties: {
    subnet: {
      id: privateEPSubnetIds[2] // privateEP subnet for appsvnet
    }
    privateLinkServiceConnections: [
      {
        name: 'webAppPrivateLink'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [ 'sites' ]
        }
      }
    ]
  }
}
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'webAppDnsZone'
        properties: {
          privateDnsZoneId: dnsZoneIds[10] //👈 This assumes correct index for privatelink.azurewebsites.net
        }
      }
    ]
  }
}
resource webAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appServiceToLogs'
  scope: webApp
  properties: {
    workspaceId: appInsightsResourceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
// Output the default host name for use in main.bicep
output webAppFqdn string = webApp.properties.defaultHostName
output webAppName string = webApp.name
