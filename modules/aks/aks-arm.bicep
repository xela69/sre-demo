param clusterName string = 'aks-cluster'
@minValue(1)
@maxValue(50)
param agentCount int = 1
param agentVMSize string = 'Standard_DS2_v2' //'Standard_A2_v2'
param sshRSAPublicKey string
param adminUsername string = 'aksadmin'

resource cluster 'Microsoft.ContainerService/managedClusters@2025-07-02-preview' = {
  name: clusterName
  location: resourceGroup().location
  properties: {
    dnsPrefix: 'aks'
    agentPoolProfiles: [
  {
    name: 'agentpool'
    count: agentCount
    vmSize: agentVMSize
    mode: 'System'
  }
]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshRSAPublicKey
          }
        ]
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output controlPlaneFQDN string = cluster.properties.fqdn
