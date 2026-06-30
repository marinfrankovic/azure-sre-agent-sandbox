<#
.SYNOPSIS
  Prints a connection summary after deployment (azd 'postprovision' hook).

.DESCRIPTION
  Reads azd environment outputs and prints the Grafana URL, the Grafana MCP
  endpoint, the SRE Agent identifiers, and the managed identity IDs.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

function Get-AzdValue([string]$key) {
    $v = azd env get-value $key 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($v)) { return '' }
    return $v.Trim()
}

$rg          = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$grafanaUrl  = Get-AzdValue 'AZURE_GRAFANA_ENDPOINT'
$grafanaMcp  = Get-AzdValue 'AZURE_GRAFANA_MCP_ENDPOINT'
$agentName   = Get-AzdValue 'AZURE_SRE_AGENT_NAME'
$agentId     = Get-AzdValue 'AZURE_SRE_AGENT_ID'
$miId        = Get-AzdValue 'AZURE_USER_ASSIGNED_IDENTITY_ID'
$miClient    = Get-AzdValue 'AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID'

Write-Host ""
Write-Host "==================== SANDBOX ACCESS SUMMARY ====================" -ForegroundColor Cyan
Write-Host "Resource group     : $rg"
Write-Host ""
Write-Host "Managed Grafana (public endpoint, secured by Entra ID + RBAC)" -ForegroundColor Green
Write-Host "  URL              : $grafanaUrl"
Write-Host "  MCP endpoint     : $grafanaMcp"
Write-Host ""
Write-Host "Azure SRE Agent" -ForegroundColor Green
Write-Host "  Name             : $agentName"
Write-Host "  Resource ID      : $agentId"
Write-Host "  Console          : https://sre.azure.com"
Write-Host ""
Write-Host "Managed identity (agent workload identity)" -ForegroundColor Green
Write-Host "  Resource ID      : $miId"
Write-Host "  Client ID        : $miClient"
Write-Host ""
Write-Host "Next steps" -ForegroundColor Yellow
Write-Host "  1. In Grafana, add your data sources (Prometheus/Loki/Tempo) restored from backup."
Write-Host "  2. Open https://sre.azure.com and select agent '$agentName'."
Write-Host "  3. To USE the agent, you need SRE Agent Reader (or higher) on the agent —"
Write-Host "     subscription Owner is NOT sufficient. See README 'Granting access'."
Write-Host "  4. Connect the agent to Grafana MCP at the endpoint above using the agent's"
Write-Host "     managed identity (it already holds Grafana Viewer)."
Write-Host "===============================================================" -ForegroundColor Cyan
