// ============================================================================
// modules/api-center/environment.bicep — Environment Definitions
// ============================================================================

@description('API Center service name')
param apiCenterName string

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' existing = {
  name: apiCenterName
}

resource defaultWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-03-01' existing = {
  name: 'default'
  parent: apiCenter
}

resource developmentEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-03-01' = {
  name: 'development'
  parent: defaultWorkspace
  properties: {
    title: 'development'
    description: 'Development environment for MCP server deployments'
    kind: 'development'
    onboarding: {
      developerPortalUri: []
    }
    server: {
      managementPortalUri: []
    }
  }
}

resource productionEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-03-01' = {
  name: 'production'
  parent: defaultWorkspace
  properties: {
    title: 'production'
    description: 'Production environment for MCP server deployments'
    kind: 'production'
    onboarding: {
      developerPortalUri: []
    }
    server: {
      managementPortalUri: []
    }
  }
}

@description('Development environment resource ID')
output developmentEnvironmentId string = developmentEnvironment.id

@description('Production environment resource ID')
output productionEnvironmentId string = productionEnvironment.id
