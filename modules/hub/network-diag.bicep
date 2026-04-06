targetScope = 'resourceGroup'

param workspaceId string
param deployFirewall bool = true
param firewallPublicIpName string = 'xelaAzFirewall-fwIP'

resource firewallPublicIpExisting 'Microsoft.Network/publicIPAddresses@2024-07-01' existing = if (deployFirewall) {
  name: firewallPublicIpName
}

resource firewallPublicIpDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployFirewall) {
  name: 'diag-azfw-pip'
  scope: firewallPublicIpExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'DDoSProtectionNotifications'
        enabled: true
      }
      {
        category: 'DDoSMitigationFlowLogs'
        enabled: true
      }
      {
        category: 'DDoSMitigationReports'
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
