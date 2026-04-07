// param to deploy components
param deploySpokeVnet bool = true
param deployWinVM bool = true // on-prem Windows VM (WS2012R2 + SQL2014 community gallery image)
param deploySqlVM bool = true // on-prem SQL VM (WS2022 + SQL2019 marketplace image)
param deployStorage bool = true
param deployDSC bool = true // DSC extensions require outbound internet from VMs; set true after firewall rules confirmed

@secure()
param labPassword string // lab VM admin password (username: demouser)
param onpremVMSize string = 'Standard_D4as_v4'
param repositoryBranch string = 'main'
param repositoryOwner string = 'microsoft'
targetScope = 'subscription' // Required for resource group deployments

param dataRgName string = 'DataRG'
param dataVmRgName string = 'DataRG-VM'
param dataVnetName string = 'DataRG-VNet'
param dataStorageRgName string = 'DataRG-Storage'
param dataAddressSpace string = '10.51.0.0/20'
param spokeLocation string = 'westus3' // community gallery WS2012R2_SQL2014_Base validated region
param dataSubId string = '8de6c6e8-53af-4ded-a480-fd20c6093e78' //data subs

param dataSubnets array = [
  { name: 'vmSubnet', prefix: '10.51.0.0/24' }
  { name: 'appsSubnet', prefix: '10.51.1.0/24' }
  { name: 'privateEPSubnet', prefix: '10.51.10.0/24' }
]

// Reference the hub info for peering (if needed)
param hubVnetName string = 'hubRG-VNet'
param hubVnetResourceGroup string = 'hubRG'
param hubVnetSubscriptionId string = 'ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9' // hub subscription ID

// GitHub Tailspin lab script URLs — DSC extensions pull config/scripts from Microsoft's repo
var repositoryName = 'techworkshop-L300-secure-workload-migration-to-azure-windows-server---sql-server'
var gitHubRepoScriptPath = 'Hands-on%20lab/resources/deployment/onprem'
var gitHubRepoUrl = 'https://github.com/${repositoryOwner}/${repositoryName}/raw/refs/heads/${repositoryBranch}/${gitHubRepoScriptPath}'
var windowsVmScriptArchiveUrl = '${gitHubRepoUrl}/windows-vm-config.zip'
var sqlVmScriptArchiveUrl = '${gitHubRepoUrl}/sql-vm-config.zip'
var databaseBackupFileUrl = '${gitHubRepoUrl}/database.bak'
// Cross-subscription subnet resource ID for NIC configuration
var vmSubnetResourceId = '/subscriptions/${dataSubId}/resourceGroups/${dataRgName}/providers/Microsoft.Network/virtualNetworks/${dataVnetName}/subnets/vmSubnet'

// Data VNet resource group
resource dataRg 'Microsoft.Resources/resourceGroups@2024-11-01' = if (deploySpokeVnet) {
  name: dataRgName
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
  name: 'DataVnetModule'
  scope: resourceGroup(dataSubId, dataRg.name)
  params: {
    vnetName: dataVnetName
    location: spokeLocation
    addressSpace: dataAddressSpace
    subnetNames: [for s in dataSubnets: s.name]
    subnetPrefixes: [for s in dataSubnets: s.prefix]
    fwPrivateIP: '10.50.4.4' // Hub firewall private IP
    hubVnetName: hubVnetName
    hubVnetResourceGroup: hubVnetResourceGroup
    hubVnetSubscriptionId: hubVnetSubscriptionId
    routeTableName: 'dataRouteTable'
  }
}
// Lab VMs resource group (shared for both on-prem simulation VMs)
resource vmRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployWinVM || deploySqlVM) {
  name: dataVmRgName
  location: spokeLocation
  tags: {
    Service: 'Virtual Machines'
    CostCenter: 'Infrastructure'
    Environment: 'Lab'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
}

// ── AVM: On-Premises Windows VM (WS2012R2 + SQL2014 Community Gallery image) ──
// Region must have Tahubu gallery image replicated: northcentralus | westus3 | swedencentral
module onpremWinVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deployWinVM) {
  name: 'OnpremWinVMModule'
  scope: resourceGroup(dataSubId, vmRGroup.name)
  params: {
    name: 'onprem-win-vm'
    location: spokeLocation
    osType: 'Windows'
    vmSize: onpremVMSize
    zone: 0
    encryptionAtHost: false
    adminUsername: 'demouser'
    adminPassword: labPassword
    imageReference: {
      communityGalleryImageId: '/CommunityGalleries/Tahubu-607896e6-c4b5-4245-bfb6-c6b57aa9aa62/Images/WS2012R2_SQL2014_Base/Versions/latest'
    }
    osDisk: {
      createOption: 'FromImage'
      diskSizeGB: 128
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vmSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    // DSC: configures Azure Arc connectivity on the Windows VM
    extensionDSCConfig: deployDSC
      ? {
          enabled: true
          settings: {
            wmfVersion: 'latest'
            configuration: {
              url: windowsVmScriptArchiveUrl
              script: 'windows-vm-config.ps1'
              function: 'ArcConnect'
            }
          }
        }
      : null
    tags: {
      Service: 'Compute'
      CostCenter: 'Infrastructure'
      Environment: 'Lab'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
  dependsOn: [spokeVnet]
}

// ── AVM: On-Premises SQL VM (WS2022 + SQL2019 Standard, Marketplace) ──
// DSC: configures SQL Server and restores database.bak from GitHub
module onpremSqlVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deploySqlVM) {
  name: 'OnpremSqlVMModule'
  scope: resourceGroup(dataSubId, vmRGroup.name)
  params: {
    name: 'onprem-sql-vm'
    location: spokeLocation
    osType: 'Windows'
    vmSize: onpremVMSize
    zone: 0
    encryptionAtHost: false
    adminUsername: 'demouser'
    adminPassword: labPassword
    imageReference: {
      publisher: 'MicrosoftSQLServer'
      offer: 'SQL2019-WS2022'
      sku: 'Standard'
      version: 'latest'
    }
    osDisk: {
      createOption: 'FromImage'
      diskSizeGB: 128
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: vmSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: { systemAssigned: true }
    // DSC: configures SQL Server and restores database backup
    extensionDSCConfig: deployDSC
      ? {
          enabled: true
          settings: {
            configuration: {
              url: sqlVmScriptArchiveUrl
              script: 'sql-vm-config.ps1'
              function: 'Main'
            }
            configurationArguments: {
              DbBackupFileUrl: databaseBackupFileUrl
              DatabasePassword: labPassword
            }
          }
        }
      : null
    tags: {
      Service: 'Compute'
      CostCenter: 'Infrastructure'
      Environment: 'Lab'
      SecurityControl: 'Ignore'
      CostControl: 'Ignore'
    }
  }
  dependsOn: [spokeVnet]
}
// Storage account deployment
resource storageRGroup 'microsoft.resources/resourceGroups@2024-03-01' = if (deployStorage) {
  name: dataStorageRgName
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
  name: 'DataStorageModule'
  scope: resourceGroup(dataSubId, storageRGroup.name)
  params: {
    name: 'datastore${take(uniqueString(dataStorageRgName), 4)}'
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
    blobServices: {
      automaticSnapshotPolicyEnabled: true
      changeFeedEnabled: true
      containers: [
        { name: 'inputs' }
        { name: 'outputs' }
        { name: 'errors' }
      ]
    }
    fileServices: {
      shares: [
        {
          name: 'notesdoc'
          accessTier: 'Hot'
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
