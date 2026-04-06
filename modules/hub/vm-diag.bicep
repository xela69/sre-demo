targetScope = 'resourceGroup'

param workspaceId string
param deployVM bool = true
param hubVmName string
param linuxVmName string

resource hubVmExisting 'Microsoft.Compute/virtualMachines@2024-07-01' existing = if (deployVM) {
  name: hubVmName
}

resource linuxVmExisting 'Microsoft.Compute/virtualMachines@2024-07-01' existing = if (deployVM) {
  name: linuxVmName
}

resource hubVmDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVM) {
  name: 'diag-hubvm'
  scope: hubVmExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource linuxVmDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVM) {
  name: 'diag-linuxvm'
  scope: linuxVmExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource hubVmNicExisting 'Microsoft.Network/networkInterfaces@2024-07-01' existing = if (deployVM) {
  name: '${hubVmName}-nic'
}

resource linuxVmNicExisting 'Microsoft.Network/networkInterfaces@2024-07-01' existing = if (deployVM) {
  name: '${linuxVmName}-nic'
}

resource hubVmNicDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVM) {
  name: 'diag-hubvm-nic'
  scope: hubVmNicExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource linuxVmNicDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVM) {
  name: 'diag-linuxvm-nic'
  scope: linuxVmNicExisting
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
