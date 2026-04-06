param location string
param hubVnetName string // Default hub VNet name
param addressSpace string
param subnetPrefixes array
param subnetNames array
param routeTableName string
param vpnGwRouteTableName string
param fwPrivateIP string
param enableFirewallRouting bool = true
param logAnalyticsWorkspaceId string = ''
param enableDiagnostics bool = true
param Peering bool = false //only enable when you have deployed spokes

// Route tables per Spoke region 
resource hubRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: routeTableName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: true // Static routing only (no BGP)
    routes: enableFirewallRouting
      ? [
          // ── On-prem prefixes: route through firewall for inspection ────
          {
            name: '${routeTableName}-to-onprem-fortiwifi'
            properties: {
              addressPrefix: '10.2.1.0/24' // FortiWifi Network
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          {
            name: '${routeTableName}-to-onprem-hq'
            properties: {
              addressPrefix: '10.6.1.0/24' // HQ IPs
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          {
            name: '${routeTableName}-to-onprem-dc1'
            properties: {
              addressPrefix: '172.16.110.0/24' // DC-1
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          {
            name: '${routeTableName}-to-onprem-dc2'
            properties: {
              addressPrefix: '172.17.111.0/24' // DC-2
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          // ── Spoke-to-spoke: route through firewall for inspection ────
          {
            name: '${routeTableName}-to-spoke-apps'
            properties: {
              addressPrefix: '10.51.0.0/20' // Apps Spoke (AppsRG-VNet)
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          {
            name: '${routeTableName}-to-spoke-data'
            properties: {
              addressPrefix: '10.52.0.0/20' // Data Spoke (DataRG-VNet)
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
          // ── Default route: all other traffic through firewall for inspection ────
          {
            name: '${routeTableName}-to-hubAzFirewall'
            properties: {
              addressPrefix: '0.0.0.0/0'
              nextHopType: 'VirtualAppliance'
              nextHopIpAddress: fwPrivateIP
            }
          }
        ]
      : []
  }
}
// Note: GatewaySubnet does NOT use UDRs; it relies on system routes only.
// This table is kept for reference but not assigned to any subnet.
resource hubVpnGatewayTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: vpnGwRouteTableName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: true // Static routing only (no BGP)
    routes: [] // Empty; GatewaySubnet uses system routes
  }
}

// ── Route table for AzureFirewallSubnet to forward on-prem traffic to VPN gateway ────
// ── AzureFirewallSubnet route table: forward on-prem traffic to VPN gateway ────
// Purpose: After firewall inspects on-prem-destined traffic, it needs to know how to reach on-prem.
// Answer: Through the VPN Gateway (via IPsec tunnel).
resource firewallSubnetRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: '${routeTableName}-fw-subnet'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: true // Static routing only (no BGP)
    routes: enableFirewallRouting
      ? [
          {
            name: 'fw-to-onprem-fortiwifi'
            properties: {
              addressPrefix: '10.2.1.0/24'
              nextHopType: 'VirtualNetworkGateway'
            }
          }
          {
            name: 'fw-to-onprem-hq'
            properties: {
              addressPrefix: '10.6.1.0/24'
              nextHopType: 'VirtualNetworkGateway'
            }
          }
          {
            name: 'fw-to-onprem-dc1'
            properties: {
              addressPrefix: '172.16.110.0/24'
              nextHopType: 'VirtualNetworkGateway'
            }
          }
          {
            name: 'fw-to-onprem-dc2'
            properties: {
              addressPrefix: '172.17.111.0/24'
              nextHopType: 'VirtualNetworkGateway'
            }
          }
        ]
      : []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: hubVnetName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [addressSpace]
    }
    dhcpOptions: enableFirewallRouting
      ? {
          dnsServers: [fwPrivateIP]
        }
      : null
    subnets: [
      for i in range(0, length(subnetNames)): {
        name: subnetNames[i]
        properties: {
          addressPrefixes: [subnetPrefixes[i]]
          privateEndpointNetworkPolicies: subnetNames[i] == 'privateEPSubnet' ? 'Disabled' : null
          routeTable: subnetNames[i] == 'AzureFirewallSubnet'
            ? {
                id: firewallSubnetRouteTable.id
              }
            : !contains(
                  [
                    'GatewaySubnet'
                    'privateEPSubnet'
                    'AzureBastionSubnet'
                    'appGatewaySubnet'
                    'dns-inbound'
                    'dns-outbound'
                  ],
                  subnetNames[i]
                )
                ? {
                    id: hubRouteTable.id
                  }
                : null
          delegations: contains(['dns-inbound', 'dns-outbound'], subnetNames[i])
            ? [
                {
                  name: 'dnsDelegation-${subnetNames[i]}'
                  properties: {
                    serviceName: 'Microsoft.Network/dnsResolvers'
                  }
                }
              ]
            : contains(['containerAppSubnet'], subnetNames[i])
                ? [
                    {
                      name: 'containerAppsDelegation-${subnetNames[i]}'
                      properties: {
                        serviceName: 'Microsoft.App/containerApps'
                      }
                    }
                  ]
                : null
        }
      }
    ]
  }
}

// Create peering from AppsVnet to hub VNet
resource appsvnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = if (Peering) {
  name: 'AppsRG-VNet'
  scope: resourceGroup('86d55e1e-4ca9-4ddd-85df-2e7633d77534', 'AppsRG')
}
// Create peering from DataVnet to hub VNet
resource datavnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = if (Peering) {
  name: 'DataRG-VNet'
  scope: resourceGroup('8cbc59b1-7d9e-4cf1-8851-58fffe68fb79', 'DataRG')
}

resource hubToAppsPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = if (Peering) {
  name: 'hub-to-Apps-VNet-peering'
  parent: vnet
  properties: {
    remoteVirtualNetwork: {
      id: appsvnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true // Enable gateway transit for VPNGW
    useRemoteGateways: false
  }
}
resource hubToDataPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = if (Peering) {
  name: 'hub-to-Data-VNet-peering'
  parent: vnet
  properties: {
    remoteVirtualNetwork: {
      id: datavnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true // Enable gateway transit for VPNGW
    useRemoteGateways: false
  }
}

resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'diag-${vnet.name}'
  scope: vnet
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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

// Outputs
output vnetId string = vnet.id
output subnetIds array = [
  for name in subnetNames: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnetName, name)
]
output privateEPSubnetIds array = [
  for name in subnetNames: name == 'privateEPSubnet'
    ? resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnetName, name)
    : null
]
output routeTableId string = hubRouteTable.name
