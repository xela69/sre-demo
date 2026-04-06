targetScope = 'managementGroup'

@description('Custom policy definitions to create at this management group.')
param customPolicyDefinitions array = []

@description('Policy initiatives (policy set definitions) to create at this management group.')
param customPolicyInitiatives array = []

@description('Policy assignments to create at this management group.')
param policyAssignments array = []

var normalizedPolicyDefinitions = [for definition in customPolicyDefinitions: {
  name: definition.name
  displayName: definition.?displayName ?? definition.name
  description: definition.?description ?? ''
  metadata: definition.?metadata ?? {}
  mode: definition.?mode ?? 'All'
  parameters: definition.?parameters ?? {}
  policyRule: definition.policyRule
}]

var normalizedPolicyInitiatives = [for initiative in customPolicyInitiatives: {
  name: initiative.name
  displayName: initiative.?displayName ?? initiative.name
  description: initiative.?description ?? ''
  metadata: initiative.?metadata ?? {}
  parameters: initiative.?parameters ?? {}
  policyDefinitionGroups: initiative.?policyDefinitionGroups ?? []
  definitionReferences: initiative.definitionReferences
}]

var normalizedPolicyAssignments = [for assignment in policyAssignments: {
  name: assignment.name
  displayName: assignment.?displayName ?? assignment.name
  description: assignment.?description ?? ''
  definitionId: assignment.definitionId
  enforcementMode: assignment.?enforcementMode ?? 'Default'
  parameters: assignment.?parameters ?? {}
  notScopes: assignment.?notScopes ?? []
  identityType: assignment.?identityType ?? null
  nonComplianceMessages: assignment.?nonComplianceMessages ?? []
}]

resource policyDefinitions 'Microsoft.Authorization/policyDefinitions@2021-06-01' = [for definition in normalizedPolicyDefinitions: {
  name: definition.name
  properties: {
    displayName: definition.displayName
    description: definition.description
    metadata: definition.metadata
    mode: definition.mode
    parameters: definition.parameters
    policyRule: definition.policyRule
  }
}]

resource policyInitiatives 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = [for initiative in normalizedPolicyInitiatives: {
  name: initiative.name
  properties: {
    displayName: initiative.displayName
    description: initiative.description
    metadata: initiative.metadata
    parameters: initiative.parameters
    policyDefinitionGroups: initiative.policyDefinitionGroups
    policyDefinitions: initiative.definitionReferences
  }
}]

resource policyAssignmentResources 'Microsoft.Authorization/policyAssignments@2022-06-01' = [for assignment in normalizedPolicyAssignments: {
  name: assignment.name
  properties: {
    displayName: assignment.displayName
    description: assignment.description
    policyDefinitionId: assignment.definitionId
    enforcementMode: assignment.enforcementMode
    parameters: assignment.parameters
    notScopes: assignment.notScopes
    nonComplianceMessages: assignment.nonComplianceMessages
  }
  identity: assignment.identityType == 'SystemAssigned' ? {
    type: 'SystemAssigned'
  } : null
}]

output policyDefinitionNames array = [for definition in normalizedPolicyDefinitions: definition.name]
output policyInitiativeNames array = [for initiative in normalizedPolicyInitiatives: initiative.name]
