// Description: Bicep module to create VNets and subnets with route tables and peering connections.
param location string
param fwPrivateIP string // Default firewall private IP, update as needed
param vnetName string
param addressSpace string
param subnetPrefixes array
param subnetNames array
param routeTableName string

// Spoke Route Table
resource routeTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: true // Prevent VPN GW from propagating on-prem routes that would bypass firewall inspection
    routes: [
      {
        name: '${routeTableName}-to-hubAzFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fwPrivateIP
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressSpace]
    }
    dhcpOptions: {
      dnsServers: [fwPrivateIP] // update with firewall IP
    }
    subnets: [
      for i in range(0, length(subnetNames)): {
        name: subnetNames[i]
        properties: {
          addressPrefixes: [subnetPrefixes[i]]
          privateEndpointNetworkPolicies: subnetNames[i] == 'privateEPSubnet' ? 'Disabled' : null
          routeTable: !contains(
              [
                'privateEPSubnet'
              ],
              subnetNames[i]
            )
            ? {
                id: routeTable.id
              }
            : null
        }
      }
    ]
  }
}
// Optional peering to a hub VNet if not deploying in a hub
// This allows spoke VNets to connect to a central hub VNet for shared services or internet
param Peering bool = true // set false for spoke VNets, true for hub VNet
param hubVnetName string
param hubVnetResourceGroup string
param hubVnetSubscriptionId string

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = if (Peering) {
  name: hubVnetName
  scope: resourceGroup(hubVnetSubscriptionId, hubVnetResourceGroup)
}
// Create peering from spoke to hub VNet
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = if (Peering) {
  name: '${vnetName}-to-${hubVnetName}-Peering'
  parent: vnet
  properties: {
    remoteVirtualNetwork: { id: hubVnet.id }
    allowVirtualNetworkAccess: true // ✓ Allow ‘HubVNet’ to access ‘SpokeVNet’
    allowForwardedTraffic: true // ✓ Allow ‘HubVNet’ to receive forwarded traffic from ‘SpokeVNet’
    allowGatewayTransit: false // spoke peering itself doesn’t host a VPNGW
    useRemoteGateways: true // set true only after hub VPN GW is deployed (deployVpnGw=true in hubmain)
  }
}

// Outputs
output vnetId string = vnet.id
output subnetIds array = [
  for name in subnetNames: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, name)
]
