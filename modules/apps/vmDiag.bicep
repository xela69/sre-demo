// ── vmDiag.bicep ─────────────────────────────────────────────────────────────
// Deploys Microsoft.Insights/diagnosticSettings on a VM.
// Must be called as a module scoped to the VM's resource group from a
// subscription-scoped parent (appsmain.bicep).
// Captures host-level AllMetrics → Log Analytics.
// Guest logs + perf counters are handled by AMA + DCR at the parent level.
// ─────────────────────────────────────────────────────────────────────────────
param vmName string

@description('Log Analytics workspace resource ID.')
param logAnalyticsWorkspaceId string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource vmDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${vmName}'
  scope: vm
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: { enabled: false, days: 0 }
      }
    ]
  }
}
