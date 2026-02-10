# Azure API Center — Enterprise MCP Server Registry

Modular Bicep IaC for deploying Azure API Center as a centralized [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server registry with enterprise governance, Entra ID authentication, and GitOps-driven lifecycle management.

The primary use case is an **enterprise allowlist for GitHub Copilot MCP servers** — providing centralized discovery and governance so organizations can control which MCP servers are available to developers.

## What this deploys

- **Azure API Center** (Free tier) as the MCP registry
- **Azure API Management** (Developer tier, External VNet mode) as a proxy in front of the API Center data plane — provides per-user rate limiting, request logging to Application Insights, and VNet integration
- **Virtual Network** with dedicated APIM subnet (`snet-apim`, 10.0.0.0/24) and required NSG rules
- **Application Insights** + **Log Analytics Workspace** for APIM request/response logging and diagnostics
- **Default workspace** with a development environment
- **Governance metadata schemas** enforcing security classification, MCP transport, protocol version, data classification, and technical contact on all registered MCP servers
- **RBAC role assignments** — Data Reader for consumers (via Entra ID security group and APIM managed identity), Service Contributor for pipelines
- **Entra ID integration** — users authenticate with their standard corporate account; access gated by security group membership

## Prerequisites

- Azure subscription with `Microsoft.ApiCenter` resource provider registered
- Azure CLI ≥ 2.64 with Bicep CLI ≥ 0.32
- Entra ID permissions to create security groups and enterprise applications (or coordinate with your Identity Team)
- (For CI/CD) GitHub repository with OIDC federated credential configured for Azure

## Quick start

```bash
# Clone and configure
git clone <repo-url> && cd az-mcp-registry

# Set environment variables
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_RESOURCE_GROUP="<your-resource-group>"

# Copy the parameter template and fill in your values
cp parameters/main.bicepparam.example parameters/main.bicepparam
# Edit parameters/main.bicepparam with your values

# Validate
az deployment group validate \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam

# Deploy as Deployment Stack
az stack group create \
  --name mcp-registry-stack \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam \
  --action-on-unmanage deleteResources \
  --deny-settings-mode denyWriteAndDelete

# Post-deployment: disable anonymous access (not configurable via Bicep)
az rest --method patch \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/<api-center-name>?api-version=2024-03-01" \
  --body '{"properties":{"anonymousAccess":"disabled"}}'
```

## Post-deployment manual steps

These steps cannot be automated via Bicep and must be performed after deployment:

1. **Disable anonymous access** — see CLI command above
2. **Register API Center with Entra ID** — use the API Center portal Settings → access wizard to create the enterprise application, or submit an SSO integration request to your Identity Team
3. **Create security group** — create an Entra ID security group (e.g. `sg-mcp-registry-readers`) and assign it the Azure API Center Data Reader role on the API Center instance
4. **Delete sample API** — API Center auto-creates a `swagger-petstore` sample; delete it before registering MCP servers

## Authentication model

```
User (Entra ID corporate account)
  → Authenticates to Entra ID, receives JWT
    → Calls APIM gateway with Bearer token
      → APIM validates JWT (extracts user OID for rate limiting + logging)
      → APIM calls API Center backend using its own system-assigned managed identity
        → APIM managed identity has Azure API Center Data Reader role
          → API Center returns MCP server list
            → APIM returns response to user (logged to Application Insights)
```

This is a **hybrid auth pattern**: the user's JWT is validated by APIM for identity extraction (rate limiting by OID, logging), but the actual backend call to API Center uses APIM's managed identity. APIM currently validates that the caller has a valid Entra ID token with an `oid` claim. The security group `sg-mcp-registry-readers` retains the Data Reader role for direct API Center access scenarios.

**Known limitation:** The Azure CLI (`az account get-access-token --resource https://azure-apicenter.net`) does not work for data plane access due to a Microsoft first-party app preauthorization gap (`AADSTS65002`). End-user clients (VS Code, GitHub Copilot) use different app registrations and are not affected.

## Documentation

| Document | Description |
|---|---|
| [CLAUDE.md](./CLAUDE.md) | AI coding assistant context — conventions, gotchas, common tasks |
| [architecture.md](./architecture.md) | Architecture narrative with Mermaid diagrams |
| [runbook.md](./runbook.md) | Operational runbook — day-2 tasks, troubleshooting |

## Repository structure

```
├── main.bicep                         # Orchestration entry point
├── modules/
│   ├── api-center/
│   │   ├── service.bicep              # API Center + workspace
│   │   ├── environment.bicep          # Environment definitions
│   │   ├── metadata-schemas.bicep     # Governance metadata
│   │   └── api-registration.bicep     # Reusable MCP server registration
│   ├── api-management/
│   │   ├── apim-service.bicep         # APIM instance (Developer tier, External VNet)
│   │   ├── apim-api.bicep             # API definition + policies (JWT, rate limit, backend)
│   │   ├── apim-diagnostics.bicep     # Application Insights + Log Analytics + APIM logger
│   │   ├── vnet.bicep                 # VNet + snet-apim subnet + NSG
│   │   └── policies/
│   │       └── mcp-registry-proxy.xml # APIM policy (JWT, rate limit, MI auth, backend routing)
│   ├── identity/
│   │   └── role-assignments.bicep     # RBAC bindings
│   └── monitoring/                    # Reserved for future use (Event Grid)
├── parameters/
│   └── main.bicepparam.example        # Parameter template — copy and fill in your values
└── .github/workflows/
    ├── bicep-validate.yml             # PR: lint → validate → what-if
    └── bicep-deploy.yml               # Merge: Deployment Stack deploy
```

## Key design decisions

1. **API version `2024-03-01` (GA)** — pinned for stability. Preview features (`apiSources`) not used.
2. **Deployment Stacks with `denyWriteAndDelete`** — prevents drift and unauthorized modifications.
3. **APIM proxy for logging, rate limiting, and VNet** — API Center lacks diagnostic settings and network controls. APIM (Developer tier, External VNet mode) provides per-user rate limiting (60 req/min by user OID), request logging to Application Insights, and VNet presence. MCP clients call the APIM gateway, which forwards to the API Center backend using its own managed identity.
4. **Entra ID security group gating** — users authenticate with corporate accounts; access controlled by group membership, not individual assignments.
5. **Required metadata schemas** — governance enforced at registration time, not after.
6. **No private endpoints on API Center** — API Center does not support private endpoints. APIM in External VNet mode provides VNet integration, but the APIM-to-API-Center backend call is still public.
7. **Observability via APIM + Application Insights** — API Center does not support Azure Monitor diagnostic settings, but APIM logs all proxied requests to Application Insights, providing full request/response telemetry.

## License

This project is licensed under the [MIT License](LICENSE).
