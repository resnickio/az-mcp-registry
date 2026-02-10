// ============================================================================
// modules/api-management/apim-service.bicep — APIM Developer Tier
// ============================================================================
// Deploys Azure API Management in External VNet mode with system-assigned
// managed identity. Provisioning takes 30-45 minutes.
// ============================================================================

@description('Azure region')
param location string

@description('APIM instance name')
param apimName string

@description('Resource tags')
param tags object

@description('Subnet resource ID for APIM VNet integration')
param apimSubnetId string

@description('Publisher email (required by APIM)')
param publisherEmail string

@description('Publisher name (required by APIM)')
param publisherName string

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
  }
}

@description('APIM resource ID')
output apimId string = apimService.id

@description('APIM resource name')
output apimName string = apimService.name

@description('APIM gateway URL')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('APIM system-assigned managed identity principal ID')
output apimPrincipalId string = apimService.identity.principalId
