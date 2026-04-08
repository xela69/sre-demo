// Standalone VNet peering module — kept separate from hubvnet.bicep so that a
// cross-subscription RBAC failure here cannot roll back VNet / route-table changes.
// Requires Network Contributor (or Virtual Network Contributor) on the remote VNet.

param hubVnetName string
param spokeVnetName string
param spokeSubId string
param spokeRgName string
param allowGatewayTransit bool = true
param useRemoteGateways bool = false

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: hubVnetName
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: spokeVnetName
  scope: resourceGroup(spokeSubId, spokeRgName)
}

resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = {
  name: 'hub-to-${spokeVnetName}-peering'
  parent: hubVnet
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
  }
}
