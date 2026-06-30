#!/usr/bin/env bash
# Prints a connection summary after deployment (azd 'postprovision' hook).
set -uo pipefail

azd_value() {
  local v
  v="$(azd env get-value "$1" 2>/dev/null || true)"
  [ -n "$v" ] && echo "$v" || echo ""
}

RG="$(azd_value AZURE_RESOURCE_GROUP)"
GRAFANA_URL="$(azd_value AZURE_GRAFANA_ENDPOINT)"
GRAFANA_MCP="$(azd_value AZURE_GRAFANA_MCP_ENDPOINT)"
AGENT_NAME="$(azd_value AZURE_SRE_AGENT_NAME)"
AGENT_ID="$(azd_value AZURE_SRE_AGENT_ID)"
MI_ID="$(azd_value AZURE_USER_ASSIGNED_IDENTITY_ID)"
MI_CLIENT="$(azd_value AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID)"

echo ""
echo "==================== SANDBOX ACCESS SUMMARY ===================="
echo "Resource group     : $RG"
echo ""
echo "Managed Grafana"
echo "  URL              : $GRAFANA_URL"
echo "  MCP endpoint     : $GRAFANA_MCP"
echo ""
echo "Azure SRE Agent"
echo "  Name             : $AGENT_NAME"
echo "  Resource ID      : $AGENT_ID"
echo "  Console          : https://sre.azure.com"
echo ""
echo "Managed identity (agent workload identity)"
echo "  Resource ID      : $MI_ID"
echo "  Client ID        : $MI_CLIENT"
echo ""
echo "Next steps"
echo "  1. In Grafana, add your data sources (Prometheus/Loki/Tempo) restored from backup."
echo "  2. Open https://sre.azure.com and select agent '$AGENT_NAME'."
echo "  3. To USE the agent, you need SRE Agent Reader (or higher) on the agent —"
echo "     subscription Owner is NOT sufficient. See README 'Granting access'."
echo "==============================================================="
