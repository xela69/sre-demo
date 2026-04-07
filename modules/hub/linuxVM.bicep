param location string
param vmName string
param hubVnetName string
param hubVnetResourceGroup string
param hubStorageName string // for boot diagnostics in westus2
param adminUsername string = 'vmuser'
param sshPublicKey string // The SSH public key content
param vmSize string = 'Standard_D2als_v6'
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
  name: '${vmName}Nic-${take(uniqueString(resourceGroup().id), 4)}'
  location: location
  tags: {
    Service: 'Network'
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
            id: vmSubnet.id // the 1st subnet in the VNets
          }
        }
      }
    ]
  }
}

resource linuxVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: '${vmName}${take(uniqueString(resourceGroup().id), 4)}'
  location: location
  tags: {
    Service: 'VM'
    CostCenter: 'Linux'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  identity: {
    type: 'SystemAssigned' // Use system-assigned managed identity
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true // Disable password-based login
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys' // Adjust based on username
              keyData: sshPublicKey // Insert your public key here
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      allowExtensionOperations: true
      //requireGuestProvisionSignal: true
    }
    diagnosticsProfile: {
      bootDiagnostics: union(
        { enabled: true },
        location == 'westus2' ? { storageUri: 'https://${hubStorageName}.blob.${environment().suffixes.storage}/' } : {}
      )
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'Disk${vmName}'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: { storageAccountType: storageAccountType }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
}
// diagnostic settings for VMs
@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Region of the Log Analytics Workspace is located westus2')
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-vm-monitoring'
  location: location
  tags: {
    Service: 'Monitoring'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  kind: 'Linux'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounterDataSource30'
          counterSpecifiers: [
            '\\Memory\\Available Bytes'
            '\\Memory\\% Committed Bytes In Use'
            '\\Processor(_Total)\\% Processor Time'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\LogicalDisk(_Total)\\Disk Bytes/sec'
          ]
          samplingFrequencyInSeconds: 30
          streams: ['Microsoft-Perf']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la-dest'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: ['la-dest']
      }
    ]
  }
}

resource vmAMA 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  name: 'AzureMonitorLinuxAgent'
  parent: linuxVm // this auto-wires the correct VM name
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {}
  }
}

resource dcrAssoc 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${vmName}-dcr-association'
  scope: linuxVm
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'Attach DCR to VM for guest metrics'
  }
}
resource vmDashboards 'Microsoft.Portal/dashboards@2020-09-01-preview' = {
  name: 'vm-monitor-dashboard-${vmName}'
  location: resourceGroup().location
  tags: {
    Service: 'Monitoring'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'Xelatech'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  }
  properties: {
    lenses: [
      {
        order: 0
        parts: [
          {
            position: {
              x: 0
              y: 0
              rowSpan: 4
              colSpan: 6
            }
          }
        ]
      }
    ]
    metadata: {
      type: 'Extension/HubsExtension/PartType/MarkdownPart'
      inputs: [
        {
          name: 'resourceType'
          value: 'microsoft.compute/virtualmachines'
        }
        {
          name: 'resourceId'
          value: linuxVm.id
        }
      ]
      settings: {
        content: {
          chart: {
            title: 'CPU Utilization (VM ${vmName})'
            metrics: [
              {
                metricNamespace: 'Microsoft.Compute/virtualMachines'
                metricName: 'Percentage CPU'
                aggregation: 'Average'
              }
            ]
          }
        }
      }
    }
  }
}
// outputs
output vmIdentity string = linuxVm.identity.principalId
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
