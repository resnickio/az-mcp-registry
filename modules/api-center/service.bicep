// ============================================================================
// modules/api-center/service.bicep — API Center Service + Default Workspace
// ============================================================================

@description('API Center service name')
@minLength(3)
@maxLength(45)
param apiCenterName string

@description('Azure region for API Center')
param location string

@description('Resource tags')
param tags object

// Note: Bicep type definition for 2024-03-01 doesn't include 'sku' but Azure requires it.
resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' = {
  name: apiCenterName
  location: location
  tags: tags
  identity: {
    type: 'None'
  }
  #disable-next-line BCP187
  sku: {
    name: 'Free'
  }
  properties: {}
}

@description('API Center resource ID')
output apiCenterId string = apiCenter.id

@description('API Center resource name')
output apiCenterName string = apiCenter.name

@description('API Center data plane endpoint (constructed from name and location)')
output dataPlaneEndpoint string = 'https://${apiCenterName}.data.${location}.azure-apicenter.ms'
