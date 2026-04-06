targetScope = 'subscription'

@description('Resource group name that will host the shared management resources.')
param resourceGroupName string

@description('Azure region for the management resource group and baseline resources.')
param location string

@description('Name of the shared Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Name of the Automation Account linked to Log Analytics.')
param automationAccountName string

@description('Tags applied to the management resource group and related resources.')
param tags object = {}

resource managementResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module baselineResources './resource-group-baseline.bicep' = {
  name: 'baselineResources'
  scope: managementResourceGroup
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    automationAccountName: automationAccountName
    tags: tags
  }
}

output resourceGroupName string = managementResourceGroup.name
output logAnalyticsWorkspaceId string = baselineResources.outputs.logAnalyticsWorkspaceId
output automationAccountId string = baselineResources.outputs.automationAccountId
