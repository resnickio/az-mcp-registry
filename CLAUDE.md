# CLAUDE.md — Azure API Center MCP Server Registry

## Project overview

This repository deploys an **Azure API Center instance configured as an enterprise MCP (Model Context Protocol) server registry** using modular Bicep IaC. It provides centralized discovery and governance for MCP servers consumed by VS Code, GitHub Copilot, Azure AI Foundry, and custom AI agents.

The primary use case is an **enterprise allowlist for GitHub Copilot MCP servers** — starting with low-risk public-information servers (Microsoft Learn, Context7) and scaling to servers that use user credentials (GitHub MCP Server) and custom enterprise MCP servers that require enumeration protection.

**Deployment topology:** Single environment, single region
**Auth model:** Entra ID user authentication, gated by security group membership. APIM system-assigned managed identity for backend API Center access.
**API version pinned to:** `2024-03-01` (GA)
**SKU:** Free tier

## Architecture decisions

- **API Center as MCP Registry**: API Center natively implements the MCP Registry v0.1 spec at its data plane endpoint (`https://{name}.data.{region}.azure-apicenter.ms/workspaces/default/v0.1/servers`). We do NOT build a custom registry — we use the first-party implementation.
- **APIM proxy layer**: Azure API Management (Developer tier, External VNet mode) sits in front of the API Center data plane. APIM provides per-user rate limiting (60 req/min by user OID), request/response logging to Application Insights, and VNet integration that API Center lacks natively. MCP clients point to the APIM gateway URL, not the API Center data plane directly. APIM uses a hybrid auth pattern: it validates the user's JWT for identity logging, then uses its own system-assigned managed identity to call the API Center backend.
- **No private endpoints on API Center**: API Center does not support private endpoints, VNet integration, or IP firewalls. The APIM proxy in External VNet mode provides VNet presence and NSG-controlled ingress, but the backend call from APIM to API Center still traverses the public endpoint. Full network isolation would require an internal APIM + Application Gateway topology.
- **Single workspace**: Only `default` workspace is supported. Do not attempt to create additional workspaces.
- **Deployment Stacks**: Production deploys will use Azure Deployment Stacks with `denyWriteAndDelete` to prevent drift. Never deploy with raw `az deployment group create` in production.
- **Metadata-driven governance**: Required metadata schemas enforce security classification, MCP transport type, protocol version, data classification, and technical contact at registration time. These are not optional — removing `required: true` breaks the governance model.
- **Security group gating**: Access to the MCP registry data plane is controlled by membership in an Entra ID security group. Users authenticate with their standard Entra ID account. The group is assigned the Azure API Center Data Reader role on the API Center instance.
- **No diagnostic settings on API Center**: API Center (`microsoft.apicenter/services`) does not support Azure Monitor diagnostic settings. However, the APIM proxy logs all requests to Application Insights, providing the observability that API Center lacks natively. Activity Log and Event Grid remain available for ARM-level audit and registration events.

## Deployed resources

This deployment creates the following resources. Actual names are derived from the parameter file using the naming convention `{prefix}-{environment}-{resourcetype}`.

| Resource | Name Pattern | Notes |
|---|---|---|
| Resource Group | `{prefix}-{env}-rg` | All resources deployed here |
| API Center | `{prefix}-{env}-mcpr` | May be in a different region than the RG (see note below) |
| API Management | `{prefix}-{env}-apim` | Developer tier, External VNet mode |
| Virtual Network | `{prefix}-{env}-vnet` | Contains `snet-apim` subnet for APIM |
| NSG (APIM subnet) | attached to `snet-apim` | Required inbound rules for APIM health |
| Application Insights | `{prefix}-{env}-appi` | APIM request logging |
| Log Analytics Workspace | `{prefix}-{env}-law` | May be in the RG region if different from APIM region |
| Entra ID Security Group | (configured in parameters) | Controls end-user access to MCP registry |

**Note:** API Center is only available in a subset of Azure regions (Australia East, Canada Central, Central India, East US, France Central, Sweden Central, UK South, West Europe). If your resource group region is not in this list, API Center (and co-located resources like APIM) must be deployed to a supported region. The parameter file controls the API Center location separately.

**APIM gateway URL (MCP clients use this):** `https://<apim-name>.azure-api.net`
**API Center data plane (backend, not exposed to clients):** `https://<api-center-name>.data.<region>.azure-apicenter.ms`
**MCP Registry URL (via APIM):** `https://<apim-name>.azure-api.net/workspaces/default/v0.1/servers`

## Repository structure

```
├── CLAUDE.md                          # This file
├── README.md                          # Setup guide and architecture docs
├── bicepconfig.json                   # Linter rules (errors, not warnings)
├── main.bicep                         # Orchestration — wires all modules
├── modules/
│   ├── api-center/
│   │   ├── service.bicep              # API Center + default workspace
│   │   ├── environment.bicep          # Environment definitions
│   │   ├── metadata-schemas.bicep     # Governance metadata (JSON Schema)
│   │   └── api-registration.bicep     # Individual MCP server registrations
│   ├── api-management/
│   │   ├── apim-service.bicep         # APIM instance (Developer tier, External VNet)
│   │   ├── apim-api.bicep             # API definition + policies (JWT, rate limit, backend)
│   │   ├── apim-diagnostics.bicep     # Application Insights + Log Analytics + APIM logger
│   │   ├── vnet.bicep                 # VNet + snet-apim subnet + NSG
│   │   └── policies/
│   │       └── mcp-registry-proxy.xml # APIM policy (JWT, rate limit, MI auth, backend routing)
│   ├── identity/
│   │   └── role-assignments.bicep     # RBAC: Data Reader for consumers, Contributor for admins
│   └── monitoring/                    # Reserved for future use (Event Grid)
├── parameters/
│   └── main.bicepparam.example        # Example parameter values (copy and customize)
├── architecture.md                    # Architecture narrative + Mermaid diagrams
├── runbook.md                         # Operational runbook
└── .github/workflows/
    ├── bicep-validate.yml             # PR gate: lint → validate → what-if
    └── bicep-deploy.yml               # Merge to main: deploy via Deployment Stack
```

## Key conventions

### Naming

Resource names follow the pattern: `{prefix}-{environment}-{resourcetype}` where `{prefix}` is set in the parameter file.

| Abbreviation | Resource Type |
|---|---|
| `rg` | Resource Group |
| `mcpr` | API Center (MCP Registry) |
| `apim` | API Management |
| `vnet` | Virtual Network |
| `appi` | Application Insights |
| `law` | Log Analytics Workspace |
| `mid` | Managed Identity |

### Tags

All resources are tagged with:
- `env`: environment identifier (e.g. `dev`, `qa`, `prod`)
- `project`: `mcp-registry`

### Bicep

- **API version**: All `Microsoft.ApiCenter` resources use `2024-03-01`. Do not upgrade to preview versions without explicit approval — `2024-06-01-preview` adds `apiSources` but changes behavior.
- **Naming**: Resource names must match `^[a-zA-Z0-9-]{3,90}$`. Use kebab-case.
- **Parameters**: Use `.bicepparam` files, not JSON. Secrets go in Key Vault and are referenced via `getSecret()`.
- **Identity**: Always set `principalType: 'ServicePrincipal'` on role assignments for managed identities. Set `principalType: 'Group'` for security groups. Omitting `principalType` causes 48-hour Microsoft Graph resolution delays.
- **Role assignment names**: Always use `guid(scope, principalId, roleDefinitionId)` for deterministic idempotent names.
- **No hardcoded URLs or locations**: The linter enforces `no-hardcoded-env-urls` and `no-hardcoded-location` as errors.
- **Parent property**: Use `parent:` on child resources, not embedded resource names. The linter enforces `use-parent-property`.

### Metadata schemas

Five required metadata schemas are deployed, all assigned to the `api` entity:

| Schema Name | Resource Name | Type | Values |
|---|---|---|---|
| security-classification | `securityclassification` | string (enum) | `public`, `internal`, `confidential`, `restricted` |
| mcp-transport | `mcptransport` | string (enum) | `stdio`, `sse`, `streamable-http` |
| mcp-protocol-version | `mcpprotocolversion` | string (free text) | e.g. `2025-03-26` |
| data-classification | `dataclassification` | array of strings (multi-select) | `none`, `pii`, `phi` |
| technical-contact | `technicalcontact` | string (free text) | email or team name |

- Schema values are **stringified JSON Schema** in the `properties.schema` field.
- `assignedTo` controls which entity types (`api`, `environment`, `deployment`) the metadata applies to.
- Setting `required: true` means the field must be provided at registration time — this is how we enforce governance.
- Supported JSON Schema types: `string`, `number`, `boolean`, `array`, `object`. Use `oneOf` with `const` for constrained choices (not `enum`).
- `data-classification` is an `array` type allowing multi-select (a server can handle both PII and PHI).

### MCP server registration pattern

Each MCP server registration requires these linked resources in order:
1. `apis` — the server entry (title, kind, description, customProperties)
2. `apis/versions` — semantic version with lifecycle stage
3. `apis/deployments` — binds to environment, holds `server.runtimeUri[]` (the actual MCP endpoint)
4. (Optional) `apis/versions/definitions` — OpenAPI spec with `servers[0].url` for portal visibility

The `kind` field on APIs: use `rest` in Bicep (GA). The portal UI supports selecting "MCP" as a type which maps to the registry spec, but the Bicep resource schema uses `rest`, `graphql`, `grpc`, `soap`, `webhook`, or `websocket`.

### RBAC model

Typical role assignments on the API Center instance:

| Principal | Type | Role | Purpose |
|---|---|---|---|
| `<your-security-group>` | Security Group | Azure API Center Data Reader | End-user MCP server discovery |
| `<your-apim-instance>` | APIM System-Assigned MI | Azure API Center Data Reader | APIM backend calls to API Center data plane |
| `<your-admin-user>` | User | Azure API Center Data Reader | Dev/admin testing |

Available API Center RBAC roles:

| Role | GUID | Use |
|---|---|---|
| Azure API Center Data Reader | `c7244dfb-f447-457d-b2ba-3999044d1706` | MCP clients (data plane discovery) |
| Azure API Center Service Contributor | `dd24193f-ef65-44e5-8a7e-6fa6e03f7713` | CI/CD pipeline (register/update servers) |
| Azure API Center Service Reader | `6cba8790-29c5-48e5-bab1-c7541b01cb04` | Auditors (read-only ARM) |
| Azure API Center Compliance Manager | `ede9aaa3-4627-494e-be13-4aa7c256148d` | Governance team (read + analysis) |

### CI/CD

- **GitHub Actions** with OIDC federated credentials (workload identity). No service principal secrets.
- **Pipeline stages**: Lint → Validate → What-If → Deploy
- PR validation runs lint + validate + what-if with diff as PR comment.
- Production deploy uses `azure/bicep-deploy@v2` with `type: deploymentStack`.
- Pin Bicep CLI version in workflows for reproducibility.

### Event Grid events

API Center emits these events for automation:
- `Microsoft.ApiCenter.ApiDefinitionAdded` — new MCP server spec uploaded
- `Microsoft.ApiCenter.ApiDefinitionUpdated` — spec updated
- `Microsoft.ApiCenter.AnalysisResultsUpdated` — linting completed

## Common tasks

### Register a new MCP server

1. Create a new `.bicep` file in `modules/api-center/` or add to an existing registration module.
2. Define the `apis`, `apis/versions`, and `apis/deployments` resources.
3. Populate ALL required `customProperties` (security-classification, mcp-transport, mcp-protocol-version, data-classification, technical-contact).
4. Set `lifecycleStage` appropriately — new servers start at `preview` or `production`.
5. Open a PR — the validate workflow will run what-if showing the new resources.

### Grant a new MCP client access

**For end users:** Add them to the MCP registry readers Entra ID security group (configured in the parameter file).

**For service principals / managed identities:**
1. Get the client service's managed identity principal ID.
2. Add a role assignment in `modules/identity/role-assignments.bicep` using the Data Reader role GUID.
3. The client authenticates to the data plane with a token for audience `https://azure-apicenter.net/.default`.

### Deprecate an MCP server

1. Update the version's `lifecycleStage` to `deprecated`.
2. Add `deprecation-date` and `replacement-api-id` custom metadata if those schemas exist.
3. Event Grid will fire `ApiDefinitionUpdated` — downstream automation should notify consumers.

## Gotchas and constraints

- **Workspace**: Only `default` is supported. Creating others will fail silently or error.
- **No private endpoints**: This is a hard platform limitation. Plan identity-based security.
- **No diagnostic settings**: `microsoft.apicenter/services` does not support Azure Monitor diagnostic settings. Use Activity Log for ARM-level audit and Event Grid for data plane events.
- **Anonymous access**: Must be explicitly disabled via REST API post-deployment. The Bicep schema does not expose this toggle. Run: `az rest --method patch --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiCenter/services/{name}?api-version=2024-03-01" --body '{"properties":{"anonymousAccess":"disabled"}}'`
- **CLI data plane tokens**: The Azure CLI app (`04b07795-...`) is NOT preauthorized by Microsoft for the API Center data plane resource (`c3ca1a77-...`). `az account get-access-token --resource https://azure-apicenter.net` will fail with `AADSTS65002`. End-user clients (VS Code, GitHub Copilot) use different app IDs that are preauthorized and work correctly. For CLI testing, use a custom app registration with client credentials flow.
- **Metadata schema updates**: Changing a schema's JSON after deployment may break existing APIs that have values conforming to the old schema. Add new schemas rather than modifying existing ones.
- **Rate limits**: Data plane API has undocumented rate limits. For high-throughput discovery, cache registry responses on the client side.
- **Deployment ordering**: Metadata schemas must deploy before APIs that reference them in `customProperties`. Bicep handles this via `dependsOn` implicit ordering when using `parent:`, but explicit ordering may be needed in the orchestration module.
- **Sample API**: API Center auto-creates a `swagger-petstore` sample API on provisioning. This should be deleted before production use or it will appear in the MCP registry.
- **Region availability**: API Center is only available in: Australia East, Canada Central, Central India, East US, France Central, Sweden Central, UK South, West Europe. If your resource group is in an unsupported region, deploy API Center to the nearest supported region and set the location in the parameter file.
- **Entra ID enterprise app**: The portal access wizard creates an enterprise application in Entra ID (named `{api-center-name}-apic-aad`). In an enterprise setting, this registration should be performed by the Identity Team as an SSO integration request.
- **APIM provisioning time**: Developer tier APIM takes 30-45 minutes to provision. Plan accordingly for initial deployments and tier changes. The Deployment Stack timeout may need to be increased.
- **APIM NSG requirements**: The `snet-apim` subnet requires specific NSG rules for APIM to function (management endpoint inbound on 3443, load balancer inbound on 6390, Azure Infrastructure inbound). Missing rules cause APIM health to degrade silently.
- **Deployment Stack timeout with APIM**: The default Deployment Stack timeout may not be sufficient for initial APIM provisioning (30-45 min). Use `--timeout` flag or expect the first deployment to require patience. Subsequent deployments (updates) are much faster.
- **APIM managed identity role assignment ordering**: The APIM system-assigned managed identity is only available after APIM is created. The role assignment granting it Data Reader on API Center must run after APIM provisioning, requiring explicit `dependsOn` in the orchestration module.
- **API Center SKU required**: The Bicep type definition for `Microsoft.ApiCenter/services@2024-03-01` does not include the `sku` property, but Azure requires it at deploy time (Deployment Stacks will fail with "The Sku property on the given model is null"). Add `sku: { name: 'Free' }` with `#disable-next-line BCP187` to suppress the Bicep warning.
- **APIM policy XML C# string escaping**: C# expressions in APIM policy XML (inside `@(...)`) must use `&quot;` for string literals, not raw `"` or single quotes `'`. Raw `"` breaks XML parsing; single quotes `'` are C# `char` literals and cause "Too many characters in character literal" errors. Example: `GetValueOrDefault(&quot;Authorization&quot;,&quot;&quot;)`.
- **Manual role assignments conflict with Bicep**: If a role assignment (same principal + role + scope) was created manually in the portal, Bicep will fail with `RoleAssignmentExists` because the manually-assigned GUID differs from the deterministic `guid()` computed by Bicep. Fix: delete the manual assignment first so Bicep can recreate it with a deterministic name.
- **Log Analytics Workspace location**: The LAW may be in a different region than APIM and App Insights if the resource group region differs from the API Center region. The diagnostics module uses separate `location` and `logAnalyticsLocation` parameters to handle this split.

## Environment variables for local development

```bash
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export AZURE_LOCATION="<your-api-center-region>"       # Must be an API Center supported region
export API_CENTER_NAME="<your-api-center-name>"
export APIM_NAME="<your-apim-name>"
export APIM_GATEWAY_URL="https://<your-apim-name>.azure-api.net"
```

## Useful commands

```bash
# Lint
az bicep lint --file main.bicep

# Validate without deploying
az deployment group validate \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters parameters/main.bicepparam

# What-if
az deployment group what-if \
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

# Disable anonymous access (post-deployment)
az rest --method patch \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME?api-version=2024-03-01" \
  --body '{"properties":{"anonymousAccess":"disabled"}}'

# List registered APIs
az rest --method get \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/workspaces/default/apis?api-version=2024-03-01"

# List metadata schemas
az rest --method get \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/metadataSchemas?api-version=2024-03-01"

# Query MCP registry via APIM gateway (how MCP clients access it)
curl -H "Authorization: Bearer $TOKEN" \
  "$APIM_GATEWAY_URL/workspaces/default/v0.1/servers"

# Check APIM health
az apim show --name $APIM_NAME --resource-group $AZURE_RESOURCE_GROUP --query "provisioningState" -o tsv

# View APIM managed identity principal ID
az apim show --name $APIM_NAME --resource-group $AZURE_RESOURCE_GROUP --query "identity.principalId" -o tsv
```
