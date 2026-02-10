// ============================================================================
// main.bicep — Azure API Center MCP Server Registry Orchestration
// ============================================================================
// Deploys the complete MCP registry stack:
//   1. API Center service + default workspace
//   2. Environment definitions
//   3. Governance metadata schemas
//   4. APIM proxy (VNet, gateway, API policies, diagnostics)
//   5. RBAC role assignments
// ============================================================================

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for API Center and APIM (limited availability: australiaeast, canadacentral, centralindia, eastus, francecentral, swedencentral, uksouth, westeurope)')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralindia'
  'eastus'
  'francecentral'
  'swedencentral'
  'uksouth'
  'westeurope'
])
param apiCenterLocation string

@description('API Center service name (3-90 chars, alphanumeric + hyphens)')
@minLength(3)
@maxLength(90)
param apiCenterName string

@description('Object ID of the Entra ID security group for end-user MCP registry access')
param readerGroupPrincipalId string = ''

@description('Principal IDs of admins/pipelines that need Service Contributor access')
param adminPrincipalIds array = []

@description('Publisher email for APIM (required)')
param apimPublisherEmail string

@description('Publisher name for APIM (required)')
param apimPublisherName string

@description('Entra ID tenant ID for JWT validation in APIM policies')
param tenantId string

@description('VNet name for APIM subnet')
param vnetName string = '${apiCenterName}-vnet'

@description('APIM instance name (3-50 chars)')
param apimName string = '${apiCenterName}-apim'

@description('Application Insights name')
param appInsightsName string = '${apiCenterName}-appi'

@description('Log Analytics workspace name')
param logAnalyticsName string = '${apiCenterName}-law'

@description('Resource tags applied to all resources')
param tags object = {
  project: 'mcp-registry'
}

// ── Module: API Center Service ──────────────────────────────────────────────

module apiCenterService 'modules/api-center/service.bicep' = {
  name: 'deploy-api-center-service'
  params: {
    apiCenterName: apiCenterName
    location: apiCenterLocation
    tags: tags
  }
}

// ── Module: Environment ─────────────────────────────────────────────────────

module environment 'modules/api-center/environment.bicep' = {
  name: 'deploy-environments'
  params: {
    apiCenterName: apiCenterService.outputs.apiCenterName
  }
}

// ── Module: Metadata Schemas ────────────────────────────────────────────────

module metadataSchemas 'modules/api-center/metadata-schemas.bicep' = {
  name: 'deploy-metadata-schemas'
  params: {
    apiCenterName: apiCenterService.outputs.apiCenterName
  }
}

// ── Module: APIM VNet ───────────────────────────────────────────────────────

module apimVnet 'modules/api-management/vnet.bicep' = {
  name: 'deploy-apim-vnet'
  params: {
    location: apiCenterLocation
    vnetName: vnetName
    tags: tags
  }
}

// ── Module: APIM Service ────────────────────────────────────────────────────

module apimService 'modules/api-management/apim-service.bicep' = {
  name: 'deploy-apim-service'
  params: {
    location: apiCenterLocation
    apimName: apimName
    tags: tags
    apimSubnetId: apimVnet.outputs.apimSubnetId
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

// ── Module: APIM API + Policies ─────────────────────────────────────────────

module apimApi 'modules/api-management/apim-api.bicep' = {
  name: 'deploy-apim-api'
  params: {
    apimName: apimService.outputs.apimName
    apiCenterDataPlaneUrl: apiCenterService.outputs.dataPlaneEndpoint
    openidConfigUrl: '${az.environment().authentication.loginEndpoint}${tenantId}/v2.0/.well-known/openid-configuration'
  }
}

// ── Module: APIM Diagnostics ────────────────────────────────────────────────

module apimDiagnostics 'modules/api-management/apim-diagnostics.bicep' = {
  name: 'deploy-apim-diagnostics'
  params: {
    location: apiCenterLocation
    logAnalyticsLocation: resourceGroup().location
    apimName: apimService.outputs.apimName
    tags: tags
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
  }
}

// ── Module: RBAC Role Assignments ───────────────────────────────────────────

module roleAssignments 'modules/identity/role-assignments.bicep' = {
  name: 'deploy-role-assignments'
  params: {
    apiCenterId: apiCenterService.outputs.apiCenterId
    apiCenterName: apiCenterService.outputs.apiCenterName
    readerGroupPrincipalId: readerGroupPrincipalId
    apimPrincipalId: apimService.outputs.apimPrincipalId
    adminPrincipalIds: adminPrincipalIds
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('API Center resource ID')
output apiCenterId string = apiCenterService.outputs.apiCenterId

@description('API Center data plane endpoint (direct, bypasses APIM)')
output apiCenterDataPlaneEndpoint string = apiCenterService.outputs.dataPlaneEndpoint

@description('APIM gateway URL (entry point for MCP clients)')
output apimGatewayUrl string = apimService.outputs.apimGatewayUrl

@description('MCP Registry URL via APIM proxy for GitHub Copilot / VS Code')
output mcpRegistryUrl string = '${apimService.outputs.apimGatewayUrl}/workspaces/default/v0.1/servers'
