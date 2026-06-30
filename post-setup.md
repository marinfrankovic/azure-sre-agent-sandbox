# Post-deployment setup

After `azd up` (or the `az` deployment) finishes, do the following to get the SRE Agent investigating real data.

![Architecture](architecture.svg)

## 1. Confirm the access summary

The `postprovision` access summary prints the Grafana URL, the MCP endpoint, and the agent/identity IDs. Grafana is on its **public endpoint secured by Entra ID + RBAC** (API keys and anonymous access are disabled), so the Microsoft-managed SRE Agent can reach it directly — there is nothing to configure on the network side.

## 2. Grant yourself access to the SRE Agent

Using the agent requires a data-plane role on the agent — **subscription Owner is not sufficient**. If you didn't pass `agentAccessPrincipalId` at deploy time:

```bash
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "SRE Agent Standard User" \
  --scope <AZURE_SRE_AGENT_ID>
```

Allow 5–10 minutes for propagation, then sign in to <https://sre.azure.com> with the **same account and tenant**.

> If you see a banner offering to migrate to a newer SRE Agent version, you can accept it — it upgrades the sandbox (code/file access, log-to-code investigation, better memory) without affecting RBAC or this deployment.

## 3. Add your data sources to Grafana

The agent only sees what Grafana can query. Open Grafana and add your data sources — typically **restored from backup**:

1. Grafana → **Connections → Data sources → Add data source**.
2. Add **Prometheus**, **Loki**, and/or **Tempo** pointing at your restored backends.
3. If those backends are private, use Grafana **managed private endpoints** to reach them.
4. Set the appropriate auth for each source and **Save & test**.

## 4. Connect the agent to Grafana (MCP)

The agent reaches Grafana through its MCP endpoint:

```
<AZURE_GRAFANA_ENDPOINT>/api/azure-mcp
```

Use **Managed identity** auth with the agent's identity (it already has **Grafana Viewer**). The Azure AD token scope for Managed Grafana is:

```
ce34e7e5-485f-4d76-964f-b3d2b16d1e4f/.default
```

## 5. Try an investigation

In <https://sre.azure.com>, open your agent and ask it to investigate a service. It will use Grafana (via MCP) to pull metrics/logs/traces from the data sources you added and reason over them.

## What you should NOT need to do

- No need to deploy Prometheus/Loki/Tempo via this template — you bring them.
- No Azure Monitor, Log Analytics, or Azure Data Explorer wiring — out of scope by design.

## Tear down when finished

```bash
azd down --purge --force
# or
az group delete --name <resource-group> --yes --no-wait
```
