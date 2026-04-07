// VPN gw module
param location string
param vpngwName string // Name of the VPN Gateway
param hubVnetName string
param vpngwSubnetName string
param localGwName string
param remoteVpnIp string
param logAnalyticsWorkspaceId string // Log Analytics Workspace ID for diagnostics
@description('Resource ID of the user-assigned managed identity for the VPN GW')
param vpngwIdentityId string
@description('Principal/Object ID of the VPN GW UAMI (from mgnt-Identity outputs)')
param vpngwPrincipalId string

// Reference existing VNet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: hubVnetName // Use the second VNet for VPN Gateway
}

// Reference an existing GatewaySubnet
resource vpngwSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  parent: hubVnet
  name: vpngwSubnetName // Use the GatewaySubnet
}
// Create a public IP for the VPN Gateway
resource vpngwPublicIP 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: toLower('${vpngwName}pip${substring(uniqueString(resourceGroup().id), 0, 4)}')
  location: location
  tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('xelagw${substring(uniqueString(resourceGroup().id), 0, 3)}')
    }
  }
}
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' = {
  name: '${vpngwName}${take(uniqueString(resourceGroup().id), 4)}'
  location: location
  tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vpngwIdentityId}': {}
    }
  }
  properties: {
    ipConfigurations: [
      {
        name: 'gw-ipconfig'
        properties: {
          subnet: {
            id: vpngwSubnet.id
          }
          publicIPAddress: {
            id: vpngwPublicIP.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    vpnGatewayGeneration: 'Generation1'
  }
}
// local network gateway
resource localGw 'Microsoft.Network/localNetworkGateways@2024-07-01' = {
  name: toLower('${localGwName}')
  location: location
  tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  dependsOn: [
    vpnGateway
  ]
  properties: {
    gatewayIpAddress: remoteVpnIp // Use the public IP address assigned to on-premises VPN device
    localNetworkAddressSpace: {
      addressPrefixes: [
        '10.6.1.0/24' //HQ IPs
        '172.16.110.0/24' // DC-1
        '172.17.111.0/24' //DC-2
        '10.2.1.0/24' // WIFI LAN
      ] // add more as needed
    }
    /*/ ---- Add this block to enable BGP ----
    bgpSettings: {
      asn: 65010                   // <-- Your on-prem FortiGate ASN
      bgpPeeringAddress: '169.254.21.2'   // Forti’s tunnel IP to FortiGate's BGP peer IP (tunnel interface)
    }
    /*/
  }
}
// ==================== RBAC Role Assignments for VPNGW ====================
@description('List of Key Vault role short names to assign (e.g., "SecretsUser", "Reader")')
param roles array = [
  'NetworkContributor'
  'Reader'
  'MonitoringReader'
]

var roleDefinitionMap = {
  NetworkContributor: 'e022efe7-f5ba-4159-bbe4-b44f577e9b61'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  MonitoringReader: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
}

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleName in roles: {
    name: guid(vpnGateway.id, vpngwIdentityId, roleName)
    scope: vpnGateway
    properties: {
      principalId: vpngwPrincipalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionMap[roleName])
      principalType: 'ServicePrincipal'
    }
  }
]

// Diagnostic settings for VPN Gateway Public IP
@description('Name of the diagnostic setting Public IP')
param IPDiagSettingName string = 'diagPIP-${vpngwName}'
resource vpngwPublicIPDiagnostic 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: IPDiagSettingName
  scope: vpngwPublicIP
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'DDoSProtectionNotifications'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'DDoSMitigationFlowLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}
// Diagnostic settings for VPN Gateway
@description('Name of the diagnostic setting (must be unique per resource).')
param vpnDiagSettingName string = 'diagVPN-${vpngwName}'

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: vpnDiagSettingName
  scope: vpnGateway
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'TunnelDiagnosticLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'RouteDiagnosticLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'IKEDiagnosticLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'P2SDiagnosticLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
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
// Outputs
output vpngwId string = vpnGateway.id
output localgwId string = localGw.id
output vpngwName string = vpnGateway.name
output localgwName string = localGw.name
output localgwPublicIP string = vpngwPublicIP.properties.ipAddress
output remoteVpnIp string = remoteVpnIp
