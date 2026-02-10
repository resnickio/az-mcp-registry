// ============================================================================
// modules/api-center/api-registration.bicep — MCP Server Registration
// ============================================================================
// Reusable module for registering an MCP server in the API Center registry.
// Creates the API entry, a version, and a deployment with runtime endpoint.
// ============================================================================

@description('API Center service name')
param apiCenterName string

@description('Server name (kebab-case identifier, e.g. context7-mcp)')
@minLength(3)
@maxLength(90)
param serverName string

@description('Display name for the server')
param serverTitle string

@description('Description of what the server provides')
param serverDescription string

@description('MCP server endpoint URL')
param endpointUrl string

@description('Security classification')
@allowed([
  'public'
  'internal'
  'confidential'
  'restricted'
])
param securityClassification string

@description('MCP transport type')
@allowed([
  'stdio'
  'sse'
  'streamable-http'
])
param mcpTransport string

@description('MCP protocol version (e.g. 2025-03-26)')
param mcpProtocolVersion string

@description('Data classification (array for multi-select)')
param dataClassification array

@description('Technical contact email or team name')
param technicalContact string

@description('Semantic version (e.g. 1.0.0)')
param version string = '1.0.0'

@description('Lifecycle stage')
@allowed([
  'design'
  'development'
  'testing'
  'preview'
  'production'
  'deprecated'
  'retired'
])
param lifecycleStage string = 'production'

@description('Environment name to deploy to')
param environmentName string = 'production'

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' existing = {
  name: apiCenterName
}

resource defaultWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-03-01' existing = {
  name: 'default'
  parent: apiCenter
}

// ── API Entry ───────────────────────────────────────────────────────────────

resource api 'Microsoft.ApiCenter/services/workspaces/apis@2024-03-01' = {
  name: serverName
  parent: defaultWorkspace
  properties: {
    title: serverTitle
    description: serverDescription
    kind: 'rest'
    customProperties: {
      'security-classification': securityClassification
      'mcp-transport': mcpTransport
      'mcp-protocol-version': mcpProtocolVersion
      'data-classification': dataClassification
      'technical-contact': technicalContact
    }
  }
}

// ── Version ─────────────────────────────────────────────────────────────────

resource apiVersion 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-03-01' = {
  name: replace('v${version}', '.', '-')
  parent: api
  properties: {
    title: 'v${version}'
    lifecycleStage: lifecycleStage
  }
}

// ── Deployment ──────────────────────────────────────────────────────────────

resource deployment 'Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-03-01' = {
  name: '${environmentName}-deployment'
  parent: api
  properties: {
    title: '${serverTitle} (${environmentName})'
    environmentId: '/workspaces/default/environments/${environmentName}'
    server: {
      runtimeUri: [
        endpointUrl
      ]
    }
    state: 'active'
  }
}

@description('API resource ID')
output apiId string = api.id

@description('API version resource ID')
output versionId string = apiVersion.id

@description('Deployment resource ID')
output deploymentId string = deployment.id
