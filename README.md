# Azure SRE Agent + Managed Grafana sandbox

A deploy-and-go sandbox for evaluating the **Azure SRE Agent** with **Azure Managed Grafana**. The agent investigates incidents by querying Grafana through Grafana's MCP endpoint, so the only services this template provisions are the agent, its identity, and Grafana.

**How access works.** The Azure SRE Agent (`Microsoft.App/agents`) is a **Microsoft-managed service**, so it reaches Grafana over Grafana's **public endpoint, hardened by Entra ID authentication + Grafana RBAC**, with **API keys and anonymous access disabled**. Every call is authenticated and authorized; there is no anonymous path in.

**Bring your own observability data.** This template does *not* stand up Prometheus, Loki, Tempo, or any data store. You add your data sources to Grafana yourself — typically by restoring them from backup — and the SRE Agent reaches that data through Grafana.

![Architecture](architecture.svg)

## What gets deployed

| Resource | Type | Purpose |
| --- | --- | --- |
| Resource group | `Microsoft.Resources/resourceGroups` | Sandbox boundary |
| User-assigned managed identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | Workload identity for the SRE Agent |
| Azure SRE Agent | `Microsoft.App/agents` | The AI SRE that investigates incidents |
| Azure Managed Grafana | `Microsoft.Dashboard/grafana` | Dashboards + the MCP endpoint the agent queries |

That's the template's footprint. Note that creating the SRE Agent also **auto-provisions an Application Insights instance and a Log Analytics workspace** (for the agent's own observability) — these appear in your subscription and carry pay-per-GB ingestion costs. Everything else (Prometheus/Loki/Tempo, storage, logs) is **yours to bring** — secure those data sources on your own network and connect them to Grafana.

## How it's secured

Grafana is reachable on the public internet **only after Entra ID sign-in**; there is no anonymous access and no API keys.

| Control | Setting |
| --- | --- |
| Grafana authentication | Entra ID (Azure AD) — required for every request |
| Grafana API keys | `Disabled` |
| Anonymous access | Off (default) |
| Agent → Grafana auth | Managed identity (Microsoft Entra token) |
| Agent → Grafana authorization | **Grafana Viewer** role (read-only), scoped to the Grafana instance |

The public endpoint is an authentication boundary, not an open door — access is gated by your tenant's identity controls (Conditional Access, MFA, etc.) exactly like the Grafana UI.

## Least-privilege access

| Principal | Role | Scope |
| --- | --- | --- |
| Agent identity | Reader | Resource group |
| Agent identity | Grafana Viewer | Grafana |
| You (deployer) | SRE Agent Standard User | SRE Agent |

The deployer assignment is driven by `agentAccessPrincipalId` (defaults to the signed-in user with `azd`).

## Cost & time

> **The SRE Agent is not free.** Billing is in **Azure Agent Units (AAU)** at **$0.10/AAU**, with two parts:
> - **Always-on (fixed):** **4 AAU/agent-hour = $0.40/hour ≈ $9.60/day (~$288/month)** for as long as the agent *exists*, even when idle. It only stops when you **delete** the agent (stopping the agent does **not** stop always-on charges).
> - **Active flow (usage):** metered on LLM tokens per task — e.g. a quick question ≈ 3.8 AAU (~$0.38), an automated incident investigation ≈ 35 AAU (~$3.50) on Claude Opus 4.6 (cheaper on GPT models). Set a monthly AAU cap in **Settings → Agent consumption**.

Other standing costs:

| Item | Approx. cost |
| --- | --- |
| Azure SRE Agent — always-on | **~$9.60/day** (4 AAU/hr × $0.10), plus active-flow usage |
| Azure Managed Grafana (Standard) | ~$2/day |
| Application Insights + Log Analytics workspace (auto-created with the agent) | pay-per-GB ingestion (small for a sandbox) |
| Managed identity + resource group | no charge |

So a **mostly-idle sandbox is roughly ~$12/day (~$350/month)** before any meaningful agent activity — dominated by the agent's always-on baseline, not Grafana. **Delete the agent (or run `azd down`) when you're done** to stop the always-on charge. Figures are list price (USD, East US class regions); see the [official pricing](https://azure.microsoft.com/pricing/details/sre-agent/) and [billing docs](https://learn.microsoft.com/azure/sre-agent/pricing-billing) for current rates, free/trial AAUs, and your region/currency.

- **Deployment time:** about **5–10 minutes**.

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

```bash
az role assignment create \
  --assignee <your-object-id> \
  --role "SRE Agent Standard User" \
  --scope <AZURE_SRE_AGENT_ID>
```

Roles, lowest to highest: **SRE Agent Reader → Standard User → Author → Administrator**. Assignments can take **5–10 minutes** to propagate; sign in to <https://sre.azure.com> with the **same account and tenant**.

## Connecting the agent to Grafana (MCP)

The agent reaches Grafana through its MCP endpoint:

```
<AZURE_GRAFANA_ENDPOINT>/api/azure-mcp
```

Use **managed identity** auth with the agent's identity — it already holds **Grafana Viewer**. Because Grafana is on its public, Entra-protected endpoint, the Microsoft-managed agent can reach it directly with no networking to configure.

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
    grafana.bicep         Azure Managed Grafana (public + Entra/RBAC, API keys off)
    sreAgent.bicep        Azure SRE Agent + access role
    rbac.bicep            Least-privilege role assignments
scripts/
  preflight-region.*      Region/provider preflight (azd preprovision)
  show-access.*           Access summary (azd postprovision)
azure.yaml                azd project + hooks
architecture.svg          Architecture diagram
```
