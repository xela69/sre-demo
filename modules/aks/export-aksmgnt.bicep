param loadBalancers_kubernetes_name string = 'kubernetes'
param virtualNetworks_aks_vnet_26180121_name string = 'aks-vnet-26180121'
param networkSecurityGroups_aks_agentpool_26180121_nsg_name string = 'aks-agentpool-26180121-nsg'
param virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name string = 'aks-nodepool1-25885041-vmss'
param publicIPAddresses_f8653c64_b5e9_4ca4_950d_f5da9bf738e3_name string = 'f8653c64-b5e9-4ca4-950d-f5da9bf738e3'
param userAssignedIdentities_xela_aks_large_agentpool_name string = 'xela-aks-large-agentpool'
param galleries_AKSUbuntu_externalid string = '/subscriptions/109a5e88-712a-48ae-9078-9ca8b3c81345/resourceGroups/AKS-Ubuntu/providers/Microsoft.Compute/galleries/AKSUbuntu'
param disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_9ae2cd94c7eb486aa1ab4bd2e8e213ef_externalid string = '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.Compute/disks/aks-nodepool1-258850aks-nodepool1-2588504disk1_9ae2cd94c7eb486aa1ab4bd2e8e213ef'
param disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_6a81a18ebe9d4cee9430d40bafeb06f4_externalid string = '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.Compute/disks/aks-nodepool1-258850aks-nodepool1-2588504disk1_6a81a18ebe9d4cee9430d40bafeb06f4'
param disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_78b32d22b2444428a99130db1e95b3b5_externalid string = '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.Compute/disks/aks-nodepool1-258850aks-nodepool1-2588504disk1_78b32d22b2444428a99130db1e95b3b5'
param disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_45161fba5a73466dba9d83375d45a7ec_externalid string = '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.Compute/disks/aks-nodepool1-258850aks-nodepool1-2588504disk1_45161fba5a73466dba9d83375d45a7ec'

resource userAssignedIdentities_xela_aks_large_agentpool_name_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: userAssignedIdentities_xela_aks_large_agentpool_name
  location: 'eastus'
}

resource networkSecurityGroups_aks_agentpool_26180121_nsg_name_resource 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: networkSecurityGroups_aks_agentpool_26180121_nsg_name
  location: 'eastus'
  properties: {
    securityRules: []
  }
}

resource publicIPAddresses_f8653c64_b5e9_4ca4_950d_f5da9bf738e3_name_resource 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: publicIPAddresses_f8653c64_b5e9_4ca4_950d_f5da9bf738e3_name
  location: 'eastus'
  tags: {
    'aks-managed-cluster-name': 'xela-aks-large'
    'aks-managed-cluster-rg': 'xela-aks-eastus'
    'aks-managed-type': 'aks-slb-managed-outbound-ip'
  }
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    ipAddress: '4.157.194.12'
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    ipTags: []
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_AKSLinuxBilling 'Microsoft.Compute/virtualMachineScaleSets/extensions@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
  properties: {
    provisioningState: 'Succeeded'
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.AKS'
    type: 'Compute.AKS.Linux.Billing'
    typeHandlerVersion: '1.0'
    settings: {}
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_vmssCSE 'Microsoft.Compute/virtualMachineScaleSets/extensions@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: 'vmssCSE'
  properties: {
    provisioningState: 'Succeeded'
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {}
  }
}

resource loadBalancers_kubernetes_name_resource 'Microsoft.Network/loadBalancers@2024-07-01' = {
  name: loadBalancers_kubernetes_name
  location: 'eastus'
  tags: {
    'aks-managed-cluster-name': 'xela-aks-large'
    'aks-managed-cluster-rg': 'xela-aks-eastus'
  }
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'f8653c64-b5e9-4ca4-950d-f5da9bf738e3'
        id: '${loadBalancers_kubernetes_name_resource.id}/frontendIPConfigurations/f8653c64-b5e9-4ca4-950d-f5da9bf738e3'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddresses_f8653c64_b5e9_4ca4_950d_f5da9bf738e3_name_resource.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'aksOutboundBackendPool'
        id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
        properties: {
          loadBalancerBackendAddresses: [
            {
              name: '999e9e9d-37e3-4949-ad63-014592ad202d'
              properties: {}
            }
            {
              name: 'bd26c442-6f9c-482f-8300-de7578d60027'
              properties: {}
            }
            {
              name: 'fc0a1367-00e3-4931-9436-23a35dcdc07f'
              properties: {}
            }
            {
              name: 'a32c72dd-3701-4171-a3ee-646386d6e194'
              properties: {}
            }
          ]
        }
      }
      {
        name: loadBalancers_kubernetes_name
        id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
        properties: {
          loadBalancerBackendAddresses: [
            {
              name: '9868d90a-a917-47eb-b970-a79e000fa526'
              properties: {}
            }
            {
              name: 'e2c9a19e-b68a-4790-a5b5-6ab8a53c65dd'
              properties: {}
            }
            {
              name: '2c1f5ccc-f1d6-41bc-aae8-829a83a66c0f'
              properties: {}
            }
            {
              name: '856a1cb3-4c0e-4714-b9d9-95e990e40456'
              properties: {}
            }
          ]
        }
      }
    ]
    loadBalancingRules: []
    probes: []
    inboundNatRules: []
    outboundRules: [
      {
        name: 'aksOutboundRule'
        id: '${loadBalancers_kubernetes_name_resource.id}/outboundRules/aksOutboundRule'
        properties: {
          allocatedOutboundPorts: 0
          protocol: 'All'
          enableTcpReset: true
          idleTimeoutInMinutes: 30
          backendAddressPool: {
            id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
          }
          frontendIPConfigurations: [
            {
              id: '${loadBalancers_kubernetes_name_resource.id}/frontendIPConfigurations/f8653c64-b5e9-4ca4-950d-f5da9bf738e3'
            }
          ]
        }
      }
    ]
    inboundNatPools: []
  }
}

resource loadBalancers_kubernetes_name_aksOutboundBackendPool 'Microsoft.Network/loadBalancers/backendAddressPools@2024-07-01' = {
  name: '${loadBalancers_kubernetes_name}/aksOutboundBackendPool'
  properties: {
    loadBalancerBackendAddresses: [
      {
        name: '999e9e9d-37e3-4949-ad63-014592ad202d'
        properties: {}
      }
      {
        name: 'bd26c442-6f9c-482f-8300-de7578d60027'
        properties: {}
      }
      {
        name: 'fc0a1367-00e3-4931-9436-23a35dcdc07f'
        properties: {}
      }
      {
        name: 'a32c72dd-3701-4171-a3ee-646386d6e194'
        properties: {}
      }
    ]
  }
  dependsOn: [
    loadBalancers_kubernetes_name_resource
  ]
}

resource loadBalancers_kubernetes_name_loadBalancers_kubernetes_name 'Microsoft.Network/loadBalancers/backendAddressPools@2024-07-01' = {
  name: '${loadBalancers_kubernetes_name}/${loadBalancers_kubernetes_name}'
  properties: {
    loadBalancerBackendAddresses: [
      {
        name: '9868d90a-a917-47eb-b970-a79e000fa526'
        properties: {}
      }
      {
        name: 'e2c9a19e-b68a-4790-a5b5-6ab8a53c65dd'
        properties: {}
      }
      {
        name: '2c1f5ccc-f1d6-41bc-aae8-829a83a66c0f'
        properties: {}
      }
      {
        name: '856a1cb3-4c0e-4714-b9d9-95e990e40456'
        properties: {}
      }
    ]
  }
  dependsOn: [
    loadBalancers_kubernetes_name_resource
  ]
}

resource virtualNetworks_aks_vnet_26180121_name_resource 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworks_aks_vnet_26180121_name
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.224.0.0/12'
      ]
    }
    privateEndpointVNetPolicies: 'Disabled'
    subnets: [
      {
        name: 'aks-subnet'
        id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
        properties: {
          addressPrefix: '10.224.0.0/16'
          networkSecurityGroup: {
            id: networkSecurityGroups_aks_agentpool_26180121_nsg_name_resource.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: 'aks-appgateway'
        id: virtualNetworks_aks_vnet_26180121_name_aks_appgateway.id
        properties: {
          addressPrefix: '10.238.0.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: 'aks-virtualkubelet'
        id: virtualNetworks_aks_vnet_26180121_name_aks_virtualkubelet.id
        properties: {
          addressPrefix: '10.239.0.0/16'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource virtualNetworks_aks_vnet_26180121_name_aks_appgateway 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetworks_aks_vnet_26180121_name}/aks-appgateway'
  properties: {
    addressPrefix: '10.238.0.0/24'
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    virtualNetworks_aks_vnet_26180121_name_resource
  ]
}

resource virtualNetworks_aks_vnet_26180121_name_aks_virtualkubelet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetworks_aks_vnet_26180121_name}/aks-virtualkubelet'
  properties: {
    addressPrefix: '10.239.0.0/16'
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    virtualNetworks_aks_vnet_26180121_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0_virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_AKSLinuxBilling 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/0/${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.AKS'
    type: 'Compute.AKS.Linux.Billing'
    typeHandlerVersion: '1.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1_virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_AKSLinuxBilling 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/1/${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.AKS'
    type: 'Compute.AKS.Linux.Billing'
    typeHandlerVersion: '1.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2_virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_AKSLinuxBilling 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/2/${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.AKS'
    type: 'Compute.AKS.Linux.Billing'
    typeHandlerVersion: '1.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3_virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_AKSLinuxBilling 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/3/${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.AKS'
    type: 'Compute.AKS.Linux.Billing'
    typeHandlerVersion: '1.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0_vmssCSE 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/0/vmssCSE'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1_vmssCSE 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/1/vmssCSE'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2_vmssCSE 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/2/vmssCSE'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3_vmssCSE 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions@2024-11-01' = {
  name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}/3/vmssCSE'
  location: 'eastus'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {}
  }
  dependsOn: [
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3
    virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  ]
}

resource virtualNetworks_aks_vnet_26180121_name_aks_subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${virtualNetworks_aks_vnet_26180121_name}/aks-subnet'
  properties: {
    addressPrefix: '10.224.0.0/16'
    networkSecurityGroup: {
      id: networkSecurityGroups_aks_agentpool_26180121_nsg_name_resource.id
    }
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    virtualNetworks_aks_vnet_26180121_name_resource
  ]
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' = {
  name: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name
  location: 'eastus'
  tags: {
    'aks-managed-azure-cni-overlay': 'true'
    'aks-managed-bootstrap-profile-acr-name': ''
    'aks-managed-consolidated-additional-properties': '49ac5d7a-a097-11f0-a815-faa88f0da9ce'
    'aks-managed-createOperationID': 'c4d62872-51c6-4dc2-9aeb-92457a99bc6a'
    'aks-managed-creationSource': 'vmssclient-aks-nodepool1-25885041-vmss'
    'aks-managed-enable-imds-restriction': 'false'
    'aks-managed-kubeletIdentityClientID': 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
    'aks-managed-networkisolated-outbound-type': ''
    'aks-managed-orchestrator': 'Kubernetes:1.32.7'
    'aks-managed-poolName': 'nodepool1'
    'aks-managed-resourceNameSuffix': '26180121'
    'aks-managed-ssh-access': 'LocalUser'
    'aks-managed-coordination': 'true'
  }
  sku: {
    name: 'Standard_DS2_v2'
    tier: 'Standard'
    capacity: 4
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool': {}
    }
  }
  properties: {
    singlePlacementGroup: false
    orchestrationMode: 'Uniform'
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name
        adminUsername: 'azureuser'
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/azureuser/.ssh/authorized_keys'
                keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
              }
            ]
          }
          provisionVMAgent: true
        }
        secrets: []
        allowExtensionOperations: true
        requireGuestProvisionSignal: true
      }
      storageProfile: {
        osDisk: {
          osType: 'Linux'
          createOption: 'FromImage'
          caching: 'ReadOnly'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 128
        }
        imageReference: {
          id: '${galleries_AKSUbuntu_externalid}/images/2204gen2containerd/versions/202509.23.0'
        }
        diskControllerType: 'SCSI'
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              disableTcpStateTracking: false
              dnsSettings: {
                dnsServers: []
              }
              enableIPForwarding: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: {
                      id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      {
                        id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
                      }
                      {
                        id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'vmssCSE'
            properties: {
              autoUpgradeMinorVersion: true
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.0'
              settings: {}
            }
          }
          {
            name: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name}-AKSLinuxBilling'
            properties: {
              autoUpgradeMinorVersion: true
              publisher: 'Microsoft.AKS'
              type: 'Compute.AKS.Linux.Billing'
              typeHandlerVersion: '1.0'
              settings: {}
            }
          }
        ]
        extensionsTimeBudget: 'PT16M'
      }
    }
    overprovision: false
    doNotRunExtensionsOnOverprovisionedVMs: false
    platformFaultDomainCount: 1
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: '0'
  location: 'eastus'
  tags: {
    'aks-managed-azure-cni-overlay': 'true'
    'aks-managed-bootstrap-profile-acr-name': ''
    'aks-managed-consolidated-additional-properties': '49ac5d7a-a097-11f0-a815-faa88f0da9ce'
    'aks-managed-createOperationID': 'c4d62872-51c6-4dc2-9aeb-92457a99bc6a'
    'aks-managed-creationSource': 'vmssclient-aks-nodepool1-25885041-vmss'
    'aks-managed-enable-imds-restriction': 'false'
    'aks-managed-kubeletIdentityClientID': 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
    'aks-managed-networkisolated-outbound-type': ''
    'aks-managed-orchestrator': 'Kubernetes:1.32.7'
    'aks-managed-poolName': 'nodepool1'
    'aks-managed-resourceNameSuffix': '26180121'
    'aks-managed-ssh-access': 'LocalUser'
    'aks-managed-coordination': 'true'
  }
  sku: {
    name: 'Standard_DS2_v2'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool': {}
    }
  }
  properties: {
    networkProfileConfiguration: {
      networkInterfaceConfigurations: [
        {
          name: 'aks-nodepool1-25885041-vmss'
          properties: {
            primary: true
            enableAcceleratedNetworking: true
            disableTcpStateTracking: false
            dnsSettings: {
              dnsServers: []
            }
            enableIPForwarding: true
            ipConfigurations: [
              {
                name: 'ipconfig1'
                properties: {
                  primary: true
                  subnet: {
                    id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
                  }
                  privateIPAddressVersion: 'IPv4'
                  loadBalancerBackendAddressPools: [
                    {
                      id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
                    }
                    {
                      id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    resilientVMDeletionStatus: 'Disabled'
    storageProfile: {
      imageReference: {
        id: '${galleries_AKSUbuntu_externalid}/images/2204gen2containerd/versions/202509.23.0'
      }
      osDisk: {
        osType: 'Linux'
        name: 'aks-nodepool1-258850aks-nodepool1-2588504disk1_9ae2cd94c7eb486aa1ab4bd2e8e213ef'
        createOption: 'FromImage'
        caching: 'ReadOnly'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          id: disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_9ae2cd94c7eb486aa1ab4bd2e8e213ef_externalid
        }
        diskSizeGB: 128
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: 'aks-nodepool1-25885041-vmss000000'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
            }
          ]
        }
        provisionVMAgent: true
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_0.id}/networkInterfaces/aks-nodepool1-25885041-vmss'
        }
      ]
    }
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: '1'
  location: 'eastus'
  tags: {
    'aks-managed-azure-cni-overlay': 'true'
    'aks-managed-bootstrap-profile-acr-name': ''
    'aks-managed-consolidated-additional-properties': '49ac5d7a-a097-11f0-a815-faa88f0da9ce'
    'aks-managed-createOperationID': 'c4d62872-51c6-4dc2-9aeb-92457a99bc6a'
    'aks-managed-creationSource': 'vmssclient-aks-nodepool1-25885041-vmss'
    'aks-managed-enable-imds-restriction': 'false'
    'aks-managed-kubeletIdentityClientID': 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
    'aks-managed-networkisolated-outbound-type': ''
    'aks-managed-orchestrator': 'Kubernetes:1.32.7'
    'aks-managed-poolName': 'nodepool1'
    'aks-managed-resourceNameSuffix': '26180121'
    'aks-managed-ssh-access': 'LocalUser'
    'aks-managed-coordination': 'true'
  }
  sku: {
    name: 'Standard_DS2_v2'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool': {}
    }
  }
  properties: {
    networkProfileConfiguration: {
      networkInterfaceConfigurations: [
        {
          name: 'aks-nodepool1-25885041-vmss'
          properties: {
            primary: true
            enableAcceleratedNetworking: true
            disableTcpStateTracking: false
            dnsSettings: {
              dnsServers: []
            }
            enableIPForwarding: true
            ipConfigurations: [
              {
                name: 'ipconfig1'
                properties: {
                  primary: true
                  subnet: {
                    id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
                  }
                  privateIPAddressVersion: 'IPv4'
                  loadBalancerBackendAddressPools: [
                    {
                      id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
                    }
                    {
                      id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    resilientVMDeletionStatus: 'Disabled'
    storageProfile: {
      imageReference: {
        id: '${galleries_AKSUbuntu_externalid}/images/2204gen2containerd/versions/202509.23.0'
      }
      osDisk: {
        osType: 'Linux'
        name: 'aks-nodepool1-258850aks-nodepool1-2588504disk1_6a81a18ebe9d4cee9430d40bafeb06f4'
        createOption: 'FromImage'
        caching: 'ReadOnly'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          id: disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_6a81a18ebe9d4cee9430d40bafeb06f4_externalid
        }
        diskSizeGB: 128
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: 'aks-nodepool1-25885041-vmss000001'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
            }
          ]
        }
        provisionVMAgent: true
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_1.id}/networkInterfaces/aks-nodepool1-25885041-vmss'
        }
      ]
    }
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: '2'
  location: 'eastus'
  tags: {
    'aks-managed-azure-cni-overlay': 'true'
    'aks-managed-bootstrap-profile-acr-name': ''
    'aks-managed-consolidated-additional-properties': '49ac5d7a-a097-11f0-a815-faa88f0da9ce'
    'aks-managed-createOperationID': 'c4d62872-51c6-4dc2-9aeb-92457a99bc6a'
    'aks-managed-creationSource': 'vmssclient-aks-nodepool1-25885041-vmss'
    'aks-managed-enable-imds-restriction': 'false'
    'aks-managed-kubeletIdentityClientID': 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
    'aks-managed-networkisolated-outbound-type': ''
    'aks-managed-orchestrator': 'Kubernetes:1.32.7'
    'aks-managed-poolName': 'nodepool1'
    'aks-managed-resourceNameSuffix': '26180121'
    'aks-managed-ssh-access': 'LocalUser'
    'aks-managed-coordination': 'true'
  }
  sku: {
    name: 'Standard_DS2_v2'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool': {}
    }
  }
  properties: {
    networkProfileConfiguration: {
      networkInterfaceConfigurations: [
        {
          name: 'aks-nodepool1-25885041-vmss'
          properties: {
            primary: true
            enableAcceleratedNetworking: true
            disableTcpStateTracking: false
            dnsSettings: {
              dnsServers: []
            }
            enableIPForwarding: true
            ipConfigurations: [
              {
                name: 'ipconfig1'
                properties: {
                  primary: true
                  subnet: {
                    id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
                  }
                  privateIPAddressVersion: 'IPv4'
                  loadBalancerBackendAddressPools: [
                    {
                      id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
                    }
                    {
                      id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    resilientVMDeletionStatus: 'Disabled'
    storageProfile: {
      imageReference: {
        id: '${galleries_AKSUbuntu_externalid}/images/2204gen2containerd/versions/202509.23.0'
      }
      osDisk: {
        osType: 'Linux'
        name: 'aks-nodepool1-258850aks-nodepool1-2588504disk1_78b32d22b2444428a99130db1e95b3b5'
        createOption: 'FromImage'
        caching: 'ReadOnly'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          id: disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_78b32d22b2444428a99130db1e95b3b5_externalid
        }
        diskSizeGB: 128
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: 'aks-nodepool1-25885041-vmss000002'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
            }
          ]
        }
        provisionVMAgent: true
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_2.id}/networkInterfaces/aks-nodepool1-25885041-vmss'
        }
      ]
    }
  }
}

resource virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines@2024-11-01' = {
  parent: virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_resource
  name: '3'
  location: 'eastus'
  tags: {
    'aks-managed-azure-cni-overlay': 'true'
    'aks-managed-bootstrap-profile-acr-name': ''
    'aks-managed-consolidated-additional-properties': '49ac5d7a-a097-11f0-a815-faa88f0da9ce'
    'aks-managed-createOperationID': 'c4d62872-51c6-4dc2-9aeb-92457a99bc6a'
    'aks-managed-creationSource': 'vmssclient-aks-nodepool1-25885041-vmss'
    'aks-managed-enable-imds-restriction': 'false'
    'aks-managed-kubeletIdentityClientID': 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
    'aks-managed-networkisolated-outbound-type': ''
    'aks-managed-orchestrator': 'Kubernetes:1.32.7'
    'aks-managed-poolName': 'nodepool1'
    'aks-managed-resourceNameSuffix': '26180121'
    'aks-managed-ssh-access': 'LocalUser'
    'aks-managed-coordination': 'true'
  }
  sku: {
    name: 'Standard_DS2_v2'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool': {}
    }
  }
  properties: {
    networkProfileConfiguration: {
      networkInterfaceConfigurations: [
        {
          name: 'aks-nodepool1-25885041-vmss'
          properties: {
            primary: true
            enableAcceleratedNetworking: true
            disableTcpStateTracking: false
            dnsSettings: {
              dnsServers: []
            }
            enableIPForwarding: true
            ipConfigurations: [
              {
                name: 'ipconfig1'
                properties: {
                  primary: true
                  subnet: {
                    id: virtualNetworks_aks_vnet_26180121_name_aks_subnet.id
                  }
                  privateIPAddressVersion: 'IPv4'
                  loadBalancerBackendAddressPools: [
                    {
                      id: loadBalancers_kubernetes_name_loadBalancers_kubernetes_name.id
                    }
                    {
                      id: loadBalancers_kubernetes_name_aksOutboundBackendPool.id
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    resilientVMDeletionStatus: 'Disabled'
    storageProfile: {
      imageReference: {
        id: '${galleries_AKSUbuntu_externalid}/images/2204gen2containerd/versions/202509.23.0'
      }
      osDisk: {
        osType: 'Linux'
        name: 'aks-nodepool1-258850aks-nodepool1-2588504disk1_45161fba5a73466dba9d83375d45a7ec'
        createOption: 'FromImage'
        caching: 'ReadOnly'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          id: disks_aks_nodepool1_258850aks_nodepool1_2588504disk1_45161fba5a73466dba9d83375d45a7ec_externalid
        }
        diskSizeGB: 128
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: 'aks-nodepool1-25885041-vmss000003'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
            }
          ]
        }
        provisionVMAgent: true
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: '${virtualMachineScaleSets_aks_nodepool1_25885041_vmss_name_3.id}/networkInterfaces/aks-nodepool1-25885041-vmss'
        }
      ]
    }
  }
}
