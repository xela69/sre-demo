targetScope = 'resourceGroup'

param workspaceId string
param dnsresolver bool = true
param deployFirewall bool = true
param deployVpnGw bool = true
param firewallPublicIpName string = 'xelaAzFirewall-fwIP'
param vpnGatewayName string

resource dnsResolverExisting 'Microsoft.Network/dnsResolvers@2022-07-01' existing = if (dnsresolver) {
  name: 'DnsResolver'
}

resource dnsResolverDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (dnsresolver) {
  name: 'diag-dnsresolver'
  scope: dnsResolverExisting
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

resource dnsRulesetExisting 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' existing = if (dnsresolver) {
  name: 'DnsResolver-ruleset'
}

resource dnsRulesetDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (dnsresolver) {
  name: 'diag-dnsruleset'
  scope: dnsRulesetExisting
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

resource vpnGatewayExisting 'Microsoft.Network/virtualNetworkGateways@2024-07-01' existing = if (deployVpnGw) {
  name: vpnGatewayName
}

resource vpnGatewayDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVpnGw) {
  name: 'diag-vpngateway'
  scope: vpnGatewayExisting
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
