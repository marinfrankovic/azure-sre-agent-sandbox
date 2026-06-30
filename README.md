# Azure SRE Agent + Managed Grafana sandbox (private-by-default)

A deploy-and-go sandbox for evaluating the **Azure SRE Agent** with **Azure Managed Grafana**, hardened with **private endpoints** for everything that supports Private Link. The agent investigates incidents by querying Grafana through Grafana's MCP endpoint, so the only services this template provisions are the agent, its identity, Grafana, and the network resources that make Grafana private.

**Bring your own observability data.** This template does *not* stand up Prometheus, Loki, Tempo, or any data store. You add your data sources to Grafana yourself — typically by restoring them from backup — and the SRE Agent reaches that data through Grafana.

![Architecture](architecture.svg)

## What gets deployed

| Resource | Type | Private Link? | Purpose |
| --- | --- | --- | --- |
| Resource group | `Microsoft.Resources/resourceGroups` | n/a | Sandbox boundary |
| User-assigned managed identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | not supported | Workload identity for the SRE Agent |
| Azure SRE Agent | `Microsoft.App/agents` | not supported | The AI SRE that investigates incidents |
| Azure Managed Grafana | `Microsoft.Dashboard/grafana` | **yes** | Dashboards + MCP endpoint the agent queries |
| Virtual network + subnet | `Microsoft.Network/virtualNetworks` | n/a | Hosts the private endpoint |
| Private DNS zone | `privatelink.grafana.azure.com` | n/a | Resolves Grafana to its private IP |
| Private endpoint | `Microsoft.Network/privateEndpoints` | — | Private Link access to Grafana |

> **Why only Grafana gets a private endpoint:** in this minimal stack, Grafana is the only resource that supports Private Link. The managed identity and the SRE Agent (`Microsoft.App/agents`) are control-plane resources with no private-endpoint support. Everything else (Prometheus/Loki/Tempo, storage, logs) is **yours to bring** — secure those data sources on your own network and connect them to Grafana.

## Private networking

Controlled by two parameters:

| Parameter | Default | Effect |
| --- | --- | --- |
| `enablePrivateNetworking` | `true` | Deploy VNet, Private DNS zone, and a Grafana private endpoint |
| `grafanaPublicNetworkAccess` | `Disabled` | With private networking on, `Disabled` = private-endpoint-only; `Enabled` = keep public access **and** add a private endpoint |

> ⚠️ **Important — SRE Agent reachability.** The Azure SRE Agent is a Microsoft-managed service and (today) has no VNet injection. If it **cannot reach a fully private Grafana**, the MCP connection will fail. Two options:
> - Keep `grafanaPublicNetworkAccess = Disabled` (most secure) and validate that the agent can connect. Reach Grafana yourself from inside the VNet (Bastion / jumpbox / VPN).
> - If the agent can't connect privately, redeploy with `grafanaPublicNetworkAccess = Enabled` — a private endpoint is still created for admins and data paths, while the agent uses the public endpoint (Entra ID + RBAC protected).
>
> Validate this with your tenant before committing to a fully private posture.

## Least-privilege access

| Principal | Role | Scope |
| --- | --- | --- |
| Agent identity | Reader | Resource group |
| Agent identity | Grafana Viewer | Grafana |
| You (deployer) | SRE Agent Standard User | SRE Agent |

The deployer assignment is driven by `agentAccessPrincipalId` (defaults to the signed-in user with `azd`).

## Cost & time

- **Cost:** roughly **~$2/day** — Managed Grafana Standard. The VNet, Private DNS zone, and private endpoint add a few cents/day; the agent, identity, and RG have no standing charge.
- **Deployment time:** about **5–10 minutes**.

## Supported regions

The Azure SRE Agent is available in: **swedencentral, uksouth, eastus2, australiaeast, francecentral, canadacentral, koreacentral**. The `preprovision` hook (`scripts/preflight-region`) validates your region before anything is deployed.

## Deploy

### With azd (recommended)

```bash
azd auth login
azd env new sreagent-sbx
azd env set AZURE_LOCATION swedencentral
# private by default; to keep Grafana public-reachable too:
# azd env set GRAFANA_PUBLIC_NETWORK_ACCESS Enabled
# or to skip private networking entirely:
# azd env set ENABLE_PRIVATE_NETWORKING false
azd up
```

### With az CLI

```bash
az deployment sub create \
  --name sre-sandbox \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral \
               enablePrivateNetworking=true grafanaPublicNetworkAccess=Disabled
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full walkthrough and [post-setup.md](post-setup.md) for what to do after deploying.

## Granting access to the SRE Agent

> **Subscription Owner is NOT enough to *use* the agent.** Using the agent requires a data-plane role on the agent resource itself.

```bash
az role assignment create \
  --assignee <your-object-id> \
  --role "SRE Agent Standard User" \
  --scope <AZURE_SRE_AGENT_ID>
```

Roles, lowest to highest: **SRE Agent Reader → Standard User → Author → Administrator**. Assignments can take **5–10 minutes** to propagate; sign in to <https://sre.azure.com> with the **same account and tenant**.

## Reaching a private Grafana

When `grafanaPublicNetworkAccess = Disabled`, Grafana's UI/API is only reachable from the VNet. Use one of:
- **Azure Bastion + a jumpbox VM** in the VNet (or a peered VNet).
- **VPN / ExpressRoute** into the VNet.
- A **peered hub** that already has connectivity.

This template deploys the VNet, subnet, Private DNS zone, and private endpoint, but **not** a Bastion or jumpbox — add those to suit your access model.

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
    grafana.bicep         Azure Managed Grafana (+ public-access toggle)
    sreAgent.bicep        Azure SRE Agent + access role
    rbac.bicep            Least-privilege role assignments
    network.bicep         VNet, subnet, Private DNS zone
    privateEndpoints.bicep Grafana private endpoint + DNS zone group
scripts/
  preflight-region.*      Region/provider preflight (azd preprovision)
  show-access.*           Access summary (azd postprovision)
azure.yaml                azd project + hooks
architecture.svg          Architecture diagram
```
