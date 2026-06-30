# Deployment guide

End-to-end deployment of the Azure SRE Agent + Managed Grafana sandbox.

![Architecture](architecture.svg)

## Prerequisites

- Azure subscription with permission to create resource groups and role assignments (Owner or User Access Administrator + Contributor).
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) `az`.
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) `azd` (recommended).
- A region that supports the Azure SRE Agent: **swedencentral, uksouth, eastus2, australiaeast, francecentral, canadacentral, koreacentral**.

Register the resource providers once (the preflight will warn if any are missing):

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Dashboard
az provider register --namespace Microsoft.ManagedIdentity
```

## Option A — azd (recommended)

```bash
azd auth login

# Create an environment
azd env new sreagent-sbx
azd env set AZURE_LOCATION swedencentral
# optional overrides
# azd env set AZURE_RESOURCE_GROUP rg-sreagent-sbx

# Provision (runs preflight, deploys, prints access summary)
azd up
```

What happens:
1. **preprovision** → `scripts/preflight-region` validates the region and provider registration.
2. **provision** → `infra/main.bicep` creates the resource group, identity, Grafana, SRE Agent, and role assignments.
3. **postprovision** → `scripts/show-access` prints the Grafana URL, MCP endpoint, and agent details.

## Option B — az CLI

```bash
az deployment sub create \
  --name sre-sandbox \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral
```

To also grant yourself agent access during deployment, pass your object ID:

```bash
  --parameters agentAccessPrincipalId=$(az ad signed-in-user show --query id -o tsv)
```

## Parameters

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `environmentName` | yes | — | Used for deterministic resource naming |
| `location` | yes | — | SRE Agent-supported region |
| `resourceGroupName` | no | `rg-<environmentName>-sre` | Override the resource group name |
| `tags` | no | `{}` | Tags applied to every resource |
| `agentAccessPrincipalId` | no | `` | Principal granted SRE Agent Standard User |
| `agentAccessPrincipalType` | no | `User` | `User`, `Group`, or `ServicePrincipal` |

## Outputs

| Output | Description |
| --- | --- |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `AZURE_GRAFANA_ENDPOINT` | Grafana URL |
| `AZURE_GRAFANA_MCP_ENDPOINT` | Grafana MCP endpoint (`…/api/azure-mcp`) |
| `AZURE_SRE_AGENT_ID` / `AZURE_SRE_AGENT_NAME` | SRE Agent identifiers |
| `AZURE_USER_ASSIGNED_IDENTITY_ID` / `_CLIENT_ID` / `_PRINCIPAL_ID` | Managed identity |

## Validate the template locally

```bash
az bicep build --file infra/main.bicep --stdout > $null
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Preflight fails on region | Region not supported | Pick a supported region |
| Can't open / use the agent | Missing data-plane role | Grant SRE Agent Reader+ on the agent (Owner is not enough) |
| Access just granted but still blocked | RBAC propagation | Wait 5–10 min; confirm correct account/tenant |
| Grafana shows no data | No data sources added | Add your data sources (restore from backup) |

## Clean up

```bash
azd down --purge --force
# or
az group delete --name <resource-group> --yes --no-wait
```
