// Azure Data Explorer (ADX / Kusto) cluster module
// Deploys a Dev/Test cluster with a default database and diagnostic settings.
// Designed for SRE Agent KQL querying and long-term analytics.

@description('Name of the ADX cluster')
param clusterName string

@description('Location for all resources')
param location string

@description('Log Analytics workspace resource ID for diagnostic settings')
param logAnalyticsWorkspaceId string

@description('SKU name for the ADX cluster. Dev/Test: Dev(No SLA)_Standard_E2a_v4, Production: Standard_E8ads_v5')
@allowed([
  'Dev(No SLA)_Standard_E2a_v4'
  'Dev(No SLA)_Standard_D11_v2'
  'Standard_E8ads_v5'
  'Standard_E16ads_v5'
])
param skuName string = 'Dev(No SLA)_Standard_E2a_v4'

@description('SKU tier: Basic for Dev/Test, Standard for Production')
@allowed(['Basic', 'Standard'])
param skuTier string = 'Basic'

@description('Number of instances (1 for Dev/Test, 2+ for Production)')
@minValue(1)
@maxValue(10)
param skuCapacity int = 1

@description('Name of the default database')
param databaseName string = 'sredb'

@description('Data retention period in days for the default database')
@minValue(1)
@maxValue(3650)
param dataRetentionDays int = 365

@description('Hot cache period in days for the default database')
@minValue(1)
@maxValue(365)
param hotCacheDays int = 31

@description('Principal ID of the SRE Agent managed identity for RBAC')
param sreAgentPrincipalId string = ''

@description('Toggle to deploy the ADX cluster')
param deployAdx bool = true

// ── ADX Cluster ──
resource adxCluster 'Microsoft.Kusto/clusters@2023-08-15' = if (deployAdx) {
  name: clusterName
  location: location
  sku: {
    name: skuName
    tier: skuTier
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: {
    Service: 'Analytics'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'SRE'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    trustedExternalTenants: []
    enableDiskEncryption: true
    enableStreamingIngest: true
    enablePurge: false
    enableDoubleEncryption: false
    engineType: 'V3'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// ── Default Database ──
resource adxDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = if (deployAdx) {
  name: databaseName
  parent: adxCluster
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P${dataRetentionDays}D'
    hotCachePeriod: 'P${hotCacheDays}D'
  }
}

// ── RBAC: Grant SRE Agent identity AllDatabasesViewer on the cluster ──
resource sreAgentDbViewer 'Microsoft.Kusto/clusters/principalAssignments@2023-08-15' = if (deployAdx && !empty(sreAgentPrincipalId)) {
  name: 'sre-agent-viewer'
  parent: adxCluster
  properties: {
    principalId: sreAgentPrincipalId
    role: 'AllDatabasesViewer'
    tenantId: tenant().tenantId
    principalType: 'App'
  }
}

// ── Diagnostic Settings ──
resource adxDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployAdx) {
  name: 'diag-adx-cluster'
  scope: adxCluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

// ── Outputs ──
output clusterId string = deployAdx ? adxCluster.id : ''
output clusterUri string = deployAdx ? adxCluster.properties.uri : ''
output clusterDataIngestionUri string = deployAdx ? adxCluster.properties.dataIngestionUri : ''
output clusterName string = deployAdx ? adxCluster.name : ''
output databaseName string = deployAdx ? adxDatabase.name : ''
