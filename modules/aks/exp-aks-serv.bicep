param managedClusters_xela_aks_large_name string = 'xela-aks-large'
param userAssignedIdentities_xela_aks_large_agentpool_externalid string = '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/MC_xela-aks-eastus_xela-aks-large_eastus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/xela-aks-large-agentpool'

resource managedClusters_xela_aks_large_name_resource 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: managedClusters_xela_aks_large_name
  location: 'eastus'
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.32'
    dnsPrefix: 'xela-aks-l-xela-aks-eastus-86d55e'
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 4
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        kubeletDiskType: 'OS'
        maxPods: 250
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
        scaleDownMode: 'Delete'
        powerState: {
          code: 'Running'
        }
        orchestratorVersion: '1.32'
        enableNodePublicIP: false
        mode: 'System'
        enableEncryptionAtHost: false
        enableUltraSSD: false
        osType: 'Linux'
        osSKU: 'Ubuntu'
        upgradeSettings: {
          maxSurge: '10%'
          maxUnavailable: '0'
        }
        enableFIPS: false
        securityProfile: {
          enableVTPM: false
          enableSecureBoot: false
        }
      }
    ]
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDqAztIdctug7SK7Ra7LxLgrejLtvzX3f+foJXXIrNO3Rb/FvyGC9WClnoMQC7eWHDD+oKF6+URhuqqgGFXdgcf1Mv5C7mmHsLfWGlhi2VJ2w5oI3Wf5kcUC4mYl4CJyrd+53qqnqo3f++CxA3RbEyIbbk0C1a4Z2HGFNFlKD0RVJriRx20Xx0VRhAFsAJj//jMHLUNXZcChG1fONR23aMNdJcAo4qRw5D80UloXCxpXcl8tfIOETpwwdNlUlS9PXhP9n1OJnffBbhAvn99mD00JJ1rjFr3xIhWlgFQY3sk3Pyqd9hmWFFLYkLSKPlmueWcMP95+pMYTsArh3mZ+PxMQnG5qpxnavPPbqn4Ku1lzYLM6soE+9NATxhCc9F/gHfdHwio5LDDJmExgNuV3mtwlpb5Vyo1G1VuD3HqB7XI2/BbaFL/m9syBl1vLeW8dMXsaVZjJmrlhhApHKwKkxwfMy6wetzG80zEsLGUA6QzS+OV+TLwQDKK+qw8W7NxiargFwq9WRREKfOmJyUGe8ulW8MkokhfElK8PcEARnnb7tMbN6Mwqa3ZmwVpbILzwcOsH9SBLzI2h2tssyaC4pYTsIBRXyfatSMinlMF1HoBQoEBzyKy4p3wblI00XkZX2+ig/O/kZOvJf6qOOMpWSYSi0grtG0olMpFDmksZcg8DQ== arnold@ArnoldMac.local\n'
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    nodeResourceGroup: 'MC_xela-aks-eastus_${managedClusters_xela_aks_large_name}_eastus'
    enableRBAC: true
    supportPlan: 'KubernetesOfficial'
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'none'
      networkDataplane: 'azure'
      loadBalancerSku: 'standard'
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
        backendPoolType: 'nodeIPConfiguration'
      }
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      outboundType: 'loadBalancer'
      podCidrs: [
        '10.244.0.0/16'
      ]
      serviceCidrs: [
        '10.0.0.0/16'
      ]
      ipFamilies: [
        'IPv4'
      ]
    }
    identityProfile: {
      kubeletidentity: {
        resourceId: userAssignedIdentities_xela_aks_large_agentpool_externalid
        clientId: 'fb8e7b01-7ce1-4ea0-b816-25d97e0c00ca'
        objectId: '7c11bce2-638d-4a4b-9208-977546c5df7d'
      }
    }
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
    }
    disableLocalAccounts: false
    securityProfile: {}
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: false
    }
    workloadAutoScalerProfile: {}
    metricsProfile: {
      costAnalysis: {
        enabled: false
      }
    }
    nodeProvisioningProfile: {
      mode: 'Manual'
      defaultNodePools: 'Auto'
    }
    bootstrapProfile: {
      artifactSource: 'Direct'
    }
  }
}

resource managedClusters_xela_aks_large_name_nodepool1 'Microsoft.ContainerService/managedClusters/agentPools@2025-05-01' = {
  parent: managedClusters_xela_aks_large_name_resource
  name: 'nodepool1'
  properties: {
    count: 4
    vmSize: 'Standard_DS2_v2'
    osDiskSizeGB: 128
    osDiskType: 'Managed'
    kubeletDiskType: 'OS'
    maxPods: 250
    type: 'VirtualMachineScaleSets'
    enableAutoScaling: false
    scaleDownMode: 'Delete'
    powerState: {
      code: 'Running'
    }
    orchestratorVersion: '1.32'
    enableNodePublicIP: false
    mode: 'System'
    enableEncryptionAtHost: false
    enableUltraSSD: false
    osType: 'Linux'
    osSKU: 'Ubuntu'
    upgradeSettings: {
      maxSurge: '10%'
      maxUnavailable: '0'
    }
    enableFIPS: false
    securityProfile: {
      enableVTPM: false
      enableSecureBoot: false
    }
  }
}

resource managedClusters_xela_aks_large_name_nodepool1_aks_nodepool1_25885041_vmss000000 'Microsoft.ContainerService/managedClusters/agentPools/machines@2025-04-02-preview' = {
  parent: managedClusters_xela_aks_large_name_nodepool1
  name: 'aks-nodepool1-25885041-vmss000000'
  properties: {
    network: {}
  }
  dependsOn: [
    managedClusters_xela_aks_large_name_resource
  ]
}

resource managedClusters_xela_aks_large_name_nodepool1_aks_nodepool1_25885041_vmss000001 'Microsoft.ContainerService/managedClusters/agentPools/machines@2025-04-02-preview' = {
  parent: managedClusters_xela_aks_large_name_nodepool1
  name: 'aks-nodepool1-25885041-vmss000001'
  properties: {
    network: {}
  }
  dependsOn: [
    managedClusters_xela_aks_large_name_resource
  ]
}

resource managedClusters_xela_aks_large_name_nodepool1_aks_nodepool1_25885041_vmss000002 'Microsoft.ContainerService/managedClusters/agentPools/machines@2025-04-02-preview' = {
  parent: managedClusters_xela_aks_large_name_nodepool1
  name: 'aks-nodepool1-25885041-vmss000002'
  properties: {
    network: {}
  }
  dependsOn: [
    managedClusters_xela_aks_large_name_resource
  ]
}

resource managedClusters_xela_aks_large_name_nodepool1_aks_nodepool1_25885041_vmss000003 'Microsoft.ContainerService/managedClusters/agentPools/machines@2025-04-02-preview' = {
  parent: managedClusters_xela_aks_large_name_nodepool1
  name: 'aks-nodepool1-25885041-vmss000003'
  properties: {
    network: {}
  }
  dependsOn: [
    managedClusters_xela_aks_large_name_resource
  ]
}
