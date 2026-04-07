//Firewall module
// vHub Firewall Setup -- https://learn.microsoft.com/en-us/azure/firewall-manager/quick-secure-virtual-hub-bicep?tabs=CLI
@description('Name of the Azure Firewall')
param firewallName string
@description('Location for all resources')
param location string
param hubVnetResourceGroup string
@description('Name of the firewall policy')
param firewallPolicyName string
@description('Public IP to use for inbound NAT rules')
param natPublicIP string
@description('Linux VM private IP address')
param linuxVMPrivIP string // Placeholder, replace with actual private IP
@description('Hub VM private IP address')
param hubVMPrivIP string // Placeholder, replace with actual private IP
@description('DNS Resolver name')
param dnsResolverName string
@description('VNet names array')
param hubVnetName string
@description('The Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string // Log Analytics Workspace ID for diagnostics
@description('The principalId of the Firewall Managed Identity')
param firewallPrincipalId string
@description('Resource ID of the user-assigned managed identity to attach to Azure Firewall')
param firewallIdentityId string

// Reference to existing hub VNet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}

// Reference to existing DNS Resolver
resource dnsResolver 'Microsoft.Network/dnsResolvers@2025-05-01' existing = {
  name: dnsResolverName
  scope: resourceGroup(hubVnetResourceGroup)
}

// Reference to existing firewall subnet
resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: 'AzureFirewallSubnet'
  parent: hubVnet
}
// Reference to existing DNS Resolver inbound endpoint
resource dnsResolverInboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2025-05-01' existing = {
  name: 'inbound'
  parent: dnsResolver
}

// Firewall Public IP
resource firewallPublicIP 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${firewallName}-fwIP'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'CPS'
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'Standard' // Use Standard SKU for Azure Firewall
    tier: 'Regional' // Use Regional tier for Azure Firewall
  }
  /*zones: [
    '1'
    '2'
    '3'
  ]*/
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${firewallName}${substring(uniqueString(resourceGroup().id), 0, 4)}')
    }
  }
}

// Firewall Policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: firewallPolicyName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${firewallIdentityId}': {}
    }
  }
  properties: {
    sku: {
      tier: 'Premium' // Correct tier or 'Standard' as needed
    }
    threatIntelMode: 'Deny' // Options: 'Alert', 'Deny', 'Off'.If you want both alert and deny, set to 'Deny' (which also logs alerts).
    dnsSettings: {
      enableProxy: true
      servers: [
        dnsResolverInboundEndpoint.properties.ipConfigurations[0].privateIpAddress
      ] // Leave blank to use Azure DNS and point DNS to Resolver
    }
    insights: {
      isEnabled: true
      retentionDays: 30
      logAnalyticsResources: {
        workspaces: [
          {
            region: location
            workspaceId: {
              id: logAnalyticsWorkspaceId
            }
          }
        ]
        defaultWorkspaceId: {
          id: logAnalyticsWorkspaceId
        }
      }
    }
    intrusionDetection: {
      mode: 'Deny'
      configuration: {
        signatureOverrides: []
        bypassTrafficSettings: []
      }
    }
  }
}

// Azure Firewall
resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: firewallName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'CPS'
    SecurityControl: 'Ignore'
  }
  /*zones: [
    '1'
    '2'
    '3' 
  ]*/
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    ipConfigurations: [
      {
        name: 'firewall-ipconfig'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: firewallPublicIP.id
          }
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}
// Variables -- for on-prem lets just enable BGP on VPNGW
var trustedAzureSubnets = [
  '10.50.0.0/20' //Hub-VNet
  '10.51.0.0/20' //Data-spoke
  '10.52.0.0/20' //Apps-spoke
  '10.53.0.0/20' //DC-spoke (onprem-spoke)
]
var trustedOnPremSubnets = [
  '10.2.1.0/24' //FortiWifi Network
  '10.6.1.0/24' //HQ IPs
  '172.16.110.0/24' //DC-1
  '172.17.111.0/24' //DC-2
  '192.168.0.0/24' //GWifi
]
var publicDnatNets = [
  natPublicIP // Home Vnet
  //'97.94.106.46' //Home Network
]
var umbrellaDnsIpAddresses = [
  '172.17.111.0/24' //onprem DNS
  '168.63.129.16' //azuredns
]
var denyPublicDnsIpAddresses = [
  // Cloudflare
  '1.1.1.1'
  '1.0.0.1'
  // Google
  '8.8.8.8'
  '8.8.4.4'
  // Quad9
  '9.9.9.9'
  '149.112.112.112'
  // OpenDNS
  '208.67.222.222'
  '208.67.220.220'
]

var BadPublicIpsAddressGroup = [
  '23.185.0.3' //block this test site -- usc.edu
  '142.251.40.46'
]
var infraServerSubnets = [
  '10.50.0.0/24' //Hub-VNet
  '10.51.0.0/24' //Data-spoke
  '10.52.0.0/24' //Apps-spoke
  '10.53.0.0/24' //DC-spoke (onprem-spoke)
]
var internetUdpPorts = ['168.61.215.74/32', '208.67.222.0/24'] //'53', '123'
var internetTcpPorts = ['52.202.184.83', '10.238.123.105'] //'25', '445', '9200', '9201'
var internetHttpPort = ['84.201.220.0/24', '104.114.79.0/24', '104.123.159.0/24', '184.25.59.0/24', '23.32.0.0/11'] //'80'
var internetHttpsPort = ['23.32.0.0/11', '23.47.72.0/24', '23.56.99.0/24'] //'443'

// --- Optional: IP Groups so you can change addresses without redeploying the policy ---
resource trustedAzureIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-trusted-azure'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: trustedAzureSubnets
  }
}

resource trustedOnPremIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-trusted-onprem'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: trustedOnPremSubnets
  }
}
resource publicDnatIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-public-dnat'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: publicDnatNets
  }
}
resource umbrellaDnsIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-umbrella-dns'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: umbrellaDnsIpAddresses
  }
}
resource infraServersIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-infra-servers'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: infraServerSubnets
  }
}
resource internetUdpPortsIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-internet-udp-ports'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: internetUdpPorts
  }
}
resource internetTcpPortsIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-internet-tcp-ports'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: internetTcpPorts
  }
}
resource internetHttpPortIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-internet-http-port'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: internetHttpPort
  }
}
resource internetHttpsPortIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-internet-https-port'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: internetHttpsPort
  }
}
resource denyPublicDnsIpGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-deny-public-dns'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: denyPublicDnsIpAddresses
  }
}
resource denyBadPublicIpsAddressGroup 'Microsoft.Network/ipGroups@2024-05-01' = {
  name: 'ipg-bad-public-ips'
  location: location
  tags: { SecurityControl: 'Ignore' }
  properties: {
    ipAddresses: BadPublicIpsAddressGroup
  }
}
/*var microsoftFqdns = [
  '*.microsoft.com'
  '*.azure.com'
  '${'*.'}${environment().suffixes.keyvaultDns}'
  '*.windows.net'
  '*.office.com'
  '*.microsoftonline.com'
  '*.live.com'
  '*.msftauth.net'
  '*.msedge.net'
  '*.bing.com'
]*/

/*var logsAnalyticFqdns = [
  '*.ods.opinsights.azure.com'
  '*.oms.opinsights.azure.com'
  '${'*.'}${environment().suffixes.storage}'
  '*.azure-automation.net'
  '*.agentsvc.azure-automation.net'
  '*.loganalytics.io'
  '*.monitor.azure.com'
]*/
// NAT Rules Collection Group temporarily testing from source public IP
resource natRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  name: 'XelaNatRules'
  parent: firewallPolicy
  dependsOn: [
    firewall
  ]
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'InboundNATRules'
        priority: 100
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        action: {
          type: 'DNAT'
        }
        rules: [
          {
            name: 'InboundHubSSH'
            ruleType: 'NatRule'
            sourceIpGroups: [publicDnatIpGroup.id]
            destinationAddresses: [
              firewallPublicIP.properties.ipAddress
            ]
            destinationPorts: [
              '2221'
            ]
            translatedAddress: linuxVMPrivIP
            translatedPort: '22'
            ipProtocols: [
              'TCP'
            ]
          }
          {
            name: 'InboundRDPHubVM'
            ruleType: 'NatRule'
            sourceIpGroups: [publicDnatIpGroup.id]
            destinationAddresses: [firewallPublicIP.properties.ipAddress]
            destinationPorts: [
              '3389'
            ]
            translatedAddress: hubVMPrivIP
            translatedPort: '3389'
            ipProtocols: [
              'TCP'
            ]
          }
          {
            name: 'InboundRDAppsVM'
            ruleType: 'NatRule'
            sourceIpGroups: [publicDnatIpGroup.id]
            destinationAddresses: [firewallPublicIP.properties.ipAddress]
            destinationPorts: [
              '33890'
            ]
            translatedAddress: hubVMPrivIP
            translatedPort: '3389'
            ipProtocols: [
              'TCP'
            ]
          }
        ]
      }
    ]
  }
}
// New rule collection with higher precedence than your broad allows
resource denyDirectDns 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  name: 'XelaDenyDirectDns'
  parent: firewallPolicy
  dependsOn: [
    natRules
  ]
  properties: {
    priority: 200 // < lower number = higher priority (before your 200s)
    ruleCollections: [
      {
        name: 'DenyDNSFromSpokes'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: { type: 'Deny' }
        rules: [
          {
            name: 'DenyDNSToInternet'
            ruleType: 'NetworkRule'
            ipProtocols: ['UDP', 'TCP']
            sourceIpGroups: [trustedAzureIpGroup.id] // spokes
            destinationIpGroups: [denyPublicDnsIpGroup.id]
            destinationPorts: ['53']
          }
        ]
      }
    ]
  }
}
// Network Rules Collection Group
resource networkRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  name: 'XelatNetworkRules'
  parent: firewallPolicy
  dependsOn: [
    denyDirectDns
  ]
  properties: {
    priority: 300
    ruleCollections: [
      {
        name: 'BlacklistBadSites' // Deny traffic to specific bad IPs-- TBD
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Deny'
        }
        rules: [
          {
            name: 'DenyToBadIP'
            ruleType: 'NetworkRule'
            sourceIpGroups: [trustedAzureIpGroup.id]
            destinationIpGroups: [denyBadPublicIpsAddressGroup.id]
            destinationPorts: [
              '80'
              '443'
            ]
            ipProtocols: [
              'TCP'
            ]
          }
        ]
      }
      {
        name: 'AllowNetworkRules'
        priority: 200
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'AllowDNSToFirewall'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceIpGroups: [trustedAzureIpGroup.id] // spokes
            destinationAddresses: [
              firewall.properties.ipConfigurations[0].properties.privateIPAddress
            ]
            destinationPorts: [
              '53'
            ]
          }
          {
            name: 'AllowDNSFirewallToResolver'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: [
              firewall.properties.ipConfigurations[0].properties.privateIPAddress
            ]
            destinationAddresses: [
              dnsResolverInboundEndpoint.properties.ipConfigurations[0].privateIpAddress
            ]
            destinationPorts: [
              '53'
            ]
          }
          /*{
            name: 'AllowFWtoPublicDNS'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'UDP'
              'TCP'
            ]
            sourceAddresses: [
              firewall.properties.ipConfigurations[0].properties.privateIPAddress
            ]
            destinationAddresses: ['1.1.1.1','8.8.8.8']
            destinationPorts: [
              '53'
            ]
          }*/ // Optional if you want FW to resolve DNS directly public DNS
          {
            name: 'AllowTrustedAzureTraffic'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
              'UDP'
              'ICMP'
            ]
            sourceIpGroups: [trustedAzureIpGroup.id]
            destinationIpGroups: [trustedAzureIpGroup.id]
            destinationPorts: [
              '22'
              '25'
              '53'
              '80'
              '88'
              '123'
              '135'
              '137'
              '139'
              '161'
              '389'
              '443'
              '445'
              '464'
              '636'
              '647'
              '1433'
              '3268'
              '3269'
              '3389'
              '5022' // AG endpoint
              '5353'
              '5671'
              '8443'
              '9191'
              '9192'
              '9389'
              '9200-9400'
              '11000-11999' // SQL MI TDS redirect
              '49152-65535'
            ] // Or restrict as needed
          }
          {
            name: 'AllowAzureToOnPrem'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
              'UDP'
              'ICMP'
            ]
            sourceIpGroups: [trustedAzureIpGroup.id]
            destinationIpGroups: [trustedOnPremIpGroup.id]
            destinationPorts: [
              '22'
              '25'
              '53'
              '80'
              '88'
              '123'
              '135'
              '137'
              '139'
              '161'
              '389'
              '443'
              '445'
              '464'
              '636'
              '647'
              '1433'
              '3268'
              '3269'
              '3389'
              '5022' // AG endpoint
              '5353'
              '5671'
              '8443'
              '9191'
              '9192'
              '9389'
              '9200-9400'
              '11000-11999' // SQL MI TDS redirect
              '49152-65535'
            ] // Or restrict as needed
          }
          {
            name: 'AllowOnPremToAzure'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
              'UDP'
              'ICMP'
            ]
            sourceIpGroups: [trustedOnPremIpGroup.id]
            destinationIpGroups: [trustedAzureIpGroup.id]
            destinationPorts: [
              '22'
              '25'
              '53'
              '80'
              '88'
              '123'
              '135'
              '137'
              '139'
              '161'
              '389'
              '443'
              '445'
              '464'
              '636'
              '647'
              '1433'
              '3268'
              '3269'
              '3389'
              '5022' // AG endpoint
              '5353'
              '5671'
              '8443'
              '9191'
              '9192'
              '9389'
              '9200-9400'
              '11000-11999' // SQL MI TDS redirect
              '49152-65535'
            ] // Or restrict as needed
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowInternetUdpPorts'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: []
            sourceIpGroups: [
              infraServersIpGroup.id
            ]
            destinationAddresses: []
            destinationIpGroups: [
              internetUdpPortsIpGroup.id
            ]
            destinationFqdns: []
            destinationPorts: [
              '53'
              '123'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowInternetTcpPorts'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: []
            sourceIpGroups: [
              infraServersIpGroup.id
            ]
            destinationAddresses: []
            destinationIpGroups: [
              internetTcpPortsIpGroup.id
            ]
            destinationFqdns: []
            destinationPorts: [
              '445'
              '9200'
              '9201'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowHTTP_TCP'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: []
            sourceIpGroups: [
              infraServersIpGroup.id
            ]
            destinationAddresses: []
            destinationIpGroups: [
              internetHttpPortIpGroup.id
            ]
            destinationFqdns: []
            destinationPorts: [
              '80'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowHTTPS_UDP'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: []
            sourceIpGroups: [
              infraServersIpGroup.id
            ]
            destinationAddresses: []
            destinationIpGroups: [
              internetHttpsPortIpGroup.id
            ]
            destinationFqdns: []
            destinationPorts: [
              '443'
            ]
          }
        ]
      }
    ]
  }
}
@description('TEMPORARY break-glass to let the firewall talk to public DNS directly')
param enableFwPublicDns bool = false

resource allowFwPublicDns 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = if (enableFwPublicDns) {
  name: 'XelaBreakglassPublicDns'
  parent: firewallPolicy
  dependsOn: [
    networkRules
  ]
  properties: {
    priority: 320
    ruleCollections: [
      {
        name: 'AllowFWtoPublicDNS'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: { type: 'Allow' }
        rules: [
          {
            name: 'AllowFWtoPublicDNS'
            ruleType: 'NetworkRule'
            ipProtocols: ['UDP', 'TCP']
            sourceAddresses: [firewall.properties.ipConfigurations[0].properties.privateIPAddress]
            destinationAddresses: ['1.1.1.1', '8.8.8.8']
            destinationPorts: ['53']
          }
        ]
      }
    ]
  }
}
// Application Rules Collection Group
resource applicationRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  name: 'XelaApplicationRules'
  parent: firewallPolicy
  dependsOn: enableFwPublicDns
    ? [
        allowFwPublicDns
      ]
    : [
        networkRules
      ]
  properties: {
    priority: 400
    ruleCollections: [
      {
        name: 'DenyWebFilterTraffic'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Deny'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'DenyWebFilterSites'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: [
              'alcoholandtobacco'
              'childabuseimages'
              'criminalactivity'
              'datingandpersonals'
              'gambling'
              'hacking'
              'hateandintolerance'
              'illegaldrug'
              'illegalsoftware'
              'lingerieandswimsuits'
              'marijuana'
              'nudity'
              'pornographyandsexuallyexplicit'
            ]
            targetFqdns: []
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: [
              trustedAzureIpGroup.id
            ]
            httpHeadersToInsert: []
          }
        ]
      }
      {
        name: 'AllowApplicationRules'
        priority: 200
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AllowWebTraffic'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              '*'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: [
              trustedAzureIpGroup.id
            ]
            httpHeadersToInsert: []
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AllowMicrosoftService'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: [
              'AppServiceEnvironment'
              'AzureBackup'
              'AzureKubernetesService'
              'HDInsight'
              'MicrosoftActiveProtectionService'
              'MicrosoftIntune'
              'Windows365'
              'WindowsDiagnostics'
              'WindowsUpdate'
              'WindowsVirtualDesktop'
              'citrixHdxPlusForWindows365'
              'Office365.Exchange.Optimize'
              'Office365.Exchange.Default.Required'
              'Office365.Exchange.Allow.Required'
              'Office365.Skype.Allow.Required'
              'Office365.Skype.Default.Required'
              'Office365.Skype.Default.NotRequired'
              'Office365.SharePoint.Optimize'
              'Office365.SharePoint.Default.NotRequired'
              'Office365.SharePoint.Default.Required'
              'Office365.Common.Allow.Required'
              'Office365.Common.Default.Required'
              'Office365.Common.Default.NotRequired'
            ]
            webCategories: []
            targetFqdns: []
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: [
              trustedAzureIpGroup.id
            ]
            httpHeadersToInsert: []
          }
        ]
      }
    ]
  }
}

// Reference to existing route tables for hubvnet
param routeTableName string
resource hubRouteTable 'Microsoft.Network/routeTables@2024-07-01' existing = {
  name: routeTableName
  scope: resourceGroup(hubVnetResourceGroup)
}

// ==================== RBAC Role Assignments for Firewall Route Table====================
resource firewallRouteTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hubRouteTable.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c', firewallPrincipalId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    ) // Network Contributor
    principalId: firewallPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 🔹 Diagnostic Settings for Azure Firewall
param diagnosticsName string = 'fw-log-analytics'

resource fwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticsName
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AZFWNetworkRule'
        enabled: true
      }
      {
        category: 'AZFWApplicationRule'
        enabled: true
      }
      {
        category: 'AZFWNatRule'
        enabled: true
      }
      {
        category: 'AZFWThreatIntel'
        enabled: true
      }
      {
        category: 'AZFWIdpsSignature'
        enabled: true
      }
      {
        category: 'AZFWDnsQuery'
        enabled: true
      }
      {
        category: 'AZFWFqdnResolveFailure'
        enabled: true
      }
      {
        category: 'AZFWFatFlow'
        enabled: true
      }
      {
        category: 'AZFWFlowTrace'
        enabled: true
      }
      {
        category: 'AZFWApplicationRuleAggregation'
        enabled: true
      }
      {
        category: 'AZFWNetworkRuleAggregation'
        enabled: true
      }
      {
        category: 'AZFWNatRuleAggregation'
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
output rulesDeployment string = 'Rules deployed'
output firewallId string = firewall.id
output firewallPublicIp string = firewallPublicIP.properties.ipAddress
output firewallPrivateIPAddress string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallFqdn string = firewallPublicIP.properties.dnsSettings.fqdn
