# Architecture — Azure API Center MCP Server Registry

## Solution overview

Azure API Center serves as a **centralized MCP server registry** implementing the MCP Registry v0.1 specification. The registry is an **enterprise allowlist for GitHub Copilot MCP servers** — controlling which MCP servers are available to developers, starting with public-information servers (Microsoft Learn, Context7) and scaling to credential-bearing servers (GitHub) and custom enterprise servers.

There are two key concepts to understand:

1. **Discovery** — MCP clients query the registry to find out which servers exist and where they live. This is what the registry provides.
2. **Runtime** — MCP clients connect directly to each server for tool invocation. The registry is not in the runtime path.

API Center handles discovery and governance. The MCP servers themselves run independently (Container Apps, Functions, VMs, external SaaS, etc.) and are not proxied through API Center.

## Architecture comparison

This project supports two deployment topologies. The current deployment uses the full architecture with APIM.

### Simplified architecture (API Center direct)

The minimum viable deployment for an MCP registry. MCP clients authenticate directly to the API Center data plane using Entra ID tokens. Suitable when logging, rate limiting, and VNet integration are not required.

```mermaid
graph TB
    subgraph "MCP Clients"
        VSC[VS Code / GitHub Copilot]
        CA[Custom AI Agents]
    end

    subgraph "Identity"
        EID[Entra ID]
        SG[Security Group<br/>sg-mcp-registry-readers]
    end

    subgraph "Azure API Center"
        APIC[API Center Data Plane<br/>public endpoint]
        WS[Default Workspace]
        META[Metadata Schemas]
        ENV[Environments]

        APIC --> WS
        WS --> META
        WS --> ENV
    end

    subgraph "MCP Servers"
        LEARN[Microsoft Learn MCP]
        CTX7[Context7 MCP]
        GH[GitHub MCP Server]
    end

    VSC -->|"1. Authenticate"| EID
    EID -->|"JWT (audience:<br/>https://azure-apicenter.net)"| VSC
    VSC -->|"2. Discover servers"| APIC
    SG -->|"Data Reader role<br/>gates access"| APIC

    VSC -->|"3. Connect directly"| LEARN
    VSC -->|"3. Connect directly"| CTX7
    VSC -->|"3. Connect directly"| GH

    style APIC fill:#2d6a4f,color:#fff
```

**What you get:** Entra ID authentication, security group gating, governance metadata enforcement.

**What you don't get:** Request logging, per-user rate limiting, VNet integration, observability into who queried the registry.

### Full architecture with APIM proxy (current deployment)

Azure API Management (Developer tier, External VNet mode) sits in front of the API Center data plane, adding per-user rate limiting, request logging to Application Insights, VNet integration, and a hybrid auth pattern where APIM validates the user's identity but uses its own managed identity to call the backend.

```mermaid
graph TB
    subgraph "MCP Clients"
        VSC[VS Code / GitHub Copilot]
        AIF[Azure AI Foundry]
        CA[Custom AI Agents]
    end

    subgraph "Identity & Access"
        EID[Entra ID]
        SG[Security Group<br/>sg-mcp-registry-readers]
        CAP[Conditional Access Policies]
    end

    subgraph "APIM Proxy Layer"
        APIM[API Management<br/>Developer tier, External VNet]
        VNET[VNet: {name}-vnet<br/>Subnet: snet-apim 10.0.0.0/24]
        APIM --- VNET
    end

    subgraph "Azure API Center — MCP Registry"
        APIC[API Center Service<br/>backend, not client-facing]
        WS[Default Workspace]
        META[Metadata Schemas<br/>governance enforcement]
        ENV[Environments<br/>development]

        APIC --> WS
        WS --> META
        WS --> ENV
    end

    subgraph "MCP Servers (runtime)"
        LEARN[Microsoft Learn MCP]
        CTX7[Context7 MCP]
        GH[GitHub MCP Server]
        CUSTOM[Custom Enterprise MCP Servers]
    end

    subgraph "Observability"
        APPI[Application Insights<br/>request/response logging]
        AL[Activity Log]
        EG[Event Grid]
    end

    VSC -->|"1. Discover servers<br/>(Entra ID token)"| APIM
    AIF -->|"1. Discover servers<br/>(Entra ID token)"| APIM
    CA -->|"1. Discover servers<br/>(managed identity token)"| APIM

    APIM -->|"Validate JWT, rate limit<br/>then forward with MI token"| APIC

    SG -->|"Members authenticate<br/>via Entra ID"| APIM
    EID -->|"Bearer token"| APIM
    CAP -->|"Enforce device/location"| EID

    VSC -->|"2. Connect directly<br/>(tools/list, tools/call)"| LEARN
    VSC -->|"2. Connect directly"| CTX7
    VSC -->|"2. Connect directly<br/>(user OAuth)"| GH
    CA -->|"2. Connect directly"| CUSTOM

    APIM -->|"Request telemetry"| APPI
    APIC -->|"ARM audit"| AL
    APIC -->|"Registration events"| EG
```

**What APIM adds over the simplified architecture:**

| Capability | Simplified (direct) | Full (APIM proxy) |
|---|---|---|
| Authentication | User JWT validated by API Center | User JWT validated by APIM, MI token used for backend |
| Rate limiting | None (undocumented platform limits only) | 60 req/min per user OID |
| Request logging | None (API Center has no diagnostic settings) | All requests logged to Application Insights with user OID |
| VNet integration | None (API Center has no network controls) | APIM in dedicated subnet with NSG |
| Latency | Single hop | Additional hop through APIM (~10-50ms) |
| Cost | Free (API Center only) | ~$50/month (Developer tier APIM) |

## End-to-end sequence: developer discovers and uses MCP servers

This diagram shows the complete flow from a developer's workstation through registry discovery to MCP server tool invocation.

```mermaid
sequenceDiagram
    participant Dev as Developer Workstation<br/>(VS Code + Copilot)
    participant EID as Entra ID
    participant APIM as APIM Gateway
    participant APIC as API Center<br/>Data Plane
    participant APPI as Application Insights
    participant MCP1 as Context7 MCP Server<br/>(public, no auth)
    participant MCP2 as GitHub MCP Server<br/>(user OAuth)

    Note over Dev,MCP2: Phase 1 — Discover available MCP servers

    Dev->>EID: Sign in with corporate Entra ID account
    EID->>EID: Verify credentials + Conditional Access
    EID-->>Dev: Access token (JWT)<br/>aud: https://azure-apicenter.net<br/>oid: user-object-id

    Dev->>APIM: GET /workspaces/default/v0.1/servers<br/>Authorization: Bearer {user JWT}

    APIM->>APIM: validate-jwt: verify signature,<br/>check aud=https://azure-apicenter.net,<br/>require oid claim

    APIM->>APIM: rate-limit-by-key:<br/>check 60 req/min for this OID

    APIM->>EID: authentication-managed-identity:<br/>request token for https://azure-apicenter.net<br/>(APIM system-assigned MI)
    EID-->>APIM: MI token

    APIM->>APIC: GET /workspaces/default/v0.1/servers<br/>Authorization: Bearer {MI token}
    APIC->>APIC: Validate MI has Data Reader role
    APIC-->>APIM: JSON: list of MCP servers<br/>[{name, endpoint, metadata}, ...]

    APIM->>APPI: Log: user OID, 200, latency, path
    APIM-->>Dev: MCP server list

    Note over Dev,MCP2: Phase 2 — Connect to MCP servers (registry not involved)

    Dev->>MCP1: POST https://context7.com/mcp<br/>{"method": "tools/list"}
    Note over Dev,MCP1: Context7 is public — no auth needed
    MCP1-->>Dev: Available tools:<br/>[resolve-library-id, get-library-docs]

    Dev->>MCP1: POST https://context7.com/mcp<br/>{"method": "tools/call",<br/>"params": {"name": "get-library-docs", ...}}
    MCP1-->>Dev: Library documentation content

    Note over Dev,MCP2: GitHub MCP requires the developer's<br/>own GitHub OAuth token (not Entra ID)
    Dev->>MCP2: POST https://api.github.com/mcp<br/>Authorization: Bearer {github token}<br/>{"method": "tools/list"}
    MCP2-->>Dev: Available tools:<br/>[search-repos, get-file-contents, create-issue, ...]

    Dev->>MCP2: POST https://api.github.com/mcp<br/>{"method": "tools/call",<br/>"params": {"name": "get-file-contents", ...}}
    MCP2-->>Dev: File contents from user's repos
```

Key points illustrated above:

- **The registry is only involved in Phase 1 (discovery).** Once the client has the server list, it connects directly to each MCP server.
- **Each MCP server handles its own authentication.** Public servers like Context7 need no auth. Credential-bearing servers like GitHub use the developer's own OAuth tokens. The registry does not broker or proxy these connections.
- **APIM sees who queried the registry but not what happens after.** The runtime traffic between the developer and MCP servers is invisible to the registry infrastructure.

## Simplified sequence: direct API Center access (no APIM)

For comparison, this is how the flow works without the APIM proxy layer — clients talk directly to the API Center data plane.

```mermaid
sequenceDiagram
    participant Dev as Developer Workstation<br/>(VS Code + Copilot)
    participant EID as Entra ID
    participant APIC as API Center<br/>Data Plane (direct)
    participant MCP as MCP Server

    Dev->>EID: Sign in with corporate account
    EID-->>Dev: Access token (JWT)<br/>aud: https://azure-apicenter.net

    Dev->>APIC: GET /workspaces/default/v0.1/servers<br/>Authorization: Bearer {user JWT}
    APIC->>APIC: Validate JWT + Data Reader role<br/>(user must be in security group)
    APIC-->>Dev: MCP server list

    Note over Dev,MCP: No logging of who queried.<br/>No rate limiting.<br/>No VNet controls.

    Dev->>MCP: Connect directly to MCP server
    MCP-->>Dev: Tool results
```

This works but provides no observability. You cannot answer "who queried the registry last week?" or "is anyone hitting it excessively?" — which is why the APIM proxy was added.

## Data model mapping

```mermaid
erDiagram
    API_CENTER_SERVICE ||--|| WORKSPACE : "contains (default only)"
    WORKSPACE ||--|{ ENVIRONMENT : "defines"
    WORKSPACE ||--|{ API : "registers"
    API ||--|{ VERSION : "has"
    API ||--|{ DEPLOYMENT : "deployed to"
    VERSION ||--|{ DEFINITION : "documented by"
    DEPLOYMENT }|--|| ENVIRONMENT : "targets"
    API_CENTER_SERVICE ||--|{ METADATA_SCHEMA : "enforces"

    API {
        string name "kebab-case identifier"
        string title "Display name"
        string kind "rest (GA) / MCP (portal)"
        object customProperties "Governance metadata"
        array contacts "Owner team contact"
    }

    VERSION {
        string title "Semantic version"
        string lifecycleStage "design / development / testing / preview / production / deprecated / retired"
    }

    DEFINITION {
        string title "Spec title"
        string specification_name "openapi / asyncapi"
        string specification_version "3.0 / 2.0"
    }

    DEPLOYMENT {
        string title "Deployment name"
        string environmentId "Target environment path"
        array runtimeUri "MCP server endpoint URLs"
        string state "active / inactive"
    }

    ENVIRONMENT {
        string title "Environment name"
        string kind "development / staging / production"
    }

    METADATA_SCHEMA {
        string name "Schema identifier"
        string schema "JSON Schema (stringified)"
        array assignedTo "api / environment / deployment"
        boolean required "Enforced at registration"
    }
```

## RBAC model

```mermaid
graph LR
    subgraph "Principals"
        SG[Security Group<br/>sg-mcp-registry-readers]
        APIMMI[APIM System MI]
        CICD[CI/CD Pipeline<br/>Service Principal]
        AUDIT[Governance Team<br/>User/Group]
    end

    subgraph "API Center RBAC Roles"
        READER[Data Reader<br/>c7244dfb-...]
        CONTRIB[Service Contributor<br/>dd24193f-...]
        COMPLIANCE[Compliance Manager<br/>ede9aaa3-...]
    end

    subgraph "Capabilities"
        DISCOVER[Discover servers via<br/>data plane API]
        PROXY[Proxy discovery requests<br/>from MCP clients via APIM]
        REG[Register / update<br/>MCP servers via ARM]
        LINT[View linting results<br/>+ update analysis state]
    end

    SG -->|assigned| READER
    APIMMI -->|assigned| READER
    CICD -->|assigned| CONTRIB
    AUDIT -->|assigned| COMPLIANCE

    READER --> DISCOVER
    APIMMI --> PROXY
    CONTRIB --> REG
    COMPLIANCE --> LINT
```

## Network access model

```mermaid
graph TB
    subgraph "Public Clients"
        VSC[VS Code<br/>Developer Workstation]
        COPILOT[GitHub Copilot]
    end

    subgraph "Corporate Network / VNet"
        AGENT[AI Agent<br/>in VNet]
    end

    subgraph "Azure — APIM VNet (snet-apim 10.0.0.0/24)"
        APIM[API Management<br/>Developer tier, External VNet]
        NSG[NSG: 443 client HTTPS,<br/>3443 APIM mgmt, 6390 ALB inbound]
        APIM --- NSG
    end

    subgraph "Azure — API Center"
        APIC[API Center Data Plane<br/>public endpoint, not client-facing]
    end

    subgraph "Identity"
        EID[Entra ID + Conditional Access]
    end

    subgraph "Observability"
        APPI[Application Insights]
    end

    VSC -->|"Entra token<br/>+ Conditional Access"| APIM
    COPILOT -->|"Entra token"| APIM
    AGENT -->|"VNet peering or<br/>private DNS possible"| APIM

    APIM -->|"MI token<br/>(system-assigned)"| APIC
    APIM -->|"Request telemetry"| APPI

    EID -->|"Validates user JWTs"| APIM
    EID -->|"Issues MI tokens"| APIM

    style APIM fill:#264653,color:#fff
    style APIC fill:#2d6a4f,color:#fff
```

## CI/CD pipeline flow

```mermaid
graph LR
    subgraph "PR Opened"
        LINT[Bicep Lint]
        VAL[Validate]
        WIF[What-If]
        COMMENT[PR Comment<br/>with diff]
    end

    subgraph "Merge to main"
        LOGIN[OIDC Login]
        STACK[Deploy via<br/>Deployment Stack]
        ANON[Disable anonymous<br/>access post-deploy]
    end

    LINT --> VAL --> WIF --> COMMENT
    LOGIN --> STACK --> ANON

    COMMENT -.->|"approval gate"| LOGIN

    style STACK fill:#2d6a4f,color:#fff
    style COMMENT fill:#264653,color:#fff
```

> **Note:** Initial deployments that include APIM provisioning take 30-45 minutes. The Deployment Stack timeout may need to be increased. Subsequent updates to existing APIM instances are much faster.

## Governance enforcement

```mermaid
graph TB
    subgraph "Registration Time"
        REG[New MCP Server Registration]
        META{Required metadata<br/>provided?}
        REJECT[Registration fails]
        ACCEPT[Server registered]
    end

    subgraph "Post-Registration"
        EG[Event Grid:<br/>ApiDefinitionAdded]
        LINT[Spectral Linting<br/>API Analysis]
        REPORT[Compliance Dashboard]
        NOTIFY[Teams/Slack<br/>Notification]
    end

    subgraph "Required Metadata"
        SEC[security-classification]
        TRANS[mcp-transport]
        PROTO[mcp-protocol-version]
        DATA[data-classification]
        TECH[technical-contact]
    end

    REG --> META
    META -->|"No"| REJECT
    META -->|"Yes"| ACCEPT

    SEC --> META
    TRANS --> META
    PROTO --> META
    DATA --> META
    TECH --> META

    ACCEPT --> EG
    EG --> LINT
    EG --> NOTIFY
    LINT --> REPORT
```
