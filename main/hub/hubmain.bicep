// Hub main Bicep file for deploying the landing zone resources in the hub subscription
param deployHubVnet bool = true
param deploySecurity bool = true // Toggle to deploy security resources
param deployAcr bool = true
param deploylogsAnalytics bool = true // Toggle to deploy Log Analytics workspace
param deployPrivZones bool = true
param dnsresolver bool = true
param deployStorage bool = true
param deployVM bool = true // Toggle to deploy Hub VM
param enableVmInsightsPerfDcr bool = true // Optional: deploy a perf-focused DCR for VM Insights detailed metrics
param deployBastion bool = false // Toggle to deploy Bastion Host
param deployVpnGw bool = true // Toggle to deploy VPN Gateway
param deployFirewall bool = true // Toggle to deploy Azure Firewall

param natPublicIP string //injected securely from main.bicep for NAT testing
param accessKey string
param sshPublicKey string //The SSH public key content injected securely from main.bicep or pipeline
@description('Optional Entra object ID for a human Key Vault administrator. Leave empty to skip this role assignment.')
param keyVaultAdminObjectId string = ''
targetScope = 'subscription' // Required for resource group deployments

// Hub VNet parameters
param hubRgName string = 'hubRG'
param hubVnetName string = 'hubRG-VNet'
param routeTableName string = 'hubRouteTable'
param vmRgName string = 'hubRG-VM'
param hubAcrRgName string = 'hubRG-Acr'
param securityRgName string = 'hubRG-Security'
param monitorRgName string = 'hubRG-Monitor'
param hubStorageRgName string = 'hubRG-Storage'
param hubAddressSpace string = '10.50.0.0/20'
param firewallPrivateIP string = '10.50.4.4' // Static firewall private IP in AzureFirewallSubnet
param hubLocation string = 'westus2'
//param hubSubId string = '155abeb8-c0a9-4927-a455-986a03026829'

var appInsightsName = 'xelaAppsInsight${take(uniqueString(monitorRgName), 4)}'
var vmInsightsDcrName = 'MSVMI-xelaLogs${take(uniqueString(monitorRgName), 4)}'
var vmInsightsPerfDcrName = 'MSVMI-Perf-xelaLogs${take(uniqueString(monitorRgName), 4)}'
var hubVmName = 'hubVM${toLower(take(uniqueString(vmRgName), 4))}'
var linuxVmName = 'LinuxVM${take(uniqueString(vmRgName), 4)}'
var firewallPublicIpName = 'xelaAzFirewall-fwIP'

param hubSubnets array = [
  { name: 'vmSubnet', prefix: '10.50.0.0/24' }
  { name: 'dns-inbound', prefix: '10.50.1.0/27' }
  { name: 'dns-outbound', prefix: '10.50.2.0/27' }
  { name: 'GatewaySubnet', prefix: '10.50.3.0/27' }
  { name: 'AzureFirewallSubnet', prefix: '10.50.4.0/26' }
  { name: 'AzureBastionSubnet', prefix: '10.50.5.0/27' }
  { name: 'appGatewaySubnet', prefix: '10.50.6.0/27' }
  { name: 'appSubnet', prefix: '10.50.7.0/24' }
  { name: 'privateEPSubnet', prefix: '10.50.10.0/24' }
]
// Hub VNet resource group
resource networkRGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = if (deployHubVnet) {
  name: hubRgName
  location: hubLocation
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
module hubVnet '../../modules/hub/hubvnet.bicep' = if (deployHubVnet) {
  name: 'hubVnetModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    hubVnetName: hubVnetName
    location: hubLocation
    addressSpace: hubAddressSpace
    subnetNames: [for s in hubSubnets: s.name]
    subnetPrefixes: [for s in hubSubnets: s.prefix]
    routeTableName: routeTableName
    fwPrivateIP: firewallPrivateIP
    enableFirewallRouting: deployFirewall
    logAnalyticsWorkspaceId: deploylogsAnalytics ? logsAnalytics!.outputs.resourceId : ''
    enableDiagnostics: deploylogsAnalytics
  }
}

// =============== RBAC Role Assignments for VPNGW, WAF, KeyVault, and AppService====================
resource securityRGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deploySecurity) {
  name: securityRgName
  location: hubLocation
  tags: {
    Service: 'Security'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
module mgntIdentity '../../platform/identity/mgnt-Identity.bicep' = if (deploySecurity) {
  name: 'MgntIdentityModule'
  scope: resourceGroup(securityRGroup.name)
  params: {
    location: hubLocation
    wafGwName: 'xelawafgw'
    keyVaultName: 'xelavault'
    appServiceName: 'xelaweb'
    vpnGwName: 'xelavpngw'
    firewallName: 'xelaAzFirewall'
    acrName: 'xelaAcr'
    storageName: 'xelaStorage'
  }
}
/* ACR Registry Service */
resource acrRGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deployAcr) {
  name: hubAcrRgName
  location: hubLocation
  tags: {
    Service: 'Applications'
    CostCenter: 'Application'
    Environment: 'Production'
    Owner: 'ArnoldP'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── AVM REPLACEMENT: Container Registry ──
module acrService 'br/public:avm/res/container-registry/registry:0.9.3' = if (deployAcr) {
  name: 'acrModule'
  scope: resourceGroup(acrRGroup.name)
  params: {
    name: 'xelaAcr${toLower(take(uniqueString(hubAcrRgName), 4))}'
    location: hubLocation
    acrSku: 'Standard'
    tags: {
      Environment: 'Production'
      Component: 'ACR'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
    publicNetworkAccess: 'Enabled'
    acrAdminUserEnabled: false // best practice: use RBAC instead
    anonymousPullEnabled: false
    exportPolicyStatus: 'enabled'
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
    networkRuleBypassOptions: 'AzureServices'

    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        mgntIdentity!.outputs.acrIdentityId
      ]
    }

    // ── Role Assignments (built-in AVM support) ──
    roleAssignments: [
      {
        principalId: mgntIdentity!.outputs.acrPrincipalId
        roleDefinitionIdOrName: 'AcrPull'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: mgntIdentity!.outputs.acrPrincipalId
        roleDefinitionIdOrName: 'AcrPush'
        principalType: 'ServicePrincipal'
      }
    ]

    // ── Diagnostic Settings ──
    diagnosticSettings: [
      {
        workspaceResourceId: logsAnalytics!.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
        metricCategories: [
          { category: 'AllMetrics' }
        ]
      }
    ]
  }
}
// AppInsight and LogsAnalytics
resource logsRGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deploylogsAnalytics) {
  name: monitorRgName
  location: hubLocation
  tags: {
    Service: 'Logging'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── AVM REPLACEMENT: Log Analytics Workspace ──
module logsAnalytics 'br/public:avm/res/operational-insights/workspace:0.9.1' = if (deploylogsAnalytics) {
  name: 'logsModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    name: 'xelaLogs${take(uniqueString(monitorRgName), 4)}'
    location: hubLocation
    skuName: 'PerGB2018'
    dataRetention: 30
    dailyQuotaGb: -1 // unlimited; set >0 to cap ingestion (GB/day)
    publicNetworkAccessForIngestion: 'Enabled' // switch to 'Disabled' once AMPLS/Private Link is in place
    publicNetworkAccessForQuery: 'Enabled' // same as above
    tags: {
      Service: 'Logs'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }

    // Security hardening (v0.9.1 uses top-level flag)
    useResourcePermissions: true

    // ── VMInsights solution — creates InsightsMetrics, Perf, Event, Syslog tables ──
    gallerySolutions: [
      {
        name: 'VMInsights(xelaLogs${take(uniqueString(monitorRgName), 4)})'
        plan: {
          product: 'OMSGallery/VMInsights'
          publisher: 'Microsoft'
        }
      }
    ]

    // ── Diagnostic Settings — workspace sends its own logs to itself ──
    diagnosticSettings: [
      {
        useThisWorkspace: true
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
        metricCategories: [
          { category: 'AllMetrics' }
        ]
      }
    ]
  }
}

// ── AVM REPLACEMENT: Application Insights (workspace-based) ──
module appInsights 'br/public:avm/res/insights/component:0.7.1' = if (deploylogsAnalytics) {
  name: 'appInsightsModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    name: 'xelaAppsInsight${take(uniqueString(monitorRgName), 4)}'
    location: hubLocation
    workspaceResourceId: logsAnalytics!.outputs.resourceId
    applicationType: 'web'
    kind: 'web'
    ingestionMode: 'LogAnalytics'
    disableLocalAuth: true
    tags: {
      Service: 'Applications'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── Failure Anomalies smart detector alert rule ──
// Requires Microsoft.AlertsManagement provider to be registered on the subscription.
module failureAnomalies '../../modules/hub/failure-anomalies.bicep' = if (deploylogsAnalytics) {
  name: 'failureAnomaliesModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    appInsightsId: appInsights!.outputs.resourceId
    appInsightsName: appInsights!.outputs.name
  }
}

// ── AVM: Data Collection Rule for VM Insights (Map stream only) ──
// Name MUST start with "MSVMI-" for the Azure portal to recognise it as a VM Insights DCR
module vmDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.10.0' = if (deploylogsAnalytics && deployVM) {
  name: 'vmDataCollectionRuleModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    name: 'MSVMI-xelaLogs${take(uniqueString(monitorRgName), 4)}'
    location: hubLocation
    dataCollectionRuleProperties: {
      kind: 'All'
      description: 'Data Collection Rule for VM Insights Map (Dependency Agent)'
      dataSources: {
        extensions: [
          {
            name: 'DependencyAgentDataSource'
            extensionName: 'DependencyAgent'
            streams: ['Microsoft-ServiceMap']
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            name: 'logAnalyticsDestination'
            workspaceResourceId: logsAnalytics!.outputs.resourceId
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-ServiceMap']
          destinations: ['logAnalyticsDestination']
        }
      ]
    }
    tags: {
      Service: 'Monitoring'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// Optional perf-focused DCR for VM Insights detailed metrics
module vmPerfDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.10.0' = if (deploylogsAnalytics && deployVM && enableVmInsightsPerfDcr) {
  name: 'vmPerfDataCollectionRuleModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    name: 'MSVMI-Perf-xelaLogs${take(uniqueString(monitorRgName), 4)}'
    location: hubLocation
    dataCollectionRuleProperties: {
      kind: 'All'
      description: 'Optional DCR for VM Insights detailed performance metrics'
      dataSources: {
        performanceCounters: [
          {
            name: 'InsightsMetricsPerfCounters'
            streams: ['Microsoft-Perf']
            samplingFrequencyInSeconds: 60
            counterSpecifiers: [
              '\\Processor(_Total)\\% Processor Time'
              '\\Memory\\Available Bytes'
              '\\LogicalDisk(_Total)\\% Free Space'
              '\\LogicalDisk(_Total)\\Disk Transfers/sec'
              '\\Network Interface(*)\\Bytes Total/sec'
            ]
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            name: 'logAnalyticsDestination'
            workspaceResourceId: logsAnalytics!.outputs.resourceId
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-Perf']
          destinations: ['logAnalyticsDestination']
        }
      ]
    }
    tags: {
      Service: 'Monitoring'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// private DNS links for Log Analytics and Key Vault
module privateZones '../../modules/hub/privatednslinks.bicep' = if (deployPrivZones) {
  name: 'dnsLinksModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    hubVnetName: hubVnetName // Hub VNet name
    hubVnetResourceGroup: networkRGroup.name // Resource group for the hub VNet
  }
  dependsOn: [hubVnet] // ensure VNet exists before creating DNS zone VNet links
}
// Storage account deployment
resource storageRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployStorage) {
  name: hubStorageRgName
  location: hubLocation
  tags: {
    Service: 'Storage'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── AVM REPLACEMENT ──
module storage 'br/public:avm/res/storage/storage-account:0.14.3' = if (deployStorage) {
  name: 'hubStorageModule'
  scope: resourceGroup(storageRGroup.name)
  params: {
    name: 'hubstore${take(uniqueString(subscription().subscriptionId, hubStorageRgName), 6)}' // scoped to sub to avoid global name collision
    location: hubLocation
    kind: 'StorageV2'
    skuName: 'Standard_GRS'
    tags: {
      Environment: 'Production'
      CostCenter: 'Storage'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    managedIdentities: {
      userAssignedResourceIds: [
        mgntIdentity!.outputs.storageIdentityId
      ]
    }

    // ── Role Assignments (built-in AVM support) ──
    roleAssignments: [
      {
        principalId: mgntIdentity!.outputs.storagePrincipalId
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: mgntIdentity!.outputs.storagePrincipalId
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalType: 'ServicePrincipal'
      }
    ]

    // ── Diagnostic Settings (built-in AVM support) ──
    diagnosticSettings: [
      {
        workspaceResourceId: logsAnalytics!.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
        metricCategories: [
          { category: 'Transaction' }
        ]
      }
    ]

    // ── Private Endpoints (built-in AVM support) ──
    privateEndpoints: [
      {
        name: 'hubStorageBlobPE'
        subnetResourceId: hubVnet!.outputs.subnetIds[8] // privateEPSubnet (index 8)
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: deployPrivZones ? privateZones!.outputs.dnsZoneIds[0] : '' // privatelink.blob.core.windows.net
            }
          ]
        }
      }
    ]

    blobServices: {
      automaticSnapshotPolicyEnabled: true
      changeFeedEnabled: true
      containers: [
        { name: 'inputs' }
        { name: 'outputs' }
        { name: 'errors' }
      ]
      diagnosticSettings: [
        {
          workspaceResourceId: logsAnalytics!.outputs.resourceId
          logCategoriesAndGroups: [
            { categoryGroup: 'allLogs' }
          ]
          metricCategories: [
            { category: 'Transaction' }
          ]
        }
      ]
    }
    fileServices: {
      shares: [
        {
          name: 'notesdoc'
          accessTier: 'Hot'
        }
      ]
      diagnosticSettings: [
        {
          workspaceResourceId: logsAnalytics!.outputs.resourceId
          logCategoriesAndGroups: [
            { categoryGroup: 'allLogs' }
          ]
          metricCategories: [
            { category: 'Transaction' }
          ]
        }
      ]
    }
    queueServices: {
      diagnosticSettings: [
        {
          workspaceResourceId: logsAnalytics!.outputs.resourceId
          logCategoriesAndGroups: [
            { categoryGroup: 'allLogs' }
          ]
          metricCategories: [
            { category: 'Transaction' }
          ]
        }
      ]
    }
    tableServices: {
      diagnosticSettings: [
        {
          workspaceResourceId: logsAnalytics!.outputs.resourceId
          logCategoriesAndGroups: [
            { categoryGroup: 'allLogs' }
          ]
          metricCategories: [
            { category: 'Transaction' }
          ]
        }
      ]
    }
  }
}
// Hub VM example
resource vmRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployVM) {
  name: vmRgName
  location: hubLocation
  tags: {
    Service: 'Virtual Machines'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── AVM REPLACEMENT: Windows Hub VM ──
module hubVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deployVM) {
  name: 'hubVM'
  scope: resourceGroup(vmRGroup.name)
  params: {
    name: 'hubVM${toLower(take(uniqueString(vmRgName), 4))}'
    location: hubLocation
    osType: 'Windows'
    vmSize: 'Standard_D2s_v6'
    zone: 0 // non-zonal deployment — avoids per-zone SKU capacity restrictions
    encryptionAtHost: false // subscription lacks Microsoft.Compute/EncryptionAtHost feature
    adminUsername: 'vmuser'
    adminPassword: accessKey
    imageReference: {
      publisher: 'MicrosoftWindowsDesktop'
      offer: 'windows-11'
      sku: 'win11-24h2-pro'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: hubVnet!.outputs.subnetIds[0] // vmSubnet
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    // ── Boot Diagnostics ──
    bootDiagnostics: true
    // ── Azure Monitor Agent (AMA) extension + DCR association ──
    extensionMonitoringAgentConfig: {
      enabled: true
      dataCollectionRuleAssociations: concat(
        [
          {
            name: 'hubVM-vmInsights'
            dataCollectionRuleResourceId: vmDataCollectionRule!.outputs.resourceId
          }
        ],
        enableVmInsightsPerfDcr
          ? [
              {
                name: 'hubVM-vmInsightsPerf'
                dataCollectionRuleResourceId: vmPerfDataCollectionRule!.outputs.resourceId
              }
            ]
          : []
      )
    }
    // ── Dependency Agent for VM Insights Map feature ──
    extensionDependencyAgentConfig: {
      enabled: true
      enableProcessesAndDependencies: true
    }
    tags: {
      Service: 'Compute'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── AVM REPLACEMENT: Linux VM ──
module linuxVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deployVM) {
  name: 'LinuxVMModule'
  scope: resourceGroup(vmRGroup.name)
  params: {
    name: 'LinuxVM${take(uniqueString(vmRgName), 4)}'
    location: hubLocation
    osType: 'Linux'
    vmSize: 'Standard_D2s_v6' // same family as Windows VM (confirmed available)
    zone: 0 // non-zonal deployment — avoids per-zone SKU capacity restrictions
    encryptionAtHost: false // subscription lacks Microsoft.Compute/EncryptionAtHost feature
    adminUsername: 'vmuser'
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: sshPublicKey
        path: '/home/vmuser/.ssh/authorized_keys'
      }
    ]
    imageReference: {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-focal'
      sku: '20_04-lts-gen2'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      diskSizeGB: 30
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: hubVnet!.outputs.subnetIds[0] // vmSubnet
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    bootDiagnostics: true
    bootDiagnosticStorageAccountUri: 'https://${storage!.outputs.name}.blob.${environment().suffixes.storage}/'
    // ── Azure Monitor Agent (AMA) extension + DCR association ──
    extensionMonitoringAgentConfig: {
      enabled: true
      dataCollectionRuleAssociations: concat(
        [
          {
            name: 'linuxVM-vmInsights'
            dataCollectionRuleResourceId: vmDataCollectionRule!.outputs.resourceId
          }
        ],
        enableVmInsightsPerfDcr
          ? [
              {
                name: 'linuxVM-vmInsightsPerf'
                dataCollectionRuleResourceId: vmPerfDataCollectionRule!.outputs.resourceId
              }
            ]
          : []
      )
    }
    // ── Dependency Agent for VM Insights Map feature (Ubuntu 20.04 supported) ──
    extensionDependencyAgentConfig: {
      enabled: true
      enableProcessesAndDependencies: true
    }
    tags: {
      Service: 'VM'
      CostCenter: 'Linux'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── AVM REPLACEMENT: Bastion Host ──
module bastionHost 'br/public:avm/res/network/bastion-host:0.8.2' = if (deployBastion) {
  name: 'bastionModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'CPSBastion'
    location: hubLocation
    virtualNetworkResourceId: hubVnet!.outputs.vnetId
    skuName: 'Standard'
    tags: {
      Service: 'Network'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'cps-security'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }

    // ── Diagnostic Settings (allLogs + AllMetrics) ──
    diagnosticSettings: [
      {
        workspaceResourceId: logsAnalytics!.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
      }
    ]

    // ── Public IP with its own diagnostics ──
    publicIPAddressObject: {
      name: 'CPSBastionPIP'
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
      diagnosticSettings: [
        {
          workspaceResourceId: logsAnalytics!.outputs.resourceId
          logCategoriesAndGroups: [
            { categoryGroup: 'allLogs' }
          ]
          metricCategories: [
            { category: 'AllMetrics' }
          ]
        }
      ]
    }
  }
}

// ── AVM REPLACEMENT: DNS Private Resolver ──
module dnsResolver 'br/public:avm/res/network/dns-resolver:0.5.6' = if (dnsresolver) {
  name: 'dnsResolverModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'DnsResolver'
    location: hubLocation
    virtualNetworkResourceId: hubVnet!.outputs.vnetId
    inboundEndpoints: [
      {
        name: 'inbound'
        subnetResourceId: hubVnet!.outputs.subnetIds[1] // dns-inbound
      }
    ]
    outboundEndpoints: [
      {
        name: 'outbound'
        subnetResourceId: hubVnet!.outputs.subnetIds[2] // dns-outbound
      }
    ]
    tags: {
      Service: 'DNS'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── AVM REPLACEMENT: DNS Forwarding Ruleset ──
module dnsForwardingRuleset 'br/public:avm/res/network/dns-forwarding-ruleset:0.5.3' = if (dnsresolver) {
  name: 'dnsForwardingRulesetModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'DnsResolver-ruleset'
    location: hubLocation
    dnsForwardingRulesetOutboundEndpointResourceIds: [
      '${dnsResolver!.outputs.resourceId}/outboundEndpoints/outbound'
    ]
    forwardingRules: [
      {
        name: 'rule-onprem-xelatech-net'
        domainName: 'onprem.xelatech.net.'
        targetDnsServers: [
          { ipAddress: '172.16.110.5', port: 53 }
        ]
        forwardingRuleState: 'Enabled'
      }
    ]
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: hubVnet!.outputs.vnetId
      }
    ]
    tags: {
      Service: 'DNS'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}
// firewall module reference
module firewall '../../modules/hub/firewall-vnet.bicep' = if (deployFirewall) {
  name: 'firewallModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    location: hubLocation
    hubVnetResourceGroup: networkRGroup.name // Resource group for the hub VNet
    firewallName: 'xelaAzFirewall'
    firewallPolicyName: 'xelaAzFirewallPolicy01'
    natPublicIP: natPublicIP
    hubVnetName: hubVnetName // Hub VNet name
    linuxVMPrivIP: '10.50.0.5' // AVM VM module doesn't output private IPs; update post-deploy
    hubVMPrivIP: '10.50.0.4' // AVM VM module doesn't output private IPs; update post-deploy
    dnsResolverName: 'DnsResolver' // pass resolver name
    logAnalyticsWorkspaceId: logsAnalytics!.outputs.resourceId
    firewallPrincipalId: mgntIdentity!.outputs.firewallPrincipalId // pass the principalId of the Firewall Managed Identity
    firewallIdentityId: mgntIdentity!.outputs.firewallIdentityId // pass the resource ID of the Firewall Managed Identity
    routeTableName: routeTableName
  }
}
// Key Vault module reference [AVM]
module keyVault 'br/public:avm/res/key-vault/vault:0.9.0' = if (deploySecurity) {
  name: 'keyVaultModule'
  scope: resourceGroup(securityRGroup.name)
  params: {
    name: 'xelavault${take(uniqueString(securityRGroup.id, hubLocation), 4)}' // seeded with location to avoid name collision with soft-deleted westus vault
    location: hubLocation
    enableRbacAuthorization: true
    enableVaultForDeployment: true
    enableVaultForTemplateDeployment: true
    enableVaultForDiskEncryption: true
    enablePurgeProtection: false // disabled for dev/test — enable for production
    softDeleteRetentionInDays: 7
    sku: 'standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        { value: natPublicIP }
      ]
    }
    // Role assignments: KV identity (4 roles) + WAF GW + App Svc + User admin
    roleAssignments: concat(
      [
        {
          principalId: mgntIdentity!.outputs.kvPrincipalId
          roleDefinitionIdOrName: 'Key Vault Secrets User'
          principalType: 'ServicePrincipal'
        }
        {
          principalId: mgntIdentity!.outputs.kvPrincipalId
          roleDefinitionIdOrName: 'Key Vault Secrets Officer'
          principalType: 'ServicePrincipal'
        }
        {
          principalId: mgntIdentity!.outputs.kvPrincipalId
          roleDefinitionIdOrName: 'Key Vault Administrator'
          principalType: 'ServicePrincipal'
        }
        {
          principalId: mgntIdentity!.outputs.kvPrincipalId
          roleDefinitionIdOrName: 'Reader'
          principalType: 'ServicePrincipal'
        }
        {
          principalId: mgntIdentity!.outputs.wafPrincipalId
          roleDefinitionIdOrName: 'Key Vault Secrets User'
          principalType: 'ServicePrincipal'
        }
        {
          principalId: mgntIdentity!.outputs.appsSvcPrincipalId
          roleDefinitionIdOrName: 'Key Vault Secrets User'
          principalType: 'ServicePrincipal'
        }
      ],
      empty(keyVaultAdminObjectId)
        ? []
        : [
            {
              principalId: keyVaultAdminObjectId
              roleDefinitionIdOrName: 'Key Vault Administrator'
              principalType: 'User'
            }
          ]
    )
    // Diagnostics: allLogs + AllMetrics (upgraded from AuditEvent-only)
    diagnosticSettings: [
      {
        name: 'diag-keyvault' // fresh vault in westus2 — no naming conflict
        workspaceResourceId: logsAnalytics!.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
        metricCategories: [
          { category: 'AllMetrics' }
        ]
      }
    ]
    // Secrets: SQL admin password
    secrets: [
      {
        name: 'sqlAdminPassword'
        value: accessKey
        contentType: 'SQL Password'
      }
    ]
    tags: {
      Service: 'Application'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── AVM REPLACEMENT: Virtual Network Gateway (VPN) ──
module vpngw 'br/public:avm/res/network/virtual-network-gateway:0.9.0' = if (deployVpnGw) {
  name: 'vpngwModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'xelavpng${take(uniqueString(hubRgName), 4)}'
    location: hubLocation
    gatewayType: 'Vpn'
    skuName: 'VpnGw1AZ' // zone-redundant SKU for westus2
    virtualNetworkResourceId: hubVnet!.outputs.vnetId
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp'
    }
    vpnType: 'RouteBased'
    managedIdentity: {
      userAssignedResourceIds: [
        mgntIdentity!.outputs.vpngwIdentityId
      ]
    }
    // Role assignments: Network Contributor, Reader, Monitoring Reader
    roleAssignments: [
      {
        principalId: mgntIdentity!.outputs.vpngwPrincipalId
        roleDefinitionIdOrName: subscriptionResourceId(
          'Microsoft.Authorization/roleDefinitions',
          '4d97b98b-1d4f-4787-a291-c67834d212e7'
        )
        principalType: 'ServicePrincipal'
      }
      {
        principalId: mgntIdentity!.outputs.vpngwPrincipalId
        roleDefinitionIdOrName: subscriptionResourceId(
          'Microsoft.Authorization/roleDefinitions',
          'acdd72a7-3385-48ef-bd42-f606fba81ae7'
        )
        principalType: 'ServicePrincipal'
      }
      {
        principalId: mgntIdentity!.outputs.vpngwPrincipalId
        roleDefinitionIdOrName: subscriptionResourceId(
          'Microsoft.Authorization/roleDefinitions',
          '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
        )
        principalType: 'ServicePrincipal'
      }
    ]
    // Diagnostics: allLogs + AllMetrics
    diagnosticSettings: [
      {
        name: 'diag-vpngw'
        workspaceResourceId: logsAnalytics!.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
        metricCategories: [
          { category: 'AllMetrics' }
        ]
      }
    ]
    tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  }
}

// ── AVM REPLACEMENT: Local Network Gateway ──
module localGw 'br/public:avm/res/network/local-network-gateway:0.4.0' = if (deployVpnGw) {
  name: 'localGwModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'xelalocalgw'
    location: hubLocation
    localGatewayPublicIpAddress: natPublicIP
    localNetworkAddressSpace: {
      addressPrefixes: [
        '10.6.1.0/24'
        '172.16.110.0/24'
        '172.17.111.0/24'
        '10.2.1.0/24'
        '192.168.0.0/24'
      ]
    }
    tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  }
}

// ── AVM REPLACEMENT: VPN Connection ──
module vnpConnection 'br/public:avm/res/network/connection:0.1.6' = if (deployVpnGw) {
  name: 'vpnConnectionModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    name: 'XelaVPNConnection'
    location: hubLocation
    virtualNetworkGateway1: {
      id: vpngw!.outputs.resourceId
    }
    localNetworkGateway2ResourceId: localGw!.outputs.resourceId
    connectionType: 'IPsec'
    vpnSharedKey: accessKey
    connectionProtocol: 'IKEv2'
    enableBgp: false
    dpdTimeoutSeconds: 45
    connectionMode: 'Default'
    usePolicyBasedTrafficSelectors: false
    customIPSecPolicy: {
      saLifeTimeSeconds: 27000
      saDataSizeKilobytes: 0
      ipsecEncryption: 'GCMAES256'
      ipsecIntegrity: 'GCMAES256'
      ikeEncryption: 'AES256'
      ikeIntegrity: 'SHA256'
      dhGroup: 'DHGroup14'
      pfsGroup: 'None'
    }
    tags: { SecurityControl: 'Ignore', CostControl: 'Ignore' }
  }
}

// Additional diagnostics to close monitoring gaps on deployed resources.
module monitorDiag '../../modules/hub/monitor-diag.bicep' = if (deploylogsAnalytics) {
  name: 'monitorDiagModule'
  scope: resourceGroup(logsRGroup.name)
  params: {
    workspaceId: logsAnalytics!.outputs.resourceId
    appInsightsName: appInsightsName
    vmInsightsDcrName: vmInsightsDcrName
    vmInsightsPerfDcrName: vmInsightsPerfDcrName
    enableVmInsightsPerfDcr: enableVmInsightsPerfDcr
    // Lock the SRE portal identity so its principalId stays stable across deployments
    sreAgentIdentityName: 'sre-demo-${uniqueString(monitorRgName)}'
  }
  dependsOn: [appInsights, vmDataCollectionRule]
}

module networkDiag '../../modules/hub/network-diag.bicep' = if (deployFirewall) {
  name: 'networkDiagModule'
  scope: resourceGroup(networkRGroup.name)
  params: {
    workspaceId: logsAnalytics!.outputs.resourceId
    deployFirewall: deployFirewall
    firewallPublicIpName: firewallPublicIpName
  }
  dependsOn: [firewall]
}

module vmDiag '../../modules/hub/vm-diag.bicep' = if (deployVM) {
  name: 'vmDiagModule'
  scope: resourceGroup(vmRGroup.name)
  params: {
    workspaceId: logsAnalytics!.outputs.resourceId
    deployVM: deployVM
    hubVmName: hubVmName
    linuxVmName: linuxVmName
  }
  dependsOn: [hubVM, linuxVM]
}


