param location string
param vmName string
param hubVnetName string
param hubVnetResourceGroup string
@secure()
param adminPassword string
param adminUsername string = 'vmuser'
param vmSize string = 'Standard_D2s_v6'
param storageAccountType string = 'Standard_LRS'

// Reference to existing hub VNet
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}

// Reference to existing firewall subnet
resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: 'vmSubnet'
  parent: hubVnet
}
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${vmName}-nic'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vmSubnet.id
          }
        }
      }
    ]
  }
}

// Create VM 
resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  tags: {
    Service: 'Compute'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { enableAutomaticUpdates: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        name: 'Disk${vmName}${take(uniqueString(resourceGroup().id), 4)}'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: { storageAccountType: storageAccountType }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}
/*/ creates AD login extension for VM and assigns roles 
@description('Object IDs of users or groups who will have User Login rights')
param aadUserObjectIds array = [
  '94a425e8-166a-4775-9e73-cf36e5720c06'
]
@description('Object IDs of users or groups who will have Admin Login rights')
param aadAdminObjectIds array = [
  '638fff67-edf5-40f7-b61c-3f1699f83eaa'
]

// Role definition IDs are built-in
var userLoginRoleId = 'bcd981a7-7f74-457b-83e1-cceb5d3b7b5c' // Virtual Machine User Login
var adminLoginRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7' // Virtual Machine Administrator Login

resource aadLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  name: 'AADLoginForWindows'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      mdmId: '0000000a-0000-0000-c000-000000000000'
    }
  }
}

resource userLoginAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for oid in aadUserObjectIds: {
  name: guid(vm.id, userLoginRoleId, oid)
  scope: vm
  properties: {
    principalId: oid
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userLoginRoleId)
    principalType: 'User'
  }
  dependsOn: [
  aadLoginExtension
  ]
}]

resource adminLoginAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for oid in aadAdminObjectIds: {
  name: guid(vm.id, adminLoginRoleId, oid)
  scope: vm
  properties: {
    principalId: oid
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', adminLoginRoleId)
    principalType: 'User'
  }
  dependsOn: [
  aadLoginExtension
  ]
}]*/

output vmNames array = [vm.name]
output vmId string = vm.id
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
