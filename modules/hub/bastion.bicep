@description('The Azure region for the Bastion host')
param location string
@description('Name for the Bastion Host')
param bastionName string = 'CPSBastion'
param hubVnetName string
param bastionSubnetName string = 'AzureBastionSubnet' // Bastion subnet name
param hubVnetResourceGroup string
// publlic IP for Bastion
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: '${bastionName}PIP'
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'CPS-Security'
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${bastionName}-${uniqueString(resourceGroup().id)}')
    }
  }
}
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: hubVnetName //hub VNet
  scope: resourceGroup(hubVnetResourceGroup) // 🔁 update if your RG is different
}
resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: bastionSubnetName
  parent: hubVnet
}
// Bastion Host
resource bastion 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: bastionName
  location: location
  tags: {
    Service: 'Network'
    CostCenter: 'Infrastructure'
    Environment: 'Production'
    Owner: 'cps-security'
    CreatedBy: 'ArnoldP'
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'Standard' // Standard SKU for Bastion or Basic SKU
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: {
            id: bastionSubnet.id // Bastion subnet  
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

@description('Name of the diagnostic setting for Bastion')
param bastionDiagName string = 'bastionDiagSettings'

@description('Log Analytics Workspace ID for diagnostic logs')
param logAnalyticsWorkspaceId string
@description('Diagnostic settings for Bastion public IP address')
resource bastionIpDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'bastionIPDiag'
  scope: publicIp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'DDoSProtectionNotifications'
        enabled: true
      }
      {
        category: 'DDoSMitigationFlowLogs'
        enabled: true
      }
      {
        category: 'DDoSMitigationReports'
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
resource bastionDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: bastionDiagName
  scope: bastion
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'BastionAuditLogs'
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

output bastionPublicIp string = publicIp.properties.ipAddress
output bastionDnsFqdn string = publicIp.properties.dnsSettings.fqdn
