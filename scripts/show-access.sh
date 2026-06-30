#!/usr/bin/env bash
# Prints the access summary (URLs, endpoints, IDs) needed for post-deployment
# configuration of the Azure SRE Agent sandbox. Runs as an azd 'postprovision'
# hook (outputs are exposed as environment variables) or manually with a
# deployment name: scripts/show-access.sh [deploymentName]
set -euo pipefail

DEPLOYMENT_NAME="${1:-}"

get_output() {
  local name="$1"
  local val="${!name:-}"
  if [ -z "$val" ] && [ -n "${OUTPUTS_JSON:-}" ]; then
    val="$(echo "$OUTPUTS_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$name',{}).get('value',''))" 2>/dev/null || true)"
  fi
  echo "$val"
}

OUTPUTS_JSON=""
if [ -n "$DEPLOYMENT_NAME" ]; then
  OUTPUTS_JSON="$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json 2>/dev/null || true)"
fi

echo ""
echo "=============================================================================="
echo "  Azure SRE Agent sandbox — deployment complete. Access & post-config details"
echo "=============================================================================="
echo ""
echo "Resource group : $(get_output AZURE_RESOURCE_GROUP)   ($(get_output AZURE_LOCATION))"
echo ""
echo "ACCESS URLs"
echo "  Grafana UI                : $(get_output AZURE_GRAFANA_ENDPOINT)"
echo "  Grafana MCP endpoint      : $(get_output AZURE_GRAFANA_MCP_ENDPOINT)"
echo "  Prometheus query endpoint : $(get_output AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT)"
echo "  Data Explorer cluster URI : $(get_output AZURE_DATA_EXPLORER_CLUSTER_URI)   (database: $(get_output AZURE_DATA_EXPLORER_DATABASE_NAME))"
echo "  Storage blob endpoint     : $(get_output AZURE_STORAGE_BLOB_ENDPOINT)   (account: $(get_output AZURE_STORAGE_ACCOUNT_NAME))"
echo "  Key Vault URI             : $(get_output AZURE_KEY_VAULT_URI)   (name: $(get_output AZURE_KEY_VAULT_NAME))"
echo ""
echo "AZURE SRE AGENT"
echo "  Name : $(get_output AZURE_SRE_AGENT_NAME)"
echo "  Id   : $(get_output AZURE_SRE_AGENT_ID)"
echo ""
echo "WORKLOAD IDENTITY (used for agent RBAC / Grafana MCP auth)"
echo "  Resource ID  : $(get_output AZURE_USER_ASSIGNED_IDENTITY_ID)"
echo "  Client ID    : $(get_output AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID)"
echo "  Principal ID : $(get_output AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID)"
echo ""
echo "APP INSIGHTS"
echo "  Connection string : $(get_output AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING)"
echo ""
echo "NEXT STEPS"
echo "  1. Open Grafana and confirm the Azure Monitor / Prometheus data source."
echo "  2. Register the Grafana MCP endpoint on the SRE Agent (managed-identity auth)."
echo "  3. Import historical data into the storage containers / Data Explorer."
echo "  See post-setup.md for the full post-deployment guide."
echo "=============================================================================="
