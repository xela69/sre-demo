// DNS Resolver info -- https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview
@description('Name of the DNS Private Resolver')
param resolverName string
param onPremDnsServer1 string
//param onPremDnsServer2 string
//param onPremDnsServer3 string
param location string
@description('Hub VNet where the resolver will reside')
param hubVnetName string
param hubVnetResourceGroup string

//@description('Spoke VNet to link ruleset to (optional), only needed if spoke VNet will be using the resolverIP')
//param spokeVnetName string

@description('Name of the inbound and outbound subnets in hub VNet')
param inboundSubnetName string = 'dns-inbound'
param outboundSubnetName string = 'dns-outbound'
/*/ Public resolvers for “Internet”
var publicResolvers = [
  { ipAddress: '1.1.1.1', port: 53 }
  { ipAddress: '8.8.8.8', port: 53 }
]*/

@description('List of forwarding rules (domain, destination IP)')
param forwardingRules array = [
  {
    domainName: 'onprem.xelatech.net.' //<domain or subdomain, e.g. // note the trailing dot
    targetDnsServers: [
      {
        ipAddress: onPremDnsServer1
        port: 53
      }
    ]
  }
]

/*/ Forward partner SQL FQDNs (exact) to public DNS
var sqlDomain = '${environment().suffixes.sqlServerHostname}.'
var partnerSqlFqdns = [
  'sql-uat-abl-hw-cps.${sqlDomain}'
  'sql-prod-abl-hw-cps.${sqlDomain}'
]*/

// Reference existing resources
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}
resource inboundSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: inboundSubnetName
  parent: hubVnet
}
resource outboundSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: outboundSubnetName
  parent: hubVnet
}
resource resolver 'Microsoft.Network/dnsResolvers@2025-05-01' = {
  name: resolverName
  location: location
  tags: {
    Service: 'DNS'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
  }
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2025-05-01' = {
  name: 'inbound'
  parent: resolver
  location: location
  tags: {
    Service: 'DNS'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
  }
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: inboundSubnet.id
        }
      }
    ]
  }
}

resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2025-05-01' = {
  name: 'outbound'
  parent: resolver
  location: location
  tags: {
    Service: 'DNS'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
  }
  properties: {
    subnet: {
      id: outboundSubnet.id
    }
  }
}

resource dnsRuleset 'Microsoft.Network/dnsForwardingRulesets@2025-05-01' = {
  name: '${resolverName}-ruleset'
  location: location
  tags: {
    Service: 'DNS'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
  }
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outboundEndpoint.id
      }
    ]
  }
}

resource forwardingRuleResources 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2025-05-01' = [
  for rule in forwardingRules: {
    // Build a stable, readable name: rule-xelatech-net (no trailing dot)
    name: 'rule-${replace(endsWith(rule.domainName, '.') ? substring(rule.domainName, 0, length(rule.domainName) - 1) : rule.domainName, '.', '-') }'
    parent: dnsRuleset
    properties: {
      // Normalize the domain to an FQDN (always end with a dot)
      domainName: endsWith(rule.domainName, '.') ? rule.domainName : '${rule.domainName}.'
      targetDnsServers: rule.targetDnsServers
      forwardingRuleState: 'Enabled'
    }
  }
]
/*resource fwdPartnerSql 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2025-05-01' = [for name in partnerSqlFqdns: {
  name: 'partner-${replace(name, '.', '-')}'
  parent: dnsRuleset
  properties: {
    domainName: name
    targetDnsServers: publicResolvers
    forwardingRuleState: 'Enabled'
  }
}]
// 3) Send common public TLDs to public DNS (so Azure VMs use 1.1.1.1/8.8.8.8 for “most Internet”)
// DO NOT include 'windows.net.' here (so Azure PE zones under *.privatelink.* keep resolving via Azure)
var publicTlds = [
  'com.'
  'net.'
  'org.'
  'io.'
  'gov.'
]
resource fwdTlds 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2025-05-01' = [for tld in publicTlds: {
  name: 'tld-${substring(tld, 0, length(tld)-1)}'
  parent: dnsRuleset
  properties: {
    domainName: tld
    targetDnsServers: publicResolvers
    forwardingRuleState: 'Enabled'
  }
}]*/

// Link the HUB VNet to the forwarding ruleset
resource hubRulesetVnetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2025-05-01' = {
  name: '${resolverName}-link-${hubVnetName}'
  parent: dnsRuleset
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
    // optional metadata tags you can query later
    metadata: {
      role: 'hub'
    }
  }
}

/*/ Optional link to a spoke VNet if not using the firewall PrivateIP
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (spokeVnetName != '') {
  name: spokeVnetName
}
resource rulesetVnetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2023-07-01-preview' = if (spokeVnetName != '') {
  name: '${resolverName}-link-${spokeVnetName}'
  parent: dnsRuleset
  properties: {
    virtualNetwork: {
      id: spokeVnet.id
    }
    metadata: {
      environment: 'production'
    }
  }
}*/
// dns resolver outputs
output resolverId string = resolver.id
output resolverName string = resolver.name
output inboundEndpointIp string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
output outboundEndpointId string = outboundEndpoint.id
output rulesetId string = dnsRuleset.id
output inboundSubnetId string = inboundSubnet.id
output outboundSubnetId string = outboundSubnet.id
// ======== Review this code

/*/ Public resolvers to use
var publicResolvers = [
  { ipAddress: '1.1.1.1', port: 53 }
  { ipAddress: '8.8.8.8', port: 53 }
]

// Forward partner SQL (UAT)
resource fwdPartnerSqlUat 'Microsoft.Network/dnsForwardingRulesets/dnsForwardingRules@2025-05-01' = {
  name: 'partner-sql-uat-to-public'
  parent: dnsRuleset
  properties: {
    domainName: 'sql-uat-abl-hw-cps.database.windows.net.' // exact FQDN + trailing dot
    targetDnsServers: publicResolvers
    enabled: true
  }
}

// Forward partner SQL (PROD)
resource fwdPartnerSqlProd 'Microsoft.Network/dnsForwardingRulesets/dnsForwardingRules@2025-05-01' = {
  name: 'partner-sql-prod-to-public'
  parent: dnsRuleset
  properties: {
    domainName: 'sql-prod-abl-hw-cps.database.windows.net.' // exact FQDN + trailing dot
    targetDnsServers: publicResolvers
    enabled: true
  }
}*/
// these two resources exist outside my tenant
//Resolve-DnsName sql-uat-abl-hw-cps.database.windows.net -Server 208.67.222.222 # 208.67.222.222 this a privateEP on other tenant
//Resolve-DnsName sql-prod-abl-hw-cps.database.windows.net -Server 10.52.0.24 
