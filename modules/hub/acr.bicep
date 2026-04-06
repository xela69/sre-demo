param location string
param acrName string
param registryName string = '${acrName}${toLower(take(uniqueString(resourceGroup().id), 4))}'
param acrIdentityId string
param acrPrincipalId string
param acrSku string

// Grant AcrPull role to the Managed Identity on the ACR
// Role Assignments
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrRegistry.id, acrIdentityId, 'AcrPull')
  scope: acrRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
    principalId: acrPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrRegistry.id, acrIdentityId, 'AcrPush')
  scope: acrRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8311e382-0749-4cb8-b61a-304f252e45ec'
    )
    principalId: acrPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Create the ACR Registry Repo
resource acrRegistry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: registryName
  location: location
  sku: {
    name: acrSku
  }
  tags: {
    Environment: 'Production'
    Component: 'ACR'
    SecurityControl: 'Ignore'
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${acrIdentityId}': {}
    }
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: { status: 'disabled' }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      exportPolicy: { status: 'enabled' }
      azureADAuthenticationAsArmPolicy: { status: 'enabled' }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
    anonymousPullEnabled: false
  }
}
// Outputs
output acrLoginServer string = acrRegistry.properties.loginServer
output acrResourceId string = acrRegistry.id
