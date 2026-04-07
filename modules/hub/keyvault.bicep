// azure key vault module
param keyVaultName string = 'xelavault'
param location string
param enableRBACAuthorization bool = true
param logAnalyticsWorkspaceId string
param kvIdentityId string
param kvPrincipalId string
param wafGwIdentityId string
param wafGwPrincipalId string
param appsSvcPrincipalId string
param appsSvcIdentityId string
param publicIP string

@description('List of Key Vault role short names to assign (e.g., "SecretsUser", "Reader")')
param roles array = [
  'SecretsUser' //automation identity to manage secrets
  'SecretsOfficer' //DevOps Secrets User to manage secrets
  'Administrator' // admin access to manage the key vault
  'Reader' // read access only
]
var roleDefinitionMap = {
  SecretsUser: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' //Key Vault Secrets User
  SecretsOfficer: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' //Key Vault Secrets Officer
  Administrator: '00482a5a-887f-4fb3-b363-3b7fe8e74483' //Key Vault Administrator
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' //Reader
}
// create key vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: '${keyVaultName}${take(uniqueString(resourceGroup().id), 4)}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        { value: publicIP } // inbound public Ip
      ]
      virtualNetworkRules: []
      /*{
          id: '${hubVnet.id}/subnets/appgatewaysubnet'
          ignoreMissingVnetServiceEndpoint: false
        }*/
    }
    publicNetworkAccess: 'Enabled' // disable public access to the key vault
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableRbacAuthorization: enableRBACAuthorization
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableSoftDelete: false // 🔥 FIX THIS
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
  }
  tags: {
    Service: 'Application'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
// Assign roles to the Key Vault Managed Identity
resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleName in roles: {
    name: guid(keyVault.id, kvIdentityId, roleName)
    scope: keyVault
    properties: {
      principalId: kvPrincipalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionMap[roleName])
      principalType: 'ServicePrincipal'
    }
  }
]
// role assignment for waf
resource wafGwKvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, wafGwIdentityId, 'SecretsUser')
  scope: keyVault
  properties: {
    principalId: wafGwPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    ) // SecretsUser
    principalType: 'ServicePrincipal'
  }
}
// Role assignment for Appsservice
//var appsServiceRpObjectId = '164241dd-bd5a-4b9a-9d38-e987795b357e' // discovered via az rest

resource appSvcKvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appsSvcIdentityId, 'SecretsUser')
  scope: keyVault
  properties: {
    principalId: appsSvcPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets User
    )
    principalType: 'ServicePrincipal'
  }
}
// user role assignment for key vault administrator
@description('Object ID of the user (e.g. from Azure AD) to assign as Key Vault Administrator')
param userObjectId string = 'a91fb43a-77a2-4b42-9f7a-5bbf380bdb85'

resource keyVaultAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, userObjectId, 'Key Vault Administrator')
  scope: keyVault
  properties: {
    principalId: userObjectId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '00482a5a-887f-4fb3-b363-3b7fe8e74483' // Key Vault Administrator
    )
    principalType: 'User'
  }
}
// Reference the VNet and Subnet where the Private Endpoint will live
param privateEP bool = false
param dnsZoneIds array
param hubVnetName string
param hubVnetResourceGroup string

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}
resource privateEPSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: 'privateEPSubnet'
  parent: hubVnet
}

// Private Endpoint for Key Vault
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEP) {
  name: '${keyVault.name}privEP'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    subnet: {
      id: privateEPSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVault.name}-PEConnection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Auto-Approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
  }
}
// Private DNS Zone Link for Key Vault Private Endpoint
resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEP) {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: dnsZoneIds[8] // kDNSzone for Key Vault
        }
      }
    ]
  }
}
// log diagnostics for keyvault
resource diagKeyVault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${keyVaultName}-${take(uniqueString(resourceGroup().id), 4)}'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}
@description('SQL administrator password to store in the vault')
@secure()
param sqlAdminPassword string

resource sqlAdminSecret 'Microsoft.KeyVault/vaults/secrets@2024-12-01-preview' = {
  parent: keyVault
  name: 'sqlAdminPassword'
  properties: {
    value: sqlAdminPassword
    contentType: 'SQL Password'
  }
}
// outputs
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultCertSecretId string = 'https://${keyVault.name}.${environment().suffixes.keyvaultDns}/secrets/xelaSslCert'
