#!/usr/bin/env bash
set -euo pipefail

# Post-deployment script: Disable anonymous access on API Center
# API Center enables anonymous access by default and the Bicep schema
# does not expose this toggle. This script must run after every deployment.

# These can be set as environment variables or GitHub Actions variables
: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID must be set}"
: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP must be set}"
: "${API_CENTER_NAME:?API_CENTER_NAME must be set}"

echo "Disabling anonymous access on API Center: $API_CENTER_NAME"

az rest --method patch \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiCenter/services/$API_CENTER_NAME?api-version=2024-03-01" \
  --body '{"properties":{"anonymousAccess":"disabled"}}'

# Note: We rely on the PATCH exit code (set -e) rather than a GET verification.
# The API Center GET response on api-version 2024-03-01 does not surface the
# anonymousAccess property, so a read-back check would always fail.
echo "Anonymous access disabled successfully (PATCH returned HTTP 2xx)."
