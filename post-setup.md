# Post-Deployment Setup & Validation Guide

**Azure SRE Agent — Isolated Proof-of-Concept Sandbox**

**Audience:** Azure administrators · Platform engineers · Observability engineers · SRE teams
**Status:** Infrastructure deployed via Azure Developer CLI (`azd`). This guide covers **post-deployment configuration and validation only**.

> Throughout this guide, values in `UPPER_SNAKE_CASE` (for example `AZURE_GRAFANA_ENDPOINT`) refer to deployment outputs. Retrieve them with `azd env get-values` or `az deployment sub show -n sre-agent-sandbox --query properties.outputs -o jsonc`.

---

## 1. Overview

### 1.1 Goals of the post-deployment activities

The infrastructure deployment created an isolated sandbox. The activities in this guide turn that empty platform into a working Azure SRE Agent proof-of-concept by:

1. Validating that every resource and RBAC assignment is healthy.
2. Configuring Azure Managed Grafana and its data sources (Prometheus, Loki, Tempo).
3. Importing **historical** observability data (metrics, logs, traces, incidents, CMDB, topology).
4. Building dashboards and alerts that represent the customer's services.
5. Connecting the Azure SRE Agent to Grafana through the **Managed Grafana MCP endpoint**.
6. Running end-to-end validation scenarios that prove the agent can investigate using the imported history.

### 1.2 Target architecture

![Architecture](architecture.svg)

```
Azure SRE Agent
   │  (MCP)
   ▼
Azure Managed Grafana — MCP endpoint  (https://<grafana-endpoint>/api/azure-mcp)
   │
   ▼
Grafana Data Sources
   ├── Prometheus  (Azure Monitor Workspace / Managed Prometheus)  → historical metrics
   ├── Loki        → historical logs
   └── Tempo       → historical traces
```

Supporting services: Log Analytics Workspace, Application Insights, Azure Data Explorer (`sreagent` database), Azure Storage (staging containers), Key Vault, and a User-Assigned Managed Identity that carries the agent's least-privilege RBAC.

### 1.3 No production connectivity required

This is a **self-contained** environment. The agent reasons over **imported historical data**, not live production systems. There is intentionally:

- No network peering or private connectivity to production.
- No live scraping of production Prometheus/Loki/Tempo.
- No production credentials.

This isolation makes the sandbox safe for experimentation while still demonstrating realistic investigations using real historical data.

---

## 2. Pre-Requisites Before Data Import

Complete every check below before importing any data.

### 2.1 Checklist

- [ ] All Azure resources deployed successfully
- [ ] RBAC assignments present and correct
- [ ] Grafana access confirmed
- [ ] SRE Agent access confirmed
- [ ] Azure Data Explorer access confirmed
- [ ] Storage Account access confirmed

### 2.2 Validation steps

**Resources deployed successfully**

```bash
RG=$(azd env get-value AZURE_RESOURCE_GROUP)
az resource list --resource-group "$RG" --output table
az deployment sub show -n sre-agent-sandbox --query properties.provisioningState -o tsv
# Expected: Succeeded
```

**RBAC assignments**

```bash
AGENT_PID=$(azd env get-value AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID)
az role assignment list --assignee "$AGENT_PID" --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

Expected roles for the agent identity: `Reader`, `Monitoring Reader`, `Monitoring Data Reader`, `Log Analytics Reader`, `Grafana Viewer`, `Storage Blob Data Reader`, `Key Vault Secrets User`, and ADX database `Viewer`.

**Grafana access**

```bash
az grafana show --name "$(azd env get-value AZURE_GRAFANA_ID | xargs -I{} basename {})" \
  --query "{endpoint:properties.endpoint, state:properties.provisioningState}" -o jsonc
```

**SRE Agent access**

```bash
az resource show --ids "$(azd env get-value AZURE_SRE_AGENT_ID)" \
  --query "{name:name, state:properties.provisioningState}" -o jsonc
```

**Azure Data Explorer access**

```bash
ADX_URI=$(azd env get-value AZURE_DATA_EXPLORER_CLUSTER_URI)
echo "$ADX_URI"
# In the ADX web UI (https://dataexplorer.azure.com), add the cluster and run:
#   .show database sreagent principals
```

**Storage Account access**

```bash
SA=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
az storage container list --account-name "$SA" --auth-mode login -o table
# Expected: metrics-data, logs-data, traces-data, incidents-data, topology-data, cmdb-data
```

---

## 3. Configure Azure Managed Grafana

### 3.1 First login

1. Open `AZURE_GRAFANA_ENDPOINT` in a browser.
2. Sign in with your Microsoft Entra ID account.
3. Confirm the Grafana home dashboard loads.

### 3.2 Assign Grafana Admins

```bash
GRAFANA=$(azd env get-value AZURE_GRAFANA_ID | xargs -I{} basename {})
RG=$(azd env get-value AZURE_RESOURCE_GROUP)

az role assignment create \
  --assignee <admin-user-or-group-object-id> \
  --role "Grafana Admin" \
  --scope "$(azd env get-value AZURE_GRAFANA_ID)"
```

### 3.3 Assign Grafana Viewers

```bash
az role assignment create \
  --assignee <viewer-user-or-group-object-id> \
  --role "Grafana Viewer" \
  --scope "$(azd env get-value AZURE_GRAFANA_ID)"
```

> Use Entra ID **groups** rather than individual users for maintainable access.

### 3.4 Verify managed identity configuration

Azure Managed Grafana uses its **system-assigned managed identity** to query Azure data sources. It already holds `Monitoring Reader` (resource group) and `Monitoring Data Reader` (Azure Monitor Workspace).

```bash
az role assignment list \
  --assignee "$(azd env get-value AZURE_GRAFANA_PRINCIPAL_ID)" --all \
  --query "[].roleDefinitionName" -o table
```

### 3.5 Verify Grafana endpoint

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$(azd env get-value AZURE_GRAFANA_ENDPOINT)/api/health"
# Expected: 200
```

### 3.6 Validation checklist

- [ ] Grafana UI loads and you can sign in
- [ ] At least one Grafana Admin assigned
- [ ] Viewer access assigned to the SRE/observability team group
- [ ] Grafana system identity has Monitoring Reader + Monitoring Data Reader
- [ ] `/api/health` returns `200`

---

## 4. Configure Grafana Data Sources

Add three data sources in **Grafana → Connections → Data sources**. For the sandbox, Loki and Tempo run as customer-managed endpoints that read the imported history; Prometheus is the Azure Monitor Workspace (Managed Prometheus).

### Prometheus

**How to configure**

1. **Add data source → Prometheus**.
2. **URL:** `AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT`.
3. **Auth:** enable **Azure Authentication → Managed Identity** (Grafana's system identity already has `Monitoring Data Reader`).
4. Save & test.

**Expected data types:** time-series numeric metrics (counters, gauges, histograms, summaries) with labels such as `service`, `instance`, `job`, `env`.

**Validation queries**

```promql
up
count(count by (__name__)({__name__=~".+"}))
rate(http_requests_total[5m])
```

Success: queries return series; `up` shows imported targets.

### Loki

**How to configure**

1. **Add data source → Loki**.
2. **URL:** your Loki gateway endpoint (the customer-managed Loki reading imported logs).
3. Configure auth per your Loki deployment (header/basic). Store any secret in Key Vault (see §13).
4. Save & test.

**Expected log formats:** newline-delimited JSON or logfmt entries with stream labels (`service`, `level`, `namespace`, `pod`) and a UTC timestamp.

**Validation queries**

```logql
{service=~".+"} | json
count_over_time({service="orders-api"}[1h])
{level="error"} |= "exception"
```

Success: log lines render with labels and parsed fields.

### Tempo

**How to configure**

1. **Add data source → Tempo**.
2. **URL:** your Tempo query-frontend endpoint.
3. Optionally configure **trace-to-logs** correlation to the Loki data source.
4. Save & test.

**Expected trace formats:** OpenTelemetry / OTLP spans with `trace_id`, `span_id`, `service.name`, `operation`, start time (UTC), and duration.

**Validation queries**

- Search by service: `service.name = "orders-api"`
- Search by trace ID: paste a known `trace_id`.
- TraceQL: `{ duration > 500ms }`

Success: traces return and the span waterfall renders.

### Success criteria (all data sources)

- [ ] Prometheus, Loki, Tempo all return **"Data source is working"** on Save & Test
- [ ] At least one validation query returns data per source
- [ ] Trace-to-logs correlation resolves (Tempo → Loki)

---

## 5. Prepare Historical Data Imports

Export historical data into the recommended formats before importing. Stage files in the matching Storage containers (`metrics-data`, `logs-data`, `traces-data`, `incidents-data`, `cmdb-data`, `topology-data`).

### 5.1 Recommended export formats and fields

**Metrics** — Prometheus remote-write / OpenMetrics text, or Parquet/CSV for ADX.
Recommended fields: `timestamp`, `metric_name`, `value`, `labels{service, instance, job, env}`.

**Logs** — JSON lines (preferred) or logfmt.
Recommended fields: `timestamp`, `level`, `service`, `message`, `trace_id`, `span_id`, `host`, `namespace`.

**Traces** — OTLP JSON or Jaeger JSON.
Recommended fields: `trace_id`, `span_id`, `parent_span_id`, `service_name`, `operation`, `start_time`, `duration_ms`, `status`, `attributes`.

**Incidents** — CSV or JSON (e.g., ServiceNow export).
Recommended fields: `incident_id`, `opened_at`, `resolved_at`, `severity`, `priority`, `service`, `ci`, `short_description`, `root_cause`, `assignment_group`, `state`.

**CMDB** — CSV or JSON.
Recommended fields: `ci_id`, `ci_name`, `ci_type`, `environment`, `owner`, `support_group`, `business_service`, `lifecycle_state`.

**Topology** — JSON (nodes + edges).
Recommended fields: `source_ci`, `target_ci`, `relationship_type` (`depends_on`, `hosted_on`, `connects_to`), `direction`, `criticality`.

### 5.2 Timestamp & UTC requirements

- All timestamps **must be ISO 8601** (`2026-06-30T14:05:00Z`).
- All timestamps **must be UTC**. Convert local times before import; do not rely on implicit time zones.
- Metrics and traces require millisecond precision where available.

### 5.3 Data quality recommendations

- Use **consistent service names** across metrics, logs, traces, incidents, and CMDB (this is what lets the agent correlate).
- Populate `trace_id`/`span_id` in logs to enable trace-to-logs correlation.
- Remove duplicate records and ensure monotonic timestamps per series.
- Validate character encoding (UTF-8) and escape embedded delimiters in CSV.
- Keep a consistent label/key taxonomy (for example, always `service`, never mixing `svc`/`app`).

---

## 6. Import Metrics Into Prometheus

### 6.1 Steps

1. Stage exported metric files in the `metrics-data` container:
   ```bash
   SA=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
   az storage blob upload-batch --account-name "$SA" --auth-mode login \
     --destination metrics-data --source ./export/prometheus
   ```
2. Replay history into Managed Prometheus using **remote-write** from a backfill tool (e.g., a Prometheus instance with `promtool tsdb create-blocks-from` + remote-write, or an OTLP metrics pipeline) targeting `AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT`'s ingestion path via the Data Collection Rule.
3. For long-term analytics, also ingest the metric files into the ADX `sreagent` database.

### 6.2 Validation

```promql
count(count by (__name__)({__name__=~".+"}))      # number of distinct metrics
min_over_time(timestamp(up)[30d:])                 # earliest sample (confirm history depth)
```

### 6.3 What engineers should verify

- [ ] Metric **names and labels** match production taxonomy
- [ ] Historical **time range** covers the intended incident windows
- [ ] No gaps in critical series (`rate(http_requests_total[5m])` continuous)

---

## 7. Import Logs Into Loki

### 7.1 Steps

1. Stage exported logs in `logs-data`:
   ```bash
   az storage blob upload-batch --account-name "$SA" --auth-mode login \
     --destination logs-data --source ./export/loki
   ```
2. Backfill into Loki using the Loki push API or a loader that preserves original UTC timestamps and stream labels (`service`, `level`, `namespace`).

### 7.2 Validation

```logql
count_over_time({service=~".+"}[30d])
{level="error"} | json | line_format "{{.service}} {{.message}}"
```

### 7.3 What engineers should verify

- [ ] Stream **labels** present and consistent with metrics/traces
- [ ] `trace_id` populated where available (enables correlation)
- [ ] Historical depth matches the metrics window

---

## 8. Import Traces Into Tempo

### 8.1 Steps

1. Stage exported traces in `traces-data`:
   ```bash
   az storage blob upload-batch --account-name "$SA" --auth-mode login \
     --destination traces-data --source ./export/tempo
   ```
2. Backfill into Tempo via OTLP, preserving `trace_id`, `span_id`, `parent_span_id`, and UTC start times.

### 8.2 Validation

- Search Tempo by a known `service.name` and confirm spans return.
- Open a known `trace_id` and confirm the waterfall and parent/child relationships.
- TraceQL: `{ status = error }` returns failed spans.

### 8.3 What engineers should verify

- [ ] Span **parent/child** relationships intact
- [ ] `service.name` matches metrics/logs service names
- [ ] Trace-to-logs jump resolves to the Loki data source

---

## 9. Import Incident History

### 9.1 ServiceNow exports

- Export incidents to CSV/JSON with the fields in §5.1.
- Normalize `opened_at` / `resolved_at` to UTC ISO 8601.
- Map `service` and `ci` to the same names used in CMDB and telemetry.

### 9.2 CSV imports

- Stage in `incidents-data`:
  ```bash
  az storage blob upload-batch --account-name "$SA" --auth-mode login \
    --destination incidents-data --source ./export/incidents
  ```

### 9.3 ADX ingestion (recommended for analytics)

```kusto
// In the ADX web UI against database 'sreagent'
.create table Incidents (
    incident_id:string, opened_at:datetime, resolved_at:datetime,
    severity:string, priority:string, service:string, ci:string,
    short_description:string, root_cause:string, assignment_group:string, state:string
)
.create table Incidents ingestion csv mapping 'IncidentsMapping'
'[{"column":"incident_id","Properties":{"Ordinal":"0"}}, ... ]'
// Then ingest from the staged blob (SAS or managed identity).
.ingest into table Incidents (h'https://<storage>/incidents-data/incidents.csv;...')
  with (format='csv', ingestionMappingReference='IncidentsMapping')
```

### 9.4 Log Analytics ingestion (alternative)

- Use a **custom table** (DCR-based custom logs) in the Log Analytics workspace if you prefer KQL over Grafana for incident analytics.

### 9.5 Validation

```kusto
Incidents | summarize count() by severity
Incidents | where opened_at > ago(90d) | summarize incidents=count() by service | top 10 by incidents
```

- [ ] Incident counts match the source system
- [ ] `service`/`ci` values join cleanly to telemetry and CMDB

---

## 10. Import CMDB and Topology Data

### 10.1 What to import

- **Configuration Items (CIs):** servers, services, databases, queues — with `ci_id`, `ci_type`, `environment`, `lifecycle_state`.
- **Service ownership:** `owner`, `support_group`, `business_service` per CI.
- **Dependency relationships:** directed edges (`depends_on`, `hosted_on`, `connects_to`) with criticality.
- **Application topology:** how services connect end-to-end (frontend → API → database → dependencies).

### 10.2 Why topology matters for investigations

When the agent investigates an incident, topology lets it traverse from a failing service to its **upstream and downstream dependencies**, correlate the blast radius, and identify the most likely root cause. Without topology, the agent sees isolated signals; with it, the agent reasons about cause-and-effect across the service graph.

### 10.3 Import

```bash
az storage blob upload-batch --account-name "$SA" --auth-mode login \
  --destination cmdb-data --source ./export/cmdb
az storage blob upload-batch --account-name "$SA" --auth-mode login \
  --destination topology-data --source ./export/topology
```

Ingest both into ADX (`sreagent`) as `ConfigurationItems` and `Topology` tables for queryability.

### 10.4 Validation

```kusto
ConfigurationItems | summarize count() by ci_type
Topology | where relationship_type == "depends_on" | summarize deps=count() by source_ci | top 10 by deps
// Confirm every telemetry 'service' has a matching CI:
Incidents | distinct service
| join kind=leftanti (ConfigurationItems | distinct ci_name) on $left.service == $right.ci_name
```

- [ ] Every active service has a CI and an owner
- [ ] Dependency edges resolve to existing CIs
- [ ] The leftanti query returns **no** unmatched services

---

## 11. Configure Grafana Dashboards

Build (or import) dashboards that mirror the customer's services. Recommended set:

| Dashboard | Key panels | Primary source |
|-----------|-----------|----------------|
| **Service Health** | up/down, availability %, RED metrics | Prometheus |
| **Error Rates** | error ratio, 4xx/5xx, error logs | Prometheus + Loki |
| **Latency Trends** | p50/p90/p99, slowest operations | Prometheus + Tempo |
| **Incident Trends** | incidents over time, MTTR, by service | ADX/Incidents |
| **Reliability KPIs** | SLO attainment, error budget burn | Prometheus + ADX |

**Validation**

- [ ] Each dashboard renders with historical data (no "No data")
- [ ] Time range can be moved to a known incident window and panels populate
- [ ] Variables (e.g., `service`) filter correctly

---

## 12. Configure Alerts

Define Grafana alert rules (evaluated against historical/imported data for demonstration). Recommended:

| Alert | Condition (example) |
|-------|---------------------|
| **Error rate spike** | `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05` |
| **Service downtime** | `up == 0 for 5m` |
| **Latency degradation** | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 1` |
| **Dependency failure** | error ratio on a downstream service > threshold |

**Validation**

- [ ] Each rule evaluates without query errors
- [ ] Replaying a known-bad window triggers the alert as expected
- [ ] Notification policy/contact point configured (sandbox channel)

---

## 13. Enable Grafana MCP Access

### 13.1 MCP endpoint format

```
https://<grafana-endpoint>/api/azure-mcp
```

Use the deployment output `AZURE_GRAFANA_MCP_ENDPOINT`.

### 13.2 Authentication options

**Option A — Microsoft Entra ID (recommended)**

- The Azure SRE Agent authenticates with its **user-assigned managed identity**, which already holds `Grafana Viewer` on the Grafana instance.
- No secrets to manage; access is governed entirely by Azure RBAC.
- This is the preferred approach for production-grade security.

**Option B — Service account token**

- A Grafana service-account token may be used by MCP clients that cannot use Entra ID.
- **This guide does not generate any token.** If your scenario requires one, create it manually in Grafana and treat it as a secret.

### 13.3 Security considerations

- Prefer Entra ID + managed identity; avoid long-lived tokens.
- Grant **least privilege** (Viewer, not Admin) to the agent identity.
- Rotate any manually created tokens regularly and scope them narrowly.
- Never commit tokens to source control or paste them into shared documents.

### 13.4 Securely store secrets in Azure Key Vault

If you must use a service-account token, store it in the deployed Key Vault (RBAC mode). The agent identity holds `Key Vault Secrets User`.

```bash
KV=$(azd env get-value AZURE_KEY_VAULT_NAME)
# Set the secret value interactively/securely — do NOT hardcode it in scripts or commit it.
az keyvault secret set --vault-name "$KV" --name grafana-mcp-token
# (You will be prompted; or pipe from a secure source. Reference it later via Key Vault, never inline.)
```

### 13.5 Validation steps

- [ ] `AZURE_GRAFANA_MCP_ENDPOINT` resolves and `/api/health` returns `200`
- [ ] The agent identity has `Grafana Viewer`
- [ ] (If used) the token is stored in Key Vault, not in plaintext

---

## 14. Configure Azure SRE Agent MCP Connection

### 14.1 Steps

1. Open the Azure SRE Agent (`AZURE_SRE_AGENT_ID`) in the Azure portal or at `https://sre.azure.com`.
2. Go to the agent's **MCP / connectors** configuration.
3. **Register the MCP endpoint:** paste `AZURE_GRAFANA_MCP_ENDPOINT`.
4. **Authentication:** select Microsoft Entra ID and the agent's user-assigned managed identity (recommended), or reference the Key Vault-stored token.
5. Save the configuration.

### 14.2 Access validation

```bash
# Confirm the agent identity can reach Grafana's RBAC scope
az role assignment list \
  --assignee "$(azd env get-value AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID)" \
  --scope "$(azd env get-value AZURE_GRAFANA_ID)" -o table
```

### 14.3 Connectivity testing

- From the agent, run a health/connection test against the MCP endpoint.
- Confirm the endpoint returns a successful handshake and the agent lists Grafana as a connected MCP server.

### 14.4 Expected outcomes

- [ ] MCP endpoint registered without error
- [ ] Authentication succeeds via managed identity
- [ ] Agent shows Grafana MCP as **connected**

---

## 15. Validate MCP Tool Discovery

Confirm the Azure SRE Agent can **discover** the tools exposed by the Grafana MCP server.

### 15.1 How to confirm

- In the agent, list available MCP tools/capabilities for the Grafana connection.
- Confirm Grafana query tools (dashboards, data-source queries) appear.

### 15.2 Example validation questions

Ask the agent:

- "List the Grafana data sources available through MCP."
- "Which dashboards exist in Grafana?"
- "Query the Prometheus data source for the error rate of `orders-api` over the last 24 hours."
- "Show error logs for `orders-api` from Loki during the last incident window."

### 15.3 Expected behavior

- The agent enumerates Grafana tools without authentication errors.
- Queries return results sourced from the **imported historical data**.
- The agent cites the data source (Prometheus/Loki/Tempo) it used.

---

## 16. End-To-End Validation Scenarios

Run the following scenarios. Each has explicit success criteria.

1. **Incident investigation** — Ask the agent to investigate a known historical incident window.
   *Success:* it identifies affected service(s) and summarizes evidence from metrics + logs.

2. **Alert correlation** — Provide an error-rate spike timestamp.
   *Success:* it correlates the spike with related logs/traces and any concurrent alerts.

3. **Root cause analysis** — Ask "what was the likely root cause of the `orders-api` latency on \<date\>?"
   *Success:* it proposes an evidence-backed cause (e.g., downstream DB latency / config change).

4. **Dependency analysis** — Ask "what depends on `payments-db`?"
   *Success:* it traverses topology and lists upstream/downstream services.

5. **Trend analysis** — Ask "show the 30-day error-rate trend for `checkout`."
   *Success:* it returns a trend with notable inflection points.

6. **Service ownership lookup** — Ask "who owns `orders-api`?"
   *Success:* it returns owner/support group from CMDB.

7. **Blast-radius assessment** — Ask "if `payments-db` fails, what is impacted?"
   *Success:* it lists dependent services using topology.

8. **Latency hotspot** — Ask "which operation in `orders-api` is slowest?"
   *Success:* it identifies the slow span/operation from Tempo.

9. **Recurring incident detection** — Ask "has this incident happened before?"
   *Success:* it finds prior similar incidents in the incident history.

10. **Cross-signal correlation** — Ask "correlate the error logs, failing traces, and metrics for the \<date\> outage."
    *Success:* it ties together logs (Loki), traces (Tempo), and metrics (Prometheus) for the same window/service.

11. **MTTR reporting** — Ask "what is the MTTR by service over the last quarter?"
    *Success:* it computes MTTR from incident history.

12. **Reliability KPI** — Ask "what is the error budget burn for `checkout` this month?"
    *Success:* it returns an SLO/error-budget figure from metrics.

---

## 17. Troubleshooting Guide

| Symptom | Likely cause | Actions |
|---------|--------------|---------|
| **No metrics available** | Backfill not completed; wrong query endpoint; Grafana identity missing `Monitoring Data Reader` | Re-check §6; verify `AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT`; confirm role assignment; run `count(count by (__name__)({__name__=~".+"}))` |
| **No logs available** | Loki backfill failed; wrong URL/auth; label mismatch | Re-check §7; test Loki data source; run `count_over_time({service=~".+"}[30d])`; verify labels |
| **No traces available** | Tempo backfill failed; `service.name` mismatch | Re-check §8; search by known `trace_id`; confirm OTLP timestamps in UTC |
| **MCP connection failures** | Endpoint not registered; wrong URL; network/health failure | Verify `AZURE_GRAFANA_MCP_ENDPOINT`; `curl /api/health` → 200; re-register in §14 |
| **Authentication failures** | Agent identity lacks Grafana role; token invalid/expired | Confirm `Grafana Viewer` on agent identity; if using token, rotate and re-store in Key Vault |
| **Empty dashboards** | Time range outside imported window; variable filters exclude data | Move time range to a known window; reset dashboard variables; confirm data source health |
| **RBAC issues** | Missing/incorrect role assignments | Re-run §2.2 RBAC check; reassign least-privilege roles; allow for propagation delay |
| **Data import problems** | Non-UTC timestamps; encoding; schema drift | Validate ISO 8601/UTC (§5.2); check UTF-8; align field names to §5.1; remove duplicates |

General first steps: confirm `provisioningState = Succeeded`, re-run the §2 validation, and check Azure Activity Log for the resource group.

---

## 18. Operational Readiness Checklist

**Infrastructure & access**
- [ ] All resources show `Succeeded`
- [ ] Agent identity RBAC verified (Reader + scoped readers)
- [ ] Grafana admins and viewers assigned
- [ ] Grafana system identity has Monitoring Reader + Monitoring Data Reader

**Data sources**
- [ ] Prometheus data source connected and returning data
- [ ] Loki data source connected and returning data
- [ ] Tempo data source connected and returning data
- [ ] Trace-to-logs correlation working

**Historical data import**
- [ ] Metrics imported and validated
- [ ] Logs imported and validated
- [ ] Traces imported and validated
- [ ] Incident history imported (CSV/ADX/Log Analytics)
- [ ] CMDB imported and owners present
- [ ] Topology imported and dependencies resolve
- [ ] All timestamps ISO 8601 / UTC
- [ ] Service names consistent across all datasets

**Dashboards & alerts**
- [ ] Service Health, Error Rates, Latency, Incident Trends, Reliability KPIs built
- [ ] Alerts configured (error spike, downtime, latency, dependency failure)

**MCP & agent**
- [ ] Grafana MCP endpoint healthy (`/api/health` = 200)
- [ ] Secrets (if any) stored in Key Vault — none in plaintext
- [ ] SRE Agent MCP connection registered and authenticated
- [ ] Agent discovers Grafana MCP tools
- [ ] All 12 end-to-end validation scenarios pass

**Sign-off**
- [ ] Observability engineer sign-off
- [ ] Platform/Azure administrator sign-off
- [ ] SRE team sign-off
