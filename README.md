# Azure SRE Agent + Managed Grafana sandbox

A minimal, deploy-and-go sandbox for evaluating the **Azure SRE Agent** together with **Azure Managed Grafana**. The agent investigates incidents by querying Grafana through Grafana's MCP endpoint, so the only services this template provisions are the agent, its identity, and Grafana.

**Bring your own observability data.** This template does *not* stand up Prometheus, Loki, Tempo, or any data store. You add your data sources to Grafana yourself — typically by restoring them from backup — and the SRE Agent reaches that data through Grafana.

![Architecture](architecture.svg)

## What gets deployed

| Resource | Type | Purpose |
| --- | --- | --- |
| Resource group | `Microsoft.Resources/resourceGroups` | Sandbox boundary |
| User-assigned managed identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | Workload identity for the SRE Agent |
| Azure SRE Agent | `Microsoft.App/agents` | The AI SRE that investigates incidents |
| Azure Managed Grafana | `Microsoft.Dashboard/grafana` | Dashboards + MCP endpoint the agent queries |

Everything else (Prometheus/Loki/Tempo, storage, logs) is **yours to bring**.

## Least-privilege access

The deployment grants only what the agent needs:

| Principal | Role | Scope |
| --- | --- | --- |
| Agent identity | Reader | Resource group |
| Agent identity | Grafana Viewer | Grafana |
| You (deployer) | SRE Agent Standard User | SRE Agent |

The deployer assignment is driven by the `agentAccessPrincipalId` parameter. With `azd` it defaults to the signed-in user.

## Cost & time

- **Cost:** roughly **~$2/day** — effectively just the Managed Grafana Standard instance. The SRE Agent, managed identity, and resource group have no standing charge.
- **Deployment time:** about **5–10 minutes**. There is no Azure Data Explorer cluster to provision, which is what made earlier versions slow.

## Supported regions

The Azure SRE Agent is available in: **swedencentral, uksouth, eastus2, australiaeast, francecentral, canadacentral, koreacentral**. The `preprovision` hook (`scripts/preflight-region`) validates your region before anything is deployed.

## Deploy

### With azd (recommended)

```bash
azd auth login
azd env new sreagent-sbx
azd env set AZURE_LOCATION swedencentral
azd up
```

`azd up` runs the region preflight, provisions the stack, and prints an access summary.

### With az CLI

```bash
az deployment sub create \
  --name sre-sandbox \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full walkthrough and [post-setup.md](post-setup.md) for what to do after deploying.

## Granting access to the SRE Agent

> **Subscription Owner is NOT enough to *use* the agent.** Using the agent requires a data-plane role on the agent resource itself.

If you didn't pass `agentAccessPrincipalId`, grant yourself access:

```bash
az role assignment create \
  --assignee <your-object-id> \
  --role "SRE Agent Standard User" \
  --scope <AZURE_SRE_AGENT_ID>
```

Roles, lowest to highest: **SRE Agent Reader → Standard User → Author → Administrator**.

Notes:
- Role assignments can take **5–10 minutes** to propagate.
- Sign in to <https://sre.azure.com> with the **same account and tenant** that holds the role.

## Clean up

```bash
azd down --purge --force
# or
az group delete --name <resource-group> --yes --no-wait
```

## Repository layout

```
infra/
  main.bicep              Subscription-scoped entry point
  main.parameters.json    azd parameter mapping
  abbreviations.json      Resource name prefixes
  modules/
    identity.bicep        User-assigned managed identity
    grafana.bicep         Azure Managed Grafana
    sreAgent.bicep        Azure SRE Agent + access role
    rbac.bicep            Least-privilege role assignments
scripts/
  preflight-region.*      Region/provider preflight (azd preprovision)
  show-access.*           Access summary (azd postprovision)
azure.yaml                azd project + hooks
architecture.svg          Architecture diagram
```
