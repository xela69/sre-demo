targetScope = 'resourceGroup'

param workspaceId string
param deployFirewall bool = true
param firewallPublicIpName string = 'xelaAzFirewall-fwIP'
param deployVpnGw bool = false
param vpnConnectionName string = 'XelaVPNConnection'

resource firewallPublicIpExisting 'Microsoft.Network/publicIPAddresses@2024-07-01' existing = if (deployFirewall) {
  name: firewallPublicIpName
}

// ── VPN Connection diagnostic (AllMetrics only — no log categories on connections) ──
resource vpnConnectionExisting 'Microsoft.Network/connections@2024-07-01' existing = if (deployVpnGw) {
  name: vpnConnectionName
}

resource vpnConnectionDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVpnGw) {
  name: 'diag-vpnconn'
  scope: vpnConnectionExisting
  properties: {
    workspaceId: workspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
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
