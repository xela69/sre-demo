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
// All MCAPS-side address spaces (hub + spokes) used in GatewaySubnet routes to force
// TenantB-to-MCAPS traffic through the firewall for symmetric stateful inspection.
param azureAddressSpaces array = [
  '10.50.0.0/20' // hub
  '10.52.0.0/20' // apps-spoke
  // '10.53.0.0/20' // dc-spoke — uncomment when deployed
]
// Route tables per Spoke region 
module hubRouteTable 'br/public:avm/res/network/route-table:0.4.0' = if (enableFirewallRouting) {
  name: '${routeTableName}-avm'
  params: {
    name: routeTableName
    location: location
    tags: {
      Service: 'Network'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
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

// GatewaySubnet route table — forces on-prem→Azure traffic through Azure Firewall so the
// firewall has state for BOTH directions (fixes asymmetric routing for on-prem-initiated sessions).
// Only specific Azure address prefixes are added; 0.0.0.0/0 must NOT be added to GatewaySubnet.
module gatewaySubnetRouteTable 'br/public:avm/res/network/route-table:0.4.0' = if (enableFirewallRouting) {
  name: '${routeTableName}-gw-avm'
  params: {
    name: '${routeTableName}-gw'
    location: location
    tags: {
      Service: 'Network'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
    disableBgpRoutePropagation: false
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

// Firewall subnet route table — Azure requires 0.0.0.0/0 → Internet on AzureFirewallSubnet.
// On-prem prefixes are injected automatically via gateway route propagation (disableBgpRoutePropagation: false).
// This works even when VPN GW BGP is disabled — gateway propagation uses LNG address spaces, not BGP.
module firewallSubnetRouteTable 'br/public:avm/res/network/route-table:0.4.0' = {
  name: '${routeTableName}-fw-avm'
  params: {
    name: '${routeTableName}-fw'
    location: location
    tags: {
      Service: 'Network'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
    disableBgpRoutePropagation: false
    routes: [
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

module vnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: '${hubVnetName}-avm'
  params: {
    name: hubVnetName
    location: location
    tags: {
      Service: 'Network'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
    addressPrefixes: [addressSpace]
    dnsServers: enableFirewallRouting ? [fwPrivateIP] : []
    subnets: [
      for i in range(0, length(subnetNames)): {
        name: subnetNames[i]
        addressPrefixes: [subnetPrefixes[i]]
        privateEndpointNetworkPolicies: subnetNames[i] == 'privateEPSubnet' ? 'Disabled' : null
        routeTableResourceId: subnetNames[i] == 'AzureFirewallSubnet'
          ? firewallSubnetRouteTable.outputs.resourceId
          : subnetNames[i] == 'GatewaySubnet' && enableFirewallRouting
              ? gatewaySubnetRouteTable!.outputs.resourceId
              : enableFirewallRouting && !contains(
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
                  ? hubRouteTable!.outputs.resourceId
                  : null
        delegation: contains(['dns-inbound', 'dns-outbound'], subnetNames[i])
          ? 'Microsoft.Network/dnsResolvers'
          : contains(['containerAppSubnet'], subnetNames[i]) ? 'Microsoft.App/containerApps' : null
      }
    ]
    diagnosticSettings: enableDiagnostics && !empty(logAnalyticsWorkspaceId)
      ? [
          {
            workspaceResourceId: logAnalyticsWorkspaceId
            logAnalyticsDestinationType: 'Dedicated'
            logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
            metricCategories: [{ category: 'AllMetrics' }]
          }
        ]
      : []
  }
}

// Outputs
output vnetId string = vnet.outputs.resourceId
output subnetIds array = vnet.outputs.subnetResourceIds
output privateEPSubnetIds array = [
  for name in subnetNames: name == 'privateEPSubnet'
    ? resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnetName, name)
    : null
]
output routeTableId string = hubRouteTable!.outputs.name
