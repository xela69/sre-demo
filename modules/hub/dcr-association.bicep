// dcr-association.bicep
// Creates a Data Collection Rule association on an existing Virtual Machine
// This module must be deployed at the resource-group scope where the VM resides.

@description('Name of the existing Virtual Machine to associate')
param vmName string

@description('Resource ID of the Data Collection Rule to associate with the VM')
param dataCollectionRuleId string

@description('Unique name for the DCR association resource')
param associationName string = 'vmInsights-dcr-association'

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: associationName
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
  }
}

output associationId string = dcrAssociation.id
