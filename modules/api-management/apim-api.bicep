// ============================================================================
// modules/api-management/apim-api.bicep — API Definition + Operations + Policy
// ============================================================================
// Defines the MCP Registry proxy API in APIM with catch-all operations
// and the hybrid auth policy loaded from an external XML file.
// ============================================================================

@description('APIM instance name')
param apimName string

@description('API Center data plane URL (e.g. https://name.data.region.azure-apicenter.ms)')
param apiCenterDataPlaneUrl string

@description('Entra ID OpenID Connect configuration URL for JWT validation')
param openidConfigUrl string

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ── Named Values (referenced in policy XML as {{name}}) ─────────────────────

resource backendUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'api-center-backend-url'
  parent: apimService
  properties: {
    displayName: 'api-center-backend-url'
    value: apiCenterDataPlaneUrl
    secret: false
  }
}

resource openidConfigUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'entra-openid-config-url'
  parent: apimService
  properties: {
    displayName: 'entra-openid-config-url'
    value: openidConfigUrl
    secret: false
  }
}

// ── Backend ─────────────────────────────────────────────────────────────────

resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  name: 'api-center-backend'
  parent: apimService
  properties: {
    url: apiCenterDataPlaneUrl
    protocol: 'http'
    description: 'API Center MCP Registry data plane'
  }
}

// ── API Definition ──────────────────────────────────────────────────────────

resource mcpRegistryApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'mcp-registry'
  parent: apimService
  properties: {
    displayName: 'MCP Registry'
    description: 'Proxy to Azure API Center MCP Registry data plane'
    path: ''
    protocols: [
      'https'
    ]
    serviceUrl: apiCenterDataPlaneUrl
    subscriptionRequired: false
    apiType: 'http'
  }
}

// ── Operations (catch-all for registry paths) ───────────────────────────────

resource getServers 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'get-servers'
  parent: mcpRegistryApi
  properties: {
    displayName: 'Get MCP Servers'
    method: 'GET'
    urlTemplate: '/workspaces/default/v0.1/servers'
  }
}

resource getServersWildcard 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: 'get-wildcard'
  parent: mcpRegistryApi
  properties: {
    displayName: 'GET (wildcard)'
    method: 'GET'
    urlTemplate: '/*'
  }
}

// ── API-Level Policy ────────────────────────────────────────────────────────

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: mcpRegistryApi
  properties: {
    format: 'xml'
    value: loadTextContent('policies/mcp-registry-proxy.xml')
  }
  dependsOn: [
    backendUrlNamedValue
    openidConfigUrlNamedValue
  ]
}
