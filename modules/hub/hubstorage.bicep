param location string
param storageSkuName string
param storageName string
param hubAccountName string = '${storageName}${take(uniqueString(resourceGroup().id), 4)}'
var containerNames = ['inputs', 'outputs', 'errors']
@description('Resource ID of the Storage Account to scope the role assignments to')
param storageIdentityId string

@description('Principal IDs (objectIds) of the identities to grant access (e.g., user-assigned MI principalIds)')
param storagePrincipalId string

@description('Which built-in Storage roles to grant')
param rolesToGrant array = [
  'Storage Blob Data Contributor'
  'Storage Queue Data Contributor'
  // add/remove as needed
]
// ===== Role IDs (built-in) =====
var storageRoleIds = {
  'Storage Blob Data Contributor': 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  'Storage Blob Data Reader': '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  'Storage Blob Data Owner': 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  'Storage Queue Data Contributor': '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  'Storage Queue Data Reader': '19e7f393-2e06-4f9d-adb8-62f178e0d282'
  'Storage Account Contributor': '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}
/*/ some other roles to consider for SMB
az role definition list --name "Storage File Data SMB Share Reader"        --query "[0].name" -o tsv
az role definition list --name "Storage File Data SMB Share Contributor"    --query "[0].name" -o tsv
az role definition list --name "Storage File Data SMB Share Elevated Contributor" --query "[0].name" -o tsv*/

@description('List of virtual network subnet resource IDs to allow access to Storage Account')
// Storage Account for westus, eastus, and westus2
resource hubStorage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: hubAccountName
  location: location
  kind: 'StorageV2'
  tags: {
    Environment: 'Production'
    CostCenter: 'Storage'
    SecurityControl: 'Ignore'
  }
  sku: { name: storageSkuName }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
    }
  }

  // Nested resources for the boot storage account
  resource blobService 'blobServices' = {
    name: 'default'
    properties: {
      automaticSnapshotPolicyEnabled: true
      changeFeed: {
        enabled: true
      }
    }
    resource container 'containers' = [
      for containerName in containerNames: {
        name: containerName
      }
    ]
  }
  resource fileService 'fileServices' = {
    name: 'default'
    resource fileShare 'shares' = {
      name: 'notesdoc'
      properties: {
        accessTier: 'Hot'
      }
    }
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in rolesToGrant: {
    name: guid(hubStorage.id, storageIdentityId, role)
    scope: hubStorage
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageRoleIds[role])
      principalId: storagePrincipalId
      principalType: 'ServicePrincipal' // assuming the principal is a service principal (user-assigned managed identity)
      //scope: hubStorage.id
    }
  }
]
/*/ Private endpoints for storage accounts
param dnsZoneIds array
param hubStoragePrivEPName string = 'hubStoragePrivEP'
param privateEPSubnetName string = 'privateEPSubnet'
param hubVnetName string
param hubVnetResourceGroup string

// call out existing Vnet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}
resource privateEPSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: privateEPSubnetName
  parent: hubVnet
}

// Private endpoints for the storage accounts
resource hubStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: hubStoragePrivEPName
  location: location
  properties: {
    subnet: {
      id: privateEPSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'appsStoragePrivEP-conn'
        properties: {
          privateLinkServiceId: hubStorage.id
          groupIds: ['blob']
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

// DNS zone groups storage account private endpoints for Blob
resource hubStorageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: hubStoragePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: dnsZoneIds[0]
        }
      }
    ]
  }
}

// Boot diagnostics storage
@description('The resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

resource hubStorageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${hubStorage.name}'
  scope: hubStorage
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}
resource hubBlobDiags 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${hubStorage.name}-blob'
  scope: hubStorage::blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
  }
}*/

output hubStorageName string = hubStorage.name
output hubStorageID string = hubStorage.id
//output hubStoragePrivateEndpointID string = hubStoragePrivateEndpoint.id
output hubStorageBlobEndpoint string = hubStorage.properties.primaryEndpoints.blob
output hubStorageFileEndpoint string = hubStorage.properties.primaryEndpoints.file
//output hubStoragePrivateEndpointIP string = hubStoragePrivateEndpoint.properties.networkInterfaces[0].properties.ipConfigurations[0].properties.privateIPAddress
//output hubStoragePrivateEndpointDNS string = hubStoragePrivateEndpoint.properties.customDnsConfigs[0].fqdn
