# Deploy & Use — Azure SRE Agent Sandbox

End-to-end guide to deploy and use the isolated Azure SRE Agent sandbox defined in this repository.

---

## 1. What gets deployed

A single-subscription, isolated sandbox with no production connectivity:

![Architecture](architecture.svg)

| # | Resource | Purpose |
|---|----------|---------|
| 1 | Resource Group | Container for the whole sandbox |
| 2 | User-Assigned Managed Identity | Workload identity for the SRE Agent (RBAC target) |
| 3 | Log Analytics Workspace | Central logs (30-day retention) + diagnostics sink |
| 4 | Application Insights | App telemetry (workspace-based) |
| 5 | Azure Monitor Workspace | Managed Prometheus metrics store |
| 6 | Data Collection Endpoint + Rule | Prometheus metrics ingestion path |
| 7 | Storage Account (6 containers) | Import target for historical metrics/logs/traces/incidents/topology/CMDB |
| 8 | Key Vault | RBAC-mode secret store (no secrets created) |
| 9 | Azure Data Explorer cluster + `sreagent` DB | Historical observability analytics |
| 10 | Azure Managed Grafana | Dashboards + Azure MCP endpoint |
| 11 | Azure SRE Agent | The AI SRE agent |

RBAC is least-privilege; the agent identity gets `Reader` + scoped reader roles on Grafana, Log Analytics, Azure Monitor Workspace, Data Explorer, Application Insights, and Storage.

### Deployment time

End-to-end provisioning takes **~15–20 minutes**. The long pole is the Azure
Data Explorer cluster + `sreagent` database (~10–15 min); every other resource
completes in the first few minutes.

### Estimated cost

Approximate **list-price** estimate (Sweden Central, idle sandbox). Actual cost
varies by region, data volume, and SRE Agent usage — always confirm with the
[Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/).

| Component | Billing model | Approx. idle cost |
|-----------|---------------|-------------------|
| Azure Data Explorer (Dev/No-SLA, `D11_v2`, 1 instance) | Fixed compute | **~$3–4 / day** |
| Azure Managed Grafana (Standard) | Fixed base + per active user | **~$2 / day** + ~$9/user/mo |
| Azure Monitor Workspace (Managed Prometheus) | Per metric sample ingested | ~$0 idle |
| Log Analytics + Application Insights | Per GB ingested (~$2.30/GB) | ~$0 idle |
| Storage (Standard LRS, Hot) | Per GB + transactions | < $0.10 / day |
| Key Vault, DCE/DCR, Managed Identity | Per operation / free | ~$0 |
| Azure SRE Agent | Usage-based (per investigation) | Varies with use |
| **Total (idle)** | | **≈ $6–8 / day (~$180–240 / mo)** |

> Cost is dominated by the **Data Explorer dev cluster** and **Managed Grafana**.
> For short-lived demos, deploy, test, then run the teardown (Section 8) to stop
> charges. Stopping the ADX cluster between sessions also reduces cost.

---


## 2. Prerequisites

| Tool | Install |
|------|---------|
| Azure CLI 2.60+ | <https://learn.microsoft.com/cli/azure/install-azure-cli> |
| Azure Developer CLI (azd) | <https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd> |
| Bicep CLI | `az bicep install` |

Azure permissions: subscription **Owner**, or **Contributor + User Access Administrator** (role assignments are created).

Register the required resource providers once per subscription:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Dashboard
az provider register --namespace Microsoft.Monitor
az provider register --namespace Microsoft.Kusto
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.OperationalInsights
```

### Region support (validated automatically)

The Azure SRE Agent (`Microsoft.App/agents`) is only available in: **swedencentral,
uksouth, eastus2, australiaeast, francecentral, canadacentral, koreacentral**, and
the Azure Data Explorer dev SKU must be available in the chosen region.

Run the **preflight** to confirm your region before deploying (it also runs
automatically as an `azd` preprovision hook):

```bash
./scripts/preflight-region.ps1 -Location <region>   # PowerShell
./scripts/preflight-region.sh <region>              # bash
```

If the region is unsupported, the check fails with the list of valid regions so
you can pick another one.

---

## 3. Configure

```bash
cd "Azure SRE"
cp .env.example .env
```

Edit `.env`:

```ini
AZURE_SUBSCRIPTION_ID=<your-subscription-guid>
AZURE_ENV_NAME=sreagent-sbx
AZURE_LOCATION=swedencentral       # must be an SRE Agent-supported region (see above)
AZURE_RESOURCE_GROUP=              # optional; blank => rg-<env>-sre
AZURE_TAGS={"workload":"sre-agent-sandbox","environment":"poc"}
```

---

## 4. Deploy

### Option A — Azure Developer CLI (recommended)

```bash
azd auth login
azd env new $AZURE_ENV_NAME
azd env set AZURE_LOCATION swedencentral
azd env set AZURE_SUBSCRIPTION_ID <subscription-guid>
azd provision
```

`azd provision` deploys infrastructure only (there is no app code). A region
preflight runs first; on success, an access summary is printed at the end.
Outputs are written to the azd environment.

### Option B — Azure CLI

```bash
az login
az account set --subscription <subscription-guid>

# Preflight the region first (recommended)
./scripts/preflight-region.ps1 -Location swedencentral

az deployment sub create \
  --name sre-agent-sandbox \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral

# Then print the access summary
./scripts/show-access.ps1 -DeploymentName sre-agent-sandbox
```

### Validate before deploying (no changes made)

```bash
# Bicep compile
az bicep build --file infra/main.bicep

# What-if
az deployment sub what-if \
  --location swedencentral \
  --template-file infra/main.bicep \
  --parameters environmentName=sreagent-sbx location=swedencentral
```

---

## 5. Read the outputs

```bash
# azd
azd env get-values

# or Azure CLI
az deployment sub show -n sre-agent-sandbox --query properties.outputs -o jsonc
```

Key values:

| Output | Use |
|--------|-----|
| `AZURE_GRAFANA_ENDPOINT` | Grafana UI URL |
| `AZURE_GRAFANA_MCP_ENDPOINT` | `https://<grafana>/api/azure-mcp` — register with the SRE Agent |
| `AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT` | Prometheus query endpoint |
| `AZURE_DATA_EXPLORER_CLUSTER_URI` | ADX query endpoint |
| `AZURE_STORAGE_BLOB_ENDPOINT` | Upload historical data here |
| `AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID` | Agent workload identity |
| `AZURE_SRE_AGENT_ID` | The SRE Agent resource |

---

## 6. Post-deployment usage

### 6.1 Import historical observability data

Upload your exported history into the matching containers (the agent identity has `Storage Blob Data Reader`):

```bash
SA=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)

az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination metrics-data  --source ./export/prometheus
az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination logs-data     --source ./export/loki
az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination traces-data   --source ./export/tempo
az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination incidents-data --source ./export/incidents
az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination topology-data  --source ./export/topology
az storage blob upload-batch --account-name $SA --auth-mode login \
  --destination cmdb-data      --source ./export/cmdb
```

For high-volume history, ingest into the `sreagent` Azure Data Explorer database (create tables/ingestion mappings as needed for your schema — intentionally not pre-created).

### 6.2 Connect Grafana to the data

Grafana already has its system identity wired to the Azure Monitor Workspace
(`Monitoring Data Reader`). In the Grafana UI, confirm the **Azure Monitor /
Prometheus** data source resolves and build dashboards from the imported metrics.

### 6.3 Connect the SRE Agent to Grafana via MCP

This template provisions infrastructure and prerequisites only (no connectors).
To complete the connection after deploy:

1. Open the SRE Agent (`AZURE_SRE_AGENT_ID`) in the portal / `sre.azure.com`.
2. Add the Grafana MCP endpoint: `AZURE_GRAFANA_MCP_ENDPOINT`
   (`https://<grafana-endpoint>/api/azure-mcp`).
3. The agent authenticates with its user-assigned identity, which already holds
   `Grafana Viewer` and the scoped reader roles.

See <https://learn.microsoft.com/azure/sre-agent/mcp-server>.

---

## 7. Update the deployment

Edit Bicep, then re-run the same command:

```bash
azd provision        # or repeat the az deployment sub create command
```

Deployments are idempotent; deterministic naming keeps resources stable across runs.

---

## 8. Clean up

```bash
# azd (deletes everything it created)
azd down --purge --force

# or Azure CLI
az group delete --name <resource-group-name> --yes --no-wait
```

> Key Vault has purge protection enabled. Use `azd down --purge` (or
> `az keyvault purge`) to fully remove the soft-deleted vault.

---

## 9. Notes

- The Azure SRE Agent (`Microsoft.App/agents`, API `2026-01-01`) is region-gated;
  the `scripts/preflight-region` check validates support before deploying.
  `bicep build` may emit a non-blocking **BCP081** warning if the type isn't yet
  in your local Bicep type index — this does not block deployment.
- The Azure Data Explorer dev SKU defaults to `Dev(No SLA)_Standard_D11_v2`
  (broadly available, including Sweden Central). Override with `dataExplorerSkuName`
  if your region offers a different dev SKU; the preflight lists what's available.
- Key Vault purge protection is **off by default** so the sandbox can be fully
  torn down; set `enablePurgeProtection=true` for non-disposable environments.
- No service account tokens, connectors, or MCP connections are created by the
  template — only infrastructure and RBAC prerequisites.
- Everything deploys into the single selected region with no production connectivity.
