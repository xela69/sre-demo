targetScope = 'resourceGroup'

param workspaceId string
param deployStorage bool = true

resource storagePrivateEndpointExisting 'Microsoft.Network/privateEndpoints@2024-07-01' existing = if (deployStorage) {
  name: 'hubStorageBlobPE'
}

resource storagePrivateEndpointDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployStorage) {
  name: 'diag-storage-blob-pe'
  scope: storagePrivateEndpointExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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
