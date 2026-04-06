// vpn connection between the VPN Gateway and the on-premises network

@secure()
param vpnSharedKey string
param location string
param localgwId string
param vnpconnectionName string
@description('Name of the existing VPN Gateway')
param vpngwName string

@description('Connection options')
param enableBgp bool = false
param dpdTimeoutSeconds int = 45
@allowed(['IKEv1', 'IKEv2'])
param connectionProtocol string = 'IKEv2'
param useLocalAzureIpAddress bool = false
param usePolicyBasedTrafficSelectors bool = false
@allowed(['Default', 'InitiatorOnly', 'ResponderOnly'])
param connectionMode string = 'Default'

// Use [] to fall back to Azure defaults instead of a custom policy
@description('Custom IPsec/IKE policies; set to [] to use Azure defaults')
param ipsecPolicies array = [
  {
    saLifeTimeSeconds: 27000
    saDataSizeKilobytes: 0
    ipsecEncryption: 'GCMAES256'
    ipsecIntegrity: 'GCMAES256'
    ikeEncryption: 'AES256'
    ikeIntegrity: 'SHA256'
    dhGroup: 'DHGroup2'
    pfsGroup: 'None'
  }
]

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' existing = {
  name: vpngwName
}
resource vpnConnection 'Microsoft.Network/connections@2024-07-01' = {
  name: vnpconnectionName
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    virtualNetworkGateway1: {
      id: vpnGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: localgwId
      properties: {}
    }
    connectionType: 'IPsec'
    sharedKey: vpnSharedKey

    // new properties from portal export
    connectionProtocol: connectionProtocol
    routingWeight: 0
    enableBgp: enableBgp
    useLocalAzureIpAddress: useLocalAzureIpAddress
    usePolicyBasedTrafficSelectors: usePolicyBasedTrafficSelectors
    ipsecPolicies: ipsecPolicies
    trafficSelectorPolicies: []
    tunnelProperties: []
    expressRouteGatewayBypass: false
    enablePrivateLinkFastPath: false
    dpdTimeoutSeconds: dpdTimeoutSeconds
    connectionMode: connectionMode
    gatewayCustomBgpIpAddresses: []
  }
}
@description('The Log Analytics Workspace Resource ID')
param logAnalyticsWorkspaceId string

resource diagVpnConnection 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-vpnConnection'
  scope: vpnConnection
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}
