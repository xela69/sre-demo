param location string
param hubVnetName string // Default hub VNet name
param addressSpace string
param subnetPrefixes array
param subnetNames array
param routeTableName string
param fwPrivateIP string
param enableFirewallRouting bool = true
param logAnalyticsWorkspaceId string = ''
param enableDiagnostics bool = true
param Peering bool = true //only enable when you have deployed spokes
// All Azure-side address spaces (hub + spokes) — used in GatewaySubnet RT to force
// on-prem→Azure traffic through the firewall for symmetric stateful inspection
param azureAddressSpaces array = [
  '10.50.0.0/20' // hub
  '10.51.0.0/20' // apps-spoke
  '10.52.0.0/20' // data-spoke
  '10.53.0.0/20' // dc-spoke
]

// Route tables per Spoke region 
resource hubRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: routeTableName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: true // Prevent VPN GW BGP from advertising on-prem routes that would bypass firewall
    routes: enableFirewallRouting
      ? [
          // ── All traffic through firewall for inspection (including Azure → On-prem) ────
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

// GatewaySubnet route table — forces on-prem→Azure traffic through Azure Firewall so the
// firewall has state for BOTH directions (fixes asymmetric routing for on-prem-initiated sessions).
// Only specific Azure address prefixes are added; 0.0.0.0/0 must NOT be added to GatewaySubnet.
resource gatewaySubnetRouteTable 'Microsoft.Network/routeTables@2024-07-01' = if (enableFirewallRouting) {
  name: '${routeTableName}-gw'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: false // must stay false — GatewaySubnet needs BGP routes to function
    routes: [
      for (prefix, i) in azureAddressSpaces: {
        name: 'gw-to-fw-azure-${i}'
        properties: {
          addressPrefix: prefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fwPrivateIP
        }
      }
    ]
  }
}

// Firewall subnet route table — Azure requires 0.0.0.0/0 → Internet on AzureFirewallSubnet
resource firewallSubnetRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: '${routeTableName}-fw'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    disableBgpRoutePropagation: false // BGP propagation enabled: VPN GW injects on-prem routes into firewall subnet effective routes
    routes: [
      // Azure mandate: AzureFirewallSubnet must have 0.0.0.0/0 → Internet
      // On-prem routes are handled via BGP propagation from VPN GW (not custom UDRs — unsupported on this subnet)
      {
        name: 'fw-subnet-to-internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
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
    CostControl: 'Ignore'
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
            : subnetNames[i] == 'GatewaySubnet' && enableFirewallRouting
                ? {
                    id: gatewaySubnetRouteTable.id
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
