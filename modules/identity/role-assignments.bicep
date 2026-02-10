// ============================================================================
// modules/identity/role-assignments.bicep — RBAC Role Assignments
// ============================================================================
// Assigns API Center roles to security groups and service principals.
// ============================================================================

@description('API Center resource ID')
param apiCenterId string

@description('API Center resource name')
param apiCenterName string

@description('Object ID of the Entra ID security group for end-user access')
param readerGroupPrincipalId string = ''

@description('Principal ID of APIM system-assigned managed identity for data plane access')
param apimPrincipalId string = ''

@description('Principal IDs of admins/pipelines that need Service Contributor access')
param adminPrincipalIds array = []

// Azure API Center Data Reader
var dataReaderRoleId = 'c7244dfb-f447-457d-b2ba-3999044d1706'

// Azure API Center Service Contributor
var serviceContributorRoleId = 'dd24193f-ef65-44e5-8a7e-6fa6e03f7713'

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' existing = {
  name: apiCenterName
}

// ── Data Reader: Security Group ─────────────────────────────────────────────

resource groupReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(readerGroupPrincipalId)) {
  name: guid(apiCenterId, readerGroupPrincipalId, dataReaderRoleId)
  scope: apiCenter
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataReaderRoleId)
    principalId: readerGroupPrincipalId
    principalType: 'Group'
  }
}

// ── Data Reader: APIM Managed Identity ───────────────────────────────────────

resource apimDataReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(apimPrincipalId)) {
  name: guid(apiCenterId, apimPrincipalId, dataReaderRoleId)
  scope: apiCenter
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataReaderRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ── Service Contributor: Admin / CI/CD Principals ───────────────────────────

resource adminAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (principalId, i) in adminPrincipalIds: {
    name: guid(apiCenterId, principalId, serviceContributorRoleId)
    scope: apiCenter
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceContributorRoleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]
