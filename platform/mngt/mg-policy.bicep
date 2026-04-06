targetScope = 'tenant'

@description('Name of the root management group that will be created (no spaces, unique in tenant).')
param rootManagementGroupName string

@description('Display name for the root management group.')
param rootDisplayName string = rootManagementGroupName

@description('Fully qualified resource ID of the parent management group. Defaults to the tenant root group.')
param parentManagementGroupId string = tenantResourceId('Microsoft.Management/managementGroups', tenant().tenantId)

@description('Collection of child management groups to create. When parentId is omitted the group is created under the root created by this module.')
param childManagementGroups array = [
  {
    name: '${rootManagementGroupName}-platform'
    displayName: '${rootManagementGroupName}-platform'
  }
]

var rootManagementGroupId = tenantResourceId('Microsoft.Management/managementGroups', rootManagementGroupName)

var normalizedChildGroups = [for mg in childManagementGroups: {
  name: mg.name
  displayName: mg.?displayName ?? mg.name
  parentId: mg.?parentId ?? rootManagementGroupId
}]

resource rootManagementGroup 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: rootManagementGroupName
  properties: {
    displayName: rootDisplayName
    details: {
      parent: {
        id: parentManagementGroupId
      }
    }
  }
}

resource childManagementGroupResources 'Microsoft.Management/managementGroups@2023-04-01' = [for mg in normalizedChildGroups: {
  name: mg.name
  properties: {
    displayName: mg.displayName
    details: {
      parent: {
        id: mg.parentId
      }
    }
  }
}]

var childManagementGroupIds = [for mg in normalizedChildGroups: {
  name: mg.name
  id: tenantResourceId('Microsoft.Management/managementGroups', mg.name)
}]

output rootManagementGroupId string = rootManagementGroup.id
output managementGroupIds object = {
  root: {
    name: rootManagementGroupName
    id: rootManagementGroupId
  }
  children: childManagementGroupIds
}
