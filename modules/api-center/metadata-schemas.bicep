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
    schema: '{"type":"string","title":"security-classification","oneOf":[{"const":"public","description":"Data freely available to the public"},{"const":"internal","description":"Internal organizational data"},{"const":"confidential","description":"Sensitive business data requiring specific authorization"},{"const":"restricted","description":"Highly sensitive data requiring explicit approval and auditing"}]}'
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
    schema: '{"type":"string","title":"mcp-transport","oneOf":[{"const":"stdio","description":"Standard I/O transport"},{"const":"sse","description":"Server-Sent Events transport"},{"const":"streamable-http","description":"Streamable HTTP transport"}]}'
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
    schema: '{"title":"mcp-protocol-version","type":"string","description":"MCP protocol version in date format (e.g. 2025-03-26)","pattern":"^\\\\d{4}-\\\\d{2}-\\\\d{2}$"}'
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
    schema: '{"type":"array","title":"data-classification","items":{"type":"string","oneOf":[{"const":"none","description":"No sensitive data handled"},{"const":"pii","description":"Personally identifiable information"},{"const":"phi","description":"Protected health information"},{"const":"pci","description":"Payment card industry data"}]}}'
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
