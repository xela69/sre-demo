// param to deploy components
param deploySpokeVnet bool = true
param deployVM bool = true
param deployStorage bool = true
param deploySQLVM bool = true

param accessKey string
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
    vmSize: 'Standard_B2ms'
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
    tags: {
      Service: 'Compute'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
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
    name: 'apps${take(uniqueString(spokeStorageRgName), 4)}'
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
  }
}

module sqlVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = if (deploySQLVM) {
  name: 'AppsSQLVMModule'
  scope: resourceGroup(spokeSubId, sqlVmRGroup.name)
  params: {
    name: 'AppsSQLVM'
    location: spokeLocation
    osType: 'Windows'
    vmSize: 'Standard_B2ms'
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
    tags: {
      Service: 'SQL Server'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'Xelatech'
      AzMigrateSource: 'true'
    }
  }
  dependsOn: [spokeVnet]
}
