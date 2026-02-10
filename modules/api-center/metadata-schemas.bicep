// ============================================================================
// modules/api-center/metadata-schemas.bicep — Governance Metadata Schemas
// ============================================================================
// Defines required metadata that must be provided when registering MCP servers.
// All schemas are assigned to the 'api' entity and marked as required.
// ============================================================================

@description('API Center service name')
param apiCenterName string

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' existing = {
  name: apiCenterName
}

// ── Security Classification ─────────────────────────────────────────────────

resource securityClassification 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'securityclassification'
  parent: apiCenter
  properties: {
    assignedTo: [
      {
        entity: 'api'
        required: true
        deprecated: false
      }
    ]
    schema: '{"type":"string","title":"security-classification","oneOf":[{"const":"public","description":""},{"const":"internal","description":""},{"const":"confidential","description":""},{"const":"restricted","description":""}]}'
  }
}

// ── MCP Transport ───────────────────────────────────────────────────────────

resource mcpTransport 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'mcptransport'
  parent: apiCenter
  properties: {
    assignedTo: [
      {
        entity: 'api'
        required: true
        deprecated: false
      }
    ]
    schema: '{"type":"string","title":"mcp-transport","oneOf":[{"const":"stdio","description":""},{"const":"sse","description":""},{"const":"streamable-http","description":""}]}'
  }
}

// ── MCP Protocol Version ────────────────────────────────────────────────────

resource mcpProtocolVersion 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'mcpprotocolversion'
  parent: apiCenter
  properties: {
    assignedTo: [
      {
        entity: 'api'
        required: true
        deprecated: false
      }
    ]
    schema: '{"title":"mcp-protocol-version","type":"string"}'
  }
}

// ── Data Classification (multi-select array) ────────────────────────────────

resource dataClassification 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'dataclassification'
  parent: apiCenter
  properties: {
    assignedTo: [
      {
        entity: 'api'
        required: true
        deprecated: false
      }
    ]
    schema: '{"type":"array","title":"data-classification","items":{"type":"string","oneOf":[{"const":"none","description":""},{"const":"pii","description":""},{"const":"phi","description":""}]}}'
  }
}

// ── Technical Contact ───────────────────────────────────────────────────────

resource technicalContact 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'technicalcontact'
  parent: apiCenter
  properties: {
    assignedTo: [
      {
        entity: 'api'
        required: true
        deprecated: false
      }
    ]
    schema: '{"title":"technical-contact","type":"string"}'
  }
}
