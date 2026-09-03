// Description: Bicep module to create VNets and subnets with route tables and peering connections.
param location string
param fwPrivateIP string // Default firewall private IP, update as needed
param vnetName string
param addressSpace string
param subnetPrefixes array
param subnetNames array
param routeTableName string
@description('Log Analytics workspace resource ID for VNet diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

// Spoke Route Table
module routeTable 'br/public:avm/res/network/route-table:0.4.0' = {
  name: '${routeTableName}-avm'
  params: {
    name: routeTableName
    location: location
    tags: { SecurityControl: 'Ignore' }
    disableBgpRoutePropagation: true
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

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = if (Peering) {
  name: hubVnetName
  scope: resourceGroup(hubVnetSubscriptionId, hubVnetResourceGroup)
}

module vnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: '${vnetName}-avm'
  params: {
    name: vnetName
    location: location
    tags: { SecurityControl: 'Ignore' }
    addressPrefixes: [addressSpace]
    dnsServers: [fwPrivateIP]
    subnets: [
      for i in range(0, length(subnetNames)): {
        name: subnetNames[i]
        addressPrefixes: [subnetPrefixes[i]]
        privateEndpointNetworkPolicies: subnetNames[i] == 'privateEPSubnet' ? 'Disabled' : null
        routeTableResourceId: subnetNames[i] == 'privateEPSubnet' ? null : routeTable.outputs.resourceId
      }
    ]
    peerings: Peering
      ? [
          {
            name: '${vnetName}-to-${hubVnetName}-Peering'
            remoteVirtualNetworkResourceId: hubVnet.id
            allowVirtualNetworkAccess: true
            allowForwardedTraffic: true
            allowGatewayTransit: false
            useRemoteGateways: true
          }
        ]
      : []
    diagnosticSettings: empty(logAnalyticsWorkspaceId)
      ? []
      : [
          {
            workspaceResourceId: logAnalyticsWorkspaceId
            logAnalyticsDestinationType: 'Dedicated'
            logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
            metricCategories: [{ category: 'AllMetrics' }]
          }
        ]
  }
}
// Optional w to a hub VNet if not deploying in a hub
// This allows spoke VNets to connect to a central hub VNet for shared services or internet
param Peering bool = true // set false for spoke VNets, true for hub VNet
param hubVnetName string
param hubVnetResourceGroup string
param hubVnetSubscriptionId string

// Outputs
output vnetId string = vnet.outputs.resourceId
output subnetIds array = vnet.outputs.subnetResourceIds
