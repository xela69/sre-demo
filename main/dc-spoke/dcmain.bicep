param accessKey string
targetScope = 'subscription' // Required for resource group deployments

param spokeRgName string = 'CPS-NCUS-DC'
param spokeVmRgName string = 'CPS-NCUS-DC-VM'
param spokeVnetName string = 'NCUS-DC-VNet'
param spokeAddressSpace string = '10.53.0.0/20'
param spokeLocation string = 'centralus'
param spokeSubId string = '8de6c6e8-53af-4ded-a480-fd20c6093e78'

param spokeSubnets array = [
  { name: 'vmSubnet', prefix: '10.53.0.0/24' }
  { name: 'appsSubnet', prefix: '10.53.1.0/24' }
  { name: 'privateEPSubnet', prefix: '10.53.10.0/24' }
  // ... etc
]

// Reference the hub info for peering (if needed)
param hubVnetName string = 'NCUS-Infra-VNet'
param hubVnetResourceGroup string = 'CPS-NCUS-Infra'
param hubVnetSubscriptionId string = 'ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9'
// Cross-subscription subnet resource ID for NIC configuration
var vmSubnetResourceId = '/subscriptions/${spokeSubId}/resourceGroups/${spokeRgName}/providers/Microsoft.Network/virtualNetworks/${spokeVnetName}/subnets/vmSubnet'

module spokeVnet '../../modules/spokes/spokevnets.bicep' = {
  name: 'spokevnet'
  scope: resourceGroup(spokeSubId, spokeRgName)
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
    routeTableName: 'dcRouteTable'
  }
}

// Spoke VM example
// ── AVM: DC Spoke VM (Windows 11 Pro) ──
module spokeVM 'br/public:avm/res/compute/virtual-machine:0.9.0' = {
  name: 'AppsVM'
  scope: resourceGroup(spokeSubId, spokeVmRgName)
  params: {
    name: 'dcVM'
    location: spokeLocation
    osType: 'Windows'
    vmSize: 'Standard_B2ms'
    zone: 0
    encryptionAtHost: false
    adminUsername: 'vmuser'
    adminPassword: accessKey
    imageReference: {
      publisher: 'MicrosoftWindowsDesktop'
      offer: 'windows-11'
      sku: 'win11-24h2-pro'
      version: 'latest'
    }
    osDisk: {
      createOption: 'FromImage'
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

output spokeVnetId string = spokeVnet.outputs.vnetId
// For both hub and spoke main modules
output vnetId string = spokeVnet.outputs.vnetId
