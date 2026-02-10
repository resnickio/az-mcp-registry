// ============================================================================
// modules/api-management/apim-diagnostics.bicep — App Insights + Logging
// ============================================================================
// Creates Log Analytics workspace, Application Insights, and configures
// APIM diagnostic logging with 100% sampling for dev environment.
// ============================================================================

@description('Azure region for Application Insights')
param location string

@description('Azure region for Log Analytics workspace (may differ from App Insights if resource group is in a different region)')
param logAnalyticsLocation string

@description('APIM instance name')
param apimName string

@description('Resource tags')
param tags object

@description('Application Insights name')
param appInsightsName string

@description('Log Analytics workspace name')
param logAnalyticsName string

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ── Log Analytics Workspace ─────────────────────────────────────────────────

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: logAnalyticsLocation
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ── Application Insights (workspace-backed) ─────────────────────────────────

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── APIM Logger (links APIM to App Insights) ────────────────────────────────

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  name: 'appinsights-logger'
  parent: apimService
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
    resourceId: appInsights.id
  }
}

// ── APIM Diagnostic Settings (request/response logging) ─────────────────────

resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  name: 'applicationinsights'
  parent: apimService
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
  }
}

@description('Application Insights resource ID')
output appInsightsId string = appInsights.id

@description('Log Analytics workspace resource ID')
output logAnalyticsId string = logAnalytics.id
