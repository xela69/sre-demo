targetScope = 'resourceGroup'

param workspaceId string
param appInsightsName string
param vmInsightsDcrName string
param vmInsightsPerfDcrName string
param enableVmInsightsPerfDcr bool = true

@description('Name of the SRE portal managed identity in this RG. Blank to skip the lock.')
param sreAgentIdentityName string = ''

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

// ── SRE Agent identity protection ──
// Locks the portal-managed identity so redeployments can't delete it and cause
// RoleAssignmentUpdateNotPermitted on the next run (principal ID would change).
resource sreAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!empty(sreAgentIdentityName)) {
  name: sreAgentIdentityName
}

resource sreAgentIdentityLock 'Microsoft.Authorization/locks@2020-05-01' = if (!empty(sreAgentIdentityName)) {
  name: 'sre-agent-identity-lock'
  scope: sreAgentIdentity
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects SRE portal managed identity from deletion during IaC redeployment.'
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
