# Security

## Reporting vulnerabilities

If you discover a security vulnerability in this project, please report it through [GitHub Security Advisories](../../security/advisories/new). Do not open a public issue.

## Security considerations for deployers

This repository is Infrastructure as Code — it deploys Azure resources but does not contain runtime secrets. However:

- **Parameter files contain sensitive values.** Your `.bicepparam` file will contain tenant IDs, security group object IDs, and email addresses. The `.gitignore` excludes `*.bicepparam` files (only `*.bicepparam.example` is tracked). Never commit your real parameter file.
- **Entra ID is the sole authentication mechanism.** API Center does not support API keys, IP firewalls, or private endpoints. All access control is identity-based via Entra ID RBAC and Conditional Access policies.
- **APIM enforces security group membership.** The APIM policy validates that callers have a valid Entra ID JWT with an `oid` claim and belong to the configured security group (via the `groups` claim). This requires the Entra ID app registration to be configured to emit group claims in the token (Token configuration → Add groups claim). Group-based access control is additionally enforced at the API Center RBAC level (Data Reader role assigned to the security group).
- **Anonymous access must be explicitly disabled.** API Center enables anonymous access by default. The post-deployment step to disable it is required — see the runbook.
- **The APIM-to-API-Center connection is public.** Even with APIM in External VNet mode, the backend call from APIM to the API Center data plane traverses the public internet. API Center does not support private endpoints.
