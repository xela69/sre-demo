targetScope = 'tenant'

@description('Short prefix used to build management group and resource names.')
param platformPrefix string = 'xela'

@description('Fully qualified resource ID of the parent management group (defaults to tenant root).')
param parentManagementGroupId string = tenantResourceId('Microsoft.Management/managementGroups', tenant().tenantId)

@description('Name for the root management group that will sit under the parent.')
param rootManagementGroupName string = '${platformPrefix}-root'

@description('Display name for the root management group.')
param rootManagementGroupDisplayName string = '${toUpper(platformPrefix)} Root'

@description('Child management groups (beyond the root) to create.')
param childManagementGroups array = [
  {
    name: '${platformPrefix}-platform'
    displayName: '${toUpper(platformPrefix)} Platform'
  }
  {
    name: '${platformPrefix}-landingzones'
    displayName: '${toUpper(platformPrefix)} Landing Zones'
  }
  {
    name: '${platformPrefix}-sandbox'
    displayName: '${toUpper(platformPrefix)} Sandbox'
  }
]

module managementGroupHierarchy './mg-policy.bicep' = {
  name: 'managementGroupHierarchy'
  params: {
    rootManagementGroupName: rootManagementGroupName
    rootDisplayName: rootManagementGroupDisplayName
    parentManagementGroupId: parentManagementGroupId
    childManagementGroups: childManagementGroups
  }
}

@description('Deploy baseline monitoring in the dedicated management subscription.')
param deployManagementSubscriptionBaseline bool = true

@description('Subscription ID that hosts shared management resources (Log Analytics, Automation, etc.).')
param managementSubscriptionId string

@description('Resource group name for the management baseline assets.')
param managementResourceGroupName string = '${platformPrefix}-management-rg'

@description('Azure region used for the management baseline.')
param managementLocation string = 'westus'

@description('Name of the shared Log Analytics workspace.')
param logAnalyticsWorkspaceName string = '${platformPrefix}-mgmt-law'

@description('Name of the Automation Account linked to Log Analytics.')
param automationAccountName string = '${platformPrefix}-mgmt-aa'

@description('Tags applied to the management subscription resource group and baseline resources.')
param managementTags object = {
  Service: 'PlatformManagement'
  CostCenter: 'Infrastructure'
  Environment: 'Production'
  Owner: 'Xelatech'
}

module managementBaseline './subscription-baseline.bicep' = if (deployManagementSubscriptionBaseline) {
  name: 'managementBaseline'
  scope: subscription(managementSubscriptionId)
  params: {
    resourceGroupName: managementResourceGroupName
    location: managementLocation
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    automationAccountName: automationAccountName
    tags: managementTags
  }
}

output rootManagementGroupId string = managementGroupHierarchy.outputs.rootManagementGroupId
output managementGroupIds object = managementGroupHierarchy.outputs.managementGroupIds
output managementBaseline object = deployManagementSubscriptionBaseline ? {
  subscriptionId: managementSubscriptionId
  resourceGroupName: managementResourceGroupName
  logAnalyticsWorkspaceId: managementBaseline.outputs.logAnalyticsWorkspaceId
  automationAccountId: managementBaseline.outputs.automationAccountId
} : {}
