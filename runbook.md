# Operational Runbook — MCP Server Registry

## Day-2 operations

### Register a new MCP server via Bicep

Add a module invocation to `main.bicep`:

```bicep
module myNewServer 'modules/api-center/api-registration.bicep' = {
  name: 'register-my-new-server'
  params: {
    apiCenterName: apiCenterService.outputs.apiCenterName
    serverName: 'my-new-mcp-server'
    serverTitle: 'My New MCP Server'
    serverDescription: 'Provides tools for ...'
    endpointUrl: 'https://my-new-server.contoso.com'
    securityClassification: 'internal'
    mcpTransport: 'streamable-http'
    mcpProtocolVersion: '2025-06-18'
    dataClassification: ['none']
    technicalContact: 'platform@contoso.com'
  }
  dependsOn: [metadataSchemas, environment]
}
```

Open a PR. The validate workflow will show the what-if diff. Merge to deploy.

### Register a new MCP server via CLI (ad-hoc)

For quick registration outside the IaC pipeline:

```bash
# Create the API entry
az rest --method put \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/workspaces/default/apis/my-adhoc-server?api-version=2024-03-01" \
  --body '{
    "properties": {
      "title": "Ad-hoc MCP Server",
      "kind": "rest",
      "customProperties": {
        "security-classification": "internal",
        "mcp-transport": "streamable-http",
        "mcp-protocol-version": "2025-06-18",
        "data-classification": ["none"],
        "technical-contact": "platform@contoso.com"
      }
    }
  }'

# Create a version
az rest --method put \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/workspaces/default/apis/my-adhoc-server/versions/v1-0-0?api-version=2024-03-01" \
  --body '{
    "properties": {
      "title": "v1.0.0",
      "lifecycleStage": "production"
    }
  }'

# Create a deployment
az rest --method put \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/workspaces/default/apis/my-adhoc-server/deployments/development-deployment?api-version=2024-03-01" \
  --body '{
    "properties": {
      "title": "Development",
      "environmentId": "/workspaces/default/environments/development",
      "server": {
        "runtimeUri": ["https://my-adhoc-server.contoso.com"]
      },
      "state": "active"
    }
  }'
```

> **Warning:** Ad-hoc registrations will be detected as drift by the Deployment Stack. Either import them into Bicep or accept they'll be cleaned up on next deploy.

### Grant MCP client access

**For end users:**
Add them to the `sg-mcp-registry-readers` Entra ID security group. No Bicep changes needed.

**For service principals / managed identities:**

1. Get the client's managed identity principal ID:
```bash
az identity show --name <identity-name> --resource-group <rg> --query principalId -o tsv
```

2. Add the principal ID to `mcpClientPrincipalIds` in `parameters/main.bicepparam`.

3. Deploy. The role-assignments module handles the rest.

### Configure VS Code / GitHub Copilot

MCP clients point to the **APIM gateway URL**, not the API Center data plane directly.

Developers who want to browse the catalog can use the **API Center portal**: `https://<api-center-name>.portal.<region>.azure-apicenter.ms`

In VS Code `settings.json`:
```json
{
  "mcp": {
    "registries": {
      "enterprise-mcp": {
        "url": "https://<your-apim-name>.azure-api.net",
        "authentication": {
          "type": "azure",
          "audience": "https://azure-apicenter.net"
        }
      }
    }
  }
}
```

> **Note:** The `audience` remains `https://azure-apicenter.net` even though clients call the APIM gateway. APIM validates the JWT and then uses its own managed identity to call API Center.

For GitHub Copilot at the organization level, configure the MCP registry in the GitHub org settings under **Copilot → Policies → MCP**. Use the APIM gateway URL (`https://<your-apim-name>.azure-api.net`).

### Deprecate an MCP server

1. Update the version's `lifecycleStage` to `deprecated` in the Bicep registration module.
2. Add optional metadata:
```bicep
customProperties: {
  // ... existing required fields
  'deprecation-date': '2026-12-31'
  'replacement-api': 'new-server-name'
}
```
3. Deploy. Event Grid fires `ApiDefinitionUpdated` which should trigger downstream notifications.

### Delete the sample Petstore API

API Center auto-creates a `swagger-petstore` API on provisioning. Remove it:

```bash
az rest --method delete \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME/workspaces/default/apis/swagger-petstore?api-version=2024-03-01"
```

### Verify APIM proxy

After deployment or when troubleshooting, verify the APIM proxy is working end-to-end:

```bash
# 1. Check APIM provisioning state
az apim show --name $APIM_NAME --resource-group $AZURE_RESOURCE_GROUP \
  --query "provisioningState" -o tsv
# Expected: Succeeded

# 2. Verify APIM managed identity has Data Reader role
APIM_PRINCIPAL=$(az apim show --name $APIM_NAME --resource-group $AZURE_RESOURCE_GROUP \
  --query "identity.principalId" -o tsv)
echo "APIM MI principal: $APIM_PRINCIPAL"

# 3. Test the APIM gateway (requires a valid Entra token)
# NOTE: `az account get-access-token --resource https://azure-apicenter.net` does NOT work
# due to a Microsoft first-party app preauthorization gap (AADSTS65002).
# Use VS Code or GitHub Copilot to test end-to-end, or use a custom app registration
# with client credentials flow for CLI-based testing.
# See the Troubleshooting section for details on the AADSTS65002 error.

# 4. Check Application Insights for recent requests
# Use the Azure Portal → Application Insights → your Application Insights instance → Logs
```

### Disaster recovery

API Center is a regional service with no built-in geo-replication. Recovery strategy:

1. **Bicep is the source of truth.** All registrations are in code.
2. To recover, create a new resource group and deploy the stack to a new region.
3. Update the data plane URL in all MCP client configurations.
4. Re-assign RBAC roles (handled by the stack deployment).
5. Re-register the enterprise application with Entra ID (manual step or Identity Team request).
6. Re-disable anonymous access (post-deployment script).

## Post-deployment checklist

- [ ] Anonymous access disabled via REST API
- [ ] Enterprise application registered with Entra ID
- [ ] Security group created and assigned Data Reader role
- [ ] Sample `swagger-petstore` API deleted
- [ ] APIM provisioning completed (30-45 min for initial deploy)
- [ ] APIM system-assigned managed identity granted Data Reader on API Center
- [ ] APIM gateway URL responds with 200 (see "Verify APIM proxy" section)
- [ ] Application Insights receiving request telemetry from APIM
- [ ] VS Code / Copilot registry URL updated to APIM gateway and tested

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| 401 on APIM gateway | Missing/expired Entra token, or JWT validation policy rejecting claims | Verify token audience is `https://azure-apicenter.net`; check APIM policy trace for JWT error details |
| 403 on data plane (direct) | User not in security group or missing Data Reader role | Check group membership and role assignment |
| 403 on ARM operations | Missing Service Contributor | Add principal to `adminPrincipalIds` |
| 429 from APIM | Rate limit exceeded (60 req/min per user OID) | Wait for rate window to reset; increase limit in APIM policy if appropriate |
| 502 from APIM gateway | APIM cannot reach API Center backend, or MI token acquisition failed | Verify APIM MI has Data Reader role; check APIM → API Center connectivity; review APIM diagnostic logs in App Insights |
| 500 from APIM on first request | APIM still provisioning or VNet not ready | Check `az apim show` provisioningState; verify NSG rules on snet-apim allow 3443 and 6390 inbound |
| AADSTS65002 from Azure CLI | CLI app not preauthorized for API Center data plane | This is a Microsoft-side limitation; use VS Code or custom app registration instead |
| Custom metadata validation error | Schema mismatch | Verify `customProperties` match schema values exactly; `data-classification` is an array |
| Deployment Stack drift detected | Ad-hoc changes outside Bicep | Import to Bicep or let stack reconcile |
| Deployment Stack timeout | APIM initial provisioning takes 30-45 min | Re-run deployment; APIM will resume from current state. Consider increasing `--timeout` |
| Event Grid not firing | Subscription misconfigured | Verify endpoint URL and event type filter |
| API Center not available in region | Region limitation | Use a supported region (e.g. `eastus`) |
| No telemetry in Application Insights | APIM diagnostic settings misconfigured | Verify APIM logger is configured with the correct App Insights instrumentation key |
| "Sku property is null" on deploy | API Center Bicep missing `sku` property | Add `sku: { name: 'Free' }` with `#disable-next-line BCP187` to service.bicep |
| "RoleAssignmentExists" on deploy | Manual role assignment conflicts with Bicep deterministic GUID | Delete the manual assignment (`az role assignment delete --ids ...`) and redeploy |
| "Too many characters in character literal" in APIM policy | C# strings in policy XML using single quotes instead of `&quot;` | Use `&quot;` for C# string literals inside XML attribute values |
| LAW location conflict on deploy | Log Analytics workspace exists in different region than specified | Ensure `logAnalyticsLocation` matches the existing LAW region (resource group region) |
| "Name already taken" on fresh deploy | API Center or APIM name reserved after deletion | Use a different name or wait for reservation to expire; for APIM, purge soft-deleted instance first via `az rest --method delete --url ".../deletedservices/{name}?api-version=2022-08-01"` |
| `DenyAssignmentAuthorizationFailed` on post-deploy | Deployment Stack deny settings blocking API Center write | Redeploy stack with `--deny-settings-excluded-actions "Microsoft.ApiCenter/services/write"` |

## Application Insights KQL queries

Use these queries in the Azure Portal under **Application Insights → your Application Insights instance → Logs**.

### All MCP registry requests (last 24h)

```kql
requests
| where timestamp > ago(24h)
| project timestamp, name, resultCode, duration, client_IP,
    customDimensions["User-OID"]
| order by timestamp desc
```

### Failed requests (4xx/5xx)

```kql
requests
| where timestamp > ago(24h)
| where toint(resultCode) >= 400
| project timestamp, name, resultCode, duration,
    customDimensions["User-OID"], customDimensions["Error-Reason"]
| order by timestamp desc
```

### Rate-limited requests (429s)

```kql
requests
| where timestamp > ago(24h)
| where resultCode == "429"
| summarize count() by bin(timestamp, 5m), tostring(customDimensions["User-OID"])
| render timechart
```

### Request volume by user OID

```kql
requests
| where timestamp > ago(7d)
| summarize RequestCount = count() by tostring(customDimensions["User-OID"])
| order by RequestCount desc
| take 20
```

### P95 latency over time

```kql
requests
| where timestamp > ago(24h)
| summarize p95 = percentile(duration, 95) by bin(timestamp, 15m)
| render timechart
```
