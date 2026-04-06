targetScope = 'resourceGroup'

param workspaceId string
param appInsightsName string
param vmInsightsDcrName string
param vmInsightsPerfDcrName string
param enableVmInsightsPerfDcr bool = true

resource appInsightsExisting 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource appInsightsDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-appinsights'
  scope: appInsightsExisting
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

resource vmInsightsDcrExisting 'Microsoft.Insights/dataCollectionRules@2022-06-01' existing = {
  name: vmInsightsDcrName
}

resource vmInsightsDcrDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-vminsights-map'
  scope: vmInsightsDcrExisting
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

resource vmInsightsPerfDcrExisting 'Microsoft.Insights/dataCollectionRules@2022-06-01' existing = if (enableVmInsightsPerfDcr) {
  name: vmInsightsPerfDcrName
}

resource vmInsightsPerfDcrDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableVmInsightsPerfDcr) {
  name: 'diag-vminsights-perf'
  scope: vmInsightsPerfDcrExisting
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
