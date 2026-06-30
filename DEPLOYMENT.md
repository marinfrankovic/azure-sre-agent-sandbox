# Deployment guide

End-to-end deployment of the Azure SRE Agent + Managed Grafana sandbox.

![Architecture](architecture.svg)

## Prerequisites

- Azure subscription with permission to create resource groups and role assignments (Owner, or User Access Administrator + Contributor).
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) `az`.
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) `azd` (recommended).
- A region that supports the Azure SRE Agent: **swedencentral, uksouth, eastus2, australiaeast, francecentral, canadacentral, koreacentral**.

Register the resource providers once (the preflight warns if any are missing):

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Dashboard
az provider register --namespace Microsoft.ManagedIdentity
```

## Networking & security model

There is no VNet or private endpoint. The Azure SRE Agent is a Microsoft-managed service with **no VNet injection**, so it can only reach Grafana over the **public endpoint**. That endpoint is hardened so the public surface is an authentication boundary, not an open door:

| Control | Setting |
| --- | --- |
| Grafana public network access | `Enabled` (required for the managed agent to connect) |
| Grafana authentication | Entra ID — required for every request |
| Grafana API keys | `Disabled` |
| Anonymous access | Off |
| Agent → Grafana | Managed identity + **Grafana Viewer** (read-only) |

> A private endpoint would block the agent and is therefore intentionally omitted. If you later need network-level isolation, you would need an agent connectivity model that supports private reach — not available today.

## Option A — azd (recommended)

```bash
azd auth login
azd env new sreagent-sbx
azd env set AZURE_LOCATION swedencentral
azd up
```

What happens:
1. **preprovision** → `scripts/preflight-region` validates region + providers.
2. **provision** → `infra/main.bicep` creates the RG, identity, Grafana, SRE Agent, and RBAC.
3. **postprovision** → `scripts/show-access` prints the access summary.

## Option B — az CLI

```bash
az deployment sub create \
  --name sre-sandbox \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral
```

Grant yourself agent access during deployment:

```bash
  --parameters agentAccessPrincipalId=$(az ad signed-in-user show --query id -o tsv)
```

## Parameters

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `environmentName` | yes | — | Deterministic resource naming |
| `location` | yes | — | SRE Agent-supported region |
| `resourceGroupName` | no | `rg-<environmentName>-sre` | Override RG name |
| `tags` | no | `{}` | Tags on every resource |
| `agentAccessPrincipalId` | no | `` | Principal granted SRE Agent Standard User |
| `agentAccessPrincipalType` | no | `User` | `User`, `Group`, or `ServicePrincipal` |

## Outputs

| Output | Description |
| --- | --- |
| `AZURE_RESOURCE_GROUP` | Resource group name |
| `AZURE_GRAFANA_ENDPOINT` | Grafana URL |
| `AZURE_GRAFANA_MCP_ENDPOINT` | Grafana MCP endpoint (`…/api/azure-mcp`) |
| `AZURE_SRE_AGENT_ID` / `AZURE_SRE_AGENT_NAME` | SRE Agent identifiers |
| `AZURE_USER_ASSIGNED_IDENTITY_*` | Managed identity IDs |

## Validate the template locally

```bash
az bicep build --file infra/main.bicep --stdout > $null
```

## Connecting the agent to Grafana (MCP)

The agent reaches Grafana at `<AZURE_GRAFANA_ENDPOINT>/api/azure-mcp` using its managed identity (already granted **Grafana Viewer**). No networking setup is required — Grafana's public, Entra-protected endpoint is directly reachable by the Microsoft-managed agent.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Preflight fails on region | Region not supported | Pick a supported region |
| Agent can't connect to Grafana | Missing role / propagation delay | Confirm the agent identity has **Grafana Viewer**; allow 5–10 min for RBAC to propagate |
| Can't open Grafana UI | Not signed in to Entra / no Grafana role | Sign in with an account that has a Grafana role in this instance |
| Can't use the agent | Missing data-plane role | Grant SRE Agent Reader+ on the agent (Owner is not enough) |
| Access just granted but blocked | RBAC propagation | Wait 5–10 min; confirm account/tenant |
| Grafana shows no data | No data sources added | Add your data sources (restore from backup) |

## Clean up

```bash
azd down --purge --force
# or
az group delete --name <resource-group> --yes --no-wait
```
