// param to deploy components
param deploySpokeVnet bool = true
param deployVM bool = true
param deployStorage bool = true
param deploySQLVM bool = true
param deployContainerApp bool = true

param accessKey string
param sshPublicKey string
param natPublicIP string = ''
param deployLinuxVM bool = true
param enableVmInsightsPerfDcr bool = true
targetScope = 'subscription' // Required for resource group deployments

param spokeRgName string = 'AppsRG'
param spokeVmRgName string = 'AppsRG-VM'
param spokeVnetName string = 'AppsRG-VNet'
param spokeStorageRgName string = 'AppsRG-Storage'
param spokeAddressSpace string = '10.52.0.0/20'
param spokeLocation string = 'centralus'
param spokeSubId string = '42021d44-97d2-47a1-8245-a77149dda4c3' //apps subs

param spokeSubnets array = [
  { name: 'vmSubnet', prefix: '10.52.0.0/24' }
  { name: 'appSubnet', prefix: '10.52.1.0/24' }
  { name: 'privateEPSubnet', prefix: '10.52.10.0/24' }
]
// Reference the hub info for peering (if needed)
param hubVnetName string = 'hubRG-VNet'
param hubVnetResourceGroup string = 'hubRG'
param hubVnetSubscriptionId string = 'ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9' // hub subscription ID
// Cross-subscription subnet resource ID for NIC configuration
var vmSubnetResourceId = '/subscriptions/${spokeSubId}/resourceGroups/${spokeRgName}/providers/Microsoft.Network/virtualNetworks/${spokeVnetName}/subnets/vmSubnet'

// Spoke VNet resource group
resource spokeRGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = if (deploySpokeVnet) {
  name: spokeRgName
  location: spokeLocation
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
module spokeVnet '../../modules/spokes/spokevnets.bicep' = if (deploySpokeVnet) {
  name: 'AppsVnetModule'
  scope: resourceGroup(spokeSubId, spokeRGroup.name)
  params: {
    vnetName: spokeVnetName
    location: spokeLocation
    addressSpace: spokeAddressSpace
    subnetNames: [for s in spokeSubnets: s.name]
    subnetPrefixes: [for s in spokeSubnets: s.prefix]
    fwPrivateIP: '10.50.4.4'
    hubVnetName: hubVnetName
    hubVnetResourceGroup: hubVnetResourceGroup
    hubVnetSubscriptionId: hubVnetSubscriptionId
    logAnalyticsWorkspaceId: hubLaw.id
    routeTableName: 'appsRouteTable'
  }
}

// Apps VM example
resource vmRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployVM) {
  name: spokeVmRgName
  location: spokeLocation
  tags: {
    Service: 'Virtual Machines'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
// ── AVM: Apps Spoke VM (Windows 11 Pro) ──
module spokeVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deployVM) {
  name: 'AppsVMModule'
  scope: resourceGroup(spokeSubId, vmRGroup.name)
  params: {
    name: 'AppsVM'
    location: spokeLocation
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    encryptionAtHost: false
    adminUsername: 'vmuser'
    adminPassword: accessKey
    imageReference: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      diskSizeGB: 128
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vmSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    // ── Boot Diagnostics ──
    bootDiagnostics: true
    // ── Azure Monitor Agent (AMA) extension + DCR association ──
    extensionMonitoringAgentConfig: {
      enabled: true
      dataCollectionRuleAssociations: concat(
        [
          {
            name: 'appsVM-vmInsights'
            dataCollectionRuleResourceId: hubVmInsightsDcr.id
          }
        ],
        enableVmInsightsPerfDcr
          ? [
              {
                name: 'appsVM-vmInsightsPerf'
                dataCollectionRuleResourceId: hubVmInsightsPerfDcr.id
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
  dependsOn: [spokeVnet]
}

// ── AVM: Apps Spoke Linux VM (Ubuntu 20.04 LTS) ──
module linuxVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deployVM && deployLinuxVM) {
  name: 'AppsLinuxVMModule'
  scope: resourceGroup(spokeSubId, vmRGroup.name)
  params: {
    name: 'AppsLinuxVM${take(uniqueString(spokeVmRgName), 4)}'
    location: spokeLocation
    osType: 'Linux'
    vmSize: 'Standard_D2s_v3'
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
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vmSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    bootDiagnostics: true
    bootDiagnosticStorageAccountUri: 'https://${storage!.outputs.name}.blob.${environment().suffixes.storage}/'
    // ── Azure Monitor Agent (AMA) extension + DCR association ──
    extensionMonitoringAgentConfig: {
      enabled: true
      dataCollectionRuleAssociations: concat(
        [
          {
            name: 'appsLinuxVM-vmInsights'
            dataCollectionRuleResourceId: hubVmInsightsDcr.id
          }
        ],
        enableVmInsightsPerfDcr
          ? [
              {
                name: 'appsLinuxVM-vmInsightsPerf'
                dataCollectionRuleResourceId: hubVmInsightsPerfDcr.id
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
      Environment: 'Production'
      Owner: 'Xelatech'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
  dependsOn: [spokeVnet]
}
// Storage account deployment
resource storageRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployStorage) {
  name: spokeStorageRgName
  location: spokeLocation
  tags: {
    Service: 'Storage'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}
// Reference existing managed identity for storage role assignments (hub subscription)
resource storageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'xelaStorage-Identity'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Security')
}
// ── AVM: Spoke Storage Account ──
module storage 'br/public:avm/res/storage/storage-account:0.15.0' = if (deployStorage) {
  name: 'AppsStorage'
  scope: resourceGroup(spokeSubId, storageRGroup.name)
  params: {
    name: 'apps${take(uniqueString(spokeSubId, spokeStorageRgName), 8)}'
    location: spokeLocation
    skuName: 'Standard_GRS'
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
    }
    // ── Diagnostic Settings ──
    diagnosticSettings: [
      {
        workspaceResourceId: hubLaw.id
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
        metricCategories: [{ category: 'Transaction' }]
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
          workspaceResourceId: hubLaw.id
          logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
          metricCategories: [{ category: 'Transaction' }]
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
          workspaceResourceId: hubLaw.id
          logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
          metricCategories: [{ category: 'Transaction' }]
        }
      ]
    }
    queueServices: {
      diagnosticSettings: [
        {
          workspaceResourceId: hubLaw.id
          logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
          metricCategories: [{ category: 'Transaction' }]
        }
      ]
    }
    tableServices: {
      diagnosticSettings: [
        {
          workspaceResourceId: hubLaw.id
          logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
          metricCategories: [{ category: 'Transaction' }]
        }
      ]
    }
    roleAssignments: [
      {
        principalId: storageIdentity.properties.principalId
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: storageIdentity.properties.principalId
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalType: 'ServicePrincipal'
      }
    ]
    tags: {
      Environment: 'Production'
      CostCenter: 'Storage'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
}

// ── SQL Server 2022 Developer VM (Azure Migrate source) ───────────────────────
param spokeSqlVmRgName string = 'AppsRG-SQL'

resource sqlVmRGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = if (deploySQLVM) {
  name: spokeSqlVmRgName
  location: spokeLocation
  tags: {
    Service: 'SQL Server'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

module sqlVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deploySQLVM) {
  name: 'AppsSQLVMModule'
  scope: resourceGroup(spokeSubId, sqlVmRGroup.name)
  params: {
    name: 'AppsSQLVM'
    location: spokeLocation
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    encryptionAtHost: false
    adminUsername: 'vmuser'
    adminPassword: accessKey
    imageReference: {
      publisher: 'MicrosoftSQLServer'
      offer: 'sql2022-ws2022'
      sku: 'sqldev-gen2'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      diskSizeGB: 128
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    dataDisks: [
      {
        lun: 0
        diskSizeGB: 64
        caching: 'ReadOnly'
        createOption: 'Empty'
        deleteOption: 'Delete'
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    ]
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vmSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    // ── Boot Diagnostics ──
    bootDiagnostics: true
    // ── Azure Monitor Agent (AMA) extension + DCR association ──
    extensionMonitoringAgentConfig: {
      enabled: true
      dataCollectionRuleAssociations: concat(
        [
          {
            name: 'sqlVM-vmInsights'
            dataCollectionRuleResourceId: hubVmInsightsDcr.id
          }
        ],
        enableVmInsightsPerfDcr
          ? [
              {
                name: 'sqlVM-vmInsightsPerf'
                dataCollectionRuleResourceId: hubVmInsightsPerfDcr.id
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
      Service: 'SQL Server'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      AzMigrateSource: 'true'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
  dependsOn: [spokeVnet]
}

// ── Hub resource lookups (cross-subscription) for container app wiring ──
// ACR registry in hubRG-Acr; ACR identity in hubRG-Security; LAW in hubRG-Monitor
resource hubAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: 'xelaAcr${toLower(take(uniqueString('hubRG-Acr'), 4))}'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Acr')
}
resource hubAcrIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'xelaAcr'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Security')
}
resource hubLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'xelaLogs${take(uniqueString('hubRG-Monitor'), 4)}'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Monitor')
}
// Reference hub VM Insights DCRs for AMA associations (cross-subscription)
resource hubVmInsightsDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: 'MSVMI-xelaLogs${take(uniqueString('hubRG-Monitor'), 4)}'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Monitor')
}
resource hubVmInsightsPerfDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: 'MSVMI-Perf-xelaLogs${take(uniqueString('hubRG-Monitor'), 4)}'
  scope: resourceGroup(hubVnetSubscriptionId, 'hubRG-Monitor')
}
// ── VM Diagnostic Settings (modules) ─────────────────────────────────────────
// AVM virtual-machine 0.9.0 has no diagnosticSettings param; use a dedicated
// module scoped to each VM's resource group.  Captures AllMetrics → hub LAW.
// Guest logs/perf are covered by AMA + DCR configured at the module level above.
module appsVMDiag '../../modules/apps/vmDiag.bicep' = if (deployVM) {
  name: 'AppsVMDiag'
  scope: resourceGroup(spokeSubId, vmRGroup.name)
  params: {
    vmName: 'AppsVM'
    logAnalyticsWorkspaceId: hubLaw.id
  }
  dependsOn: [spokeVM]
}

var linuxVMName = 'AppsLinuxVM${take(uniqueString(spokeVmRgName), 4)}'
module linuxVMDiag '../../modules/apps/vmDiag.bicep' = if (deployVM && deployLinuxVM) {
  name: 'LinuxVMDiag'
  scope: resourceGroup(spokeSubId, vmRGroup.name)
  params: {
    vmName: linuxVMName
    logAnalyticsWorkspaceId: hubLaw.id
  }
  dependsOn: [linuxVM]
}

module sqlVMDiag '../../modules/apps/vmDiag.bicep' = if (deploySQLVM) {
  name: 'SQLVMDiag'
  scope: resourceGroup(spokeSubId, sqlVmRGroup.name)
  params: {
    vmName: 'AppsSQLVM'
    logAnalyticsWorkspaceId: hubLaw.id
  }
  dependsOn: [sqlVM]
}
// ── Container App deployment ──
param spokeContainerRgName string = 'AppsRG-ContainerApp'

// ── Grubify: set deployGrubify=true once images are pushed to ACR ──
param deployGrubify bool = false
@description('Grubify API image tag in hub ACR (e.g. grubify-api:latest). Leave default until image is built.')
param grubifyApiImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
@description('Grubify frontend image tag in hub ACR (e.g. grubify-frontend:latest). Leave default until image is built.')
param grubifyFrontendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
@description('App Insights connection string from hub (injected at deploy time).')
@secure()
param appInsightsConnectionString string = ''
@description('ACR login server (e.g. xelaacr1234.azurecr.io). Pass explicitly to avoid ARM reference() in image strings failing preflight validation.')
param acrLoginServer string = ''

// Resolved at template level: use explicit param when provided, otherwise fall back to hubAcr reference.
var resolvedAcrServer = empty(acrLoginServer) ? hubAcr.properties.loginServer : acrLoginServer

resource containerRGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = if (deployContainerApp) {
  name: spokeContainerRgName
  location: spokeLocation
  tags: {
    Service: 'ContainerApp'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── Grubify API — reuses the existing containerApp module; overrides image when deployGrubify=true ──
module containerApp '../../modules/apps/containerApp.bicep' = if (deployContainerApp) {
  name: 'AppsContainerApp'
  scope: resourceGroup(spokeSubId, containerRGroup.name)
  params: {
    location: spokeLocation
    containerAppName: deployGrubify ? 'grubify-api' : 'xela${take(uniqueString(spokeContainerRgName), 4)}'
    containerAppEnvName: deployGrubify ? 'grubify-env' : 'xelaenv${take(uniqueString(spokeContainerRgName), 4)}'
    acrLoginServer: resolvedAcrServer
    managedIdentityId: hubAcrIdentity.id
    logAnalyticsWorkspaceId: hubLaw.id
    natPublicIP: natPublicIP
    containerImage: deployGrubify
      ? '${resolvedAcrServer}/${grubifyApiImage}'
      : 'mcr.microsoft.com/k8se/quickstart:latest'
  }
}

// ── Grubify Frontend — second container app reusing the same environment ──
// Look up the env resource ID by name since containerApp module exposes env name not env resource ID
resource grubifyEnv 'Microsoft.App/managedEnvironments@2024-03-01' existing = if (deployContainerApp && deployGrubify) {
  name: containerApp!.outputs.containerAppEnvName
  scope: resourceGroup(spokeSubId, containerRGroup.name)
}

module grubifyFrontend '../../modules/apps/grubifyFrontend.bicep' = if (deployContainerApp && deployGrubify) {
  name: 'GrubifyFrontend'
  scope: resourceGroup(spokeSubId, containerRGroup.name)
  params: {
    location: spokeLocation
    containerAppEnvResourceId: grubifyEnv.id
    acrLoginServer: resolvedAcrServer
    managedIdentityId: hubAcrIdentity.id
    frontendImage: '${resolvedAcrServer}/${grubifyFrontendImage}'
    apiUrl: containerApp!.outputs.containerAppFqdn
    appInsightsConnectionString: appInsightsConnectionString
    logAnalyticsWorkspaceId: hubLaw.id
  }
}
