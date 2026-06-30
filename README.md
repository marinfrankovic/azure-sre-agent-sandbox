# Azure SRE Agent Sandbox (azd)

Isolated, single-subscription Azure SRE Agent sandbox for importing historical
observability data and connecting the agent to Azure Managed Grafana via MCP.

![Architecture](architecture.svg)

## Prerequisites

- Azure CLI 2.x+
- Azure Developer CLI (azd)
- Bicep CLI
- Subscription `Owner`, or `Contributor` + `User Access Administrator`

## Deploy

```bash
cp .env.example .env        # set AZURE_SUBSCRIPTION_ID, AZURE_ENV_NAME, AZURE_LOCATION, AZURE_TAGS
azd auth login
azd env new $AZURE_ENV_NAME
azd env set AZURE_LOCATION <region>
azd up
```

Or with Azure CLI:

```bash
az deployment sub create \
  --name sre-agent-sandbox \
  --location <region> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

## Resources

Resource Group · User-Assigned Managed Identity · Log Analytics Workspace ·
Application Insights · Azure Monitor Workspace (Managed Prometheus) ·
Data Collection Endpoint · Data Collection Rule · Storage Account (6 containers) ·
Key Vault · Azure Data Explorer cluster + `sreagent` database ·
Azure Managed Grafana · Azure SRE Agent.

## Key outputs

- `AZURE_GRAFANA_ENDPOINT`
- `AZURE_GRAFANA_MCP_ENDPOINT` (`<grafana-endpoint>/api/azure-mcp`)
- `AZURE_USER_ASSIGNED_IDENTITY_ID` / `_CLIENT_ID` / `_PRINCIPAL_ID`
- `AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT`
- `AZURE_DATA_EXPLORER_CLUSTER_URI`
- `AZURE_SRE_AGENT_ID`
