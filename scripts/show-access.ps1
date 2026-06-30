<#
.SYNOPSIS
  Prints the access summary (URLs, endpoints, IDs) needed for post-deployment
  configuration of the Azure SRE Agent sandbox.

.DESCRIPTION
  Runs as an azd 'postprovision' hook (deployment outputs are available as
  environment variables) or manually. When run manually outside azd, pass the
  deployment name and it will read the outputs from Azure.

.EXAMPLE
  ./scripts/show-access.ps1
  ./scripts/show-access.ps1 -DeploymentName sre-test
#>
[CmdletBinding()]
param(
    [string]$DeploymentName
)

function Get-Output {
    param([string]$Name)
    $val = [Environment]::GetEnvironmentVariable($Name)
    if (-not $val -and $script:Outputs) { $val = $script:Outputs.$Name.value }
    return $val
}

$script:Outputs = $null
if ($DeploymentName) {
    $script:Outputs = az deployment sub show --name $DeploymentName --query properties.outputs -o json 2>$null | ConvertFrom-Json
}

$grafana   = Get-Output 'AZURE_GRAFANA_ENDPOINT'
$mcp       = Get-Output 'AZURE_GRAFANA_MCP_ENDPOINT'
$agentId   = Get-Output 'AZURE_SRE_AGENT_ID'
$agentName = Get-Output 'AZURE_SRE_AGENT_NAME'
$prom      = Get-Output 'AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT'
$adx       = Get-Output 'AZURE_DATA_EXPLORER_CLUSTER_URI'
$adxDb     = Get-Output 'AZURE_DATA_EXPLORER_DATABASE_NAME'
$blob      = Get-Output 'AZURE_STORAGE_BLOB_ENDPOINT'
$saName    = Get-Output 'AZURE_STORAGE_ACCOUNT_NAME'
$kvUri     = Get-Output 'AZURE_KEY_VAULT_URI'
$kvName    = Get-Output 'AZURE_KEY_VAULT_NAME'
$appiConn  = Get-Output 'AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING'
$miId      = Get-Output 'AZURE_USER_ASSIGNED_IDENTITY_ID'
$miClient  = Get-Output 'AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID'
$miPrin    = Get-Output 'AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID'
$rg        = Get-Output 'AZURE_RESOURCE_GROUP'
$loc       = Get-Output 'AZURE_LOCATION'

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "  Azure SRE Agent sandbox — deployment complete. Access & post-config details" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource group : $rg   ($loc)"
Write-Host ""
Write-Host "ACCESS URLs" -ForegroundColor Yellow
Write-Host "  Grafana UI                : $grafana"
Write-Host "  Grafana MCP endpoint      : $mcp"
Write-Host "  Prometheus query endpoint : $prom"
Write-Host "  Data Explorer cluster URI : $adx   (database: $adxDb)"
Write-Host "  Storage blob endpoint     : $blob   (account: $saName)"
Write-Host "  Key Vault URI             : $kvUri   (name: $kvName)"
Write-Host ""
Write-Host "AZURE SRE AGENT" -ForegroundColor Yellow
Write-Host "  Name : $agentName"
Write-Host "  Id   : $agentId"
Write-Host ""
Write-Host "WORKLOAD IDENTITY (used for agent RBAC / Grafana MCP auth)" -ForegroundColor Yellow
Write-Host "  Resource ID  : $miId"
Write-Host "  Client ID    : $miClient"
Write-Host "  Principal ID : $miPrin"
Write-Host ""
Write-Host "APP INSIGHTS" -ForegroundColor Yellow
Write-Host "  Connection string : $appiConn"
Write-Host ""
Write-Host "NEXT STEPS" -ForegroundColor Yellow
Write-Host "  1. Open Grafana and confirm the Azure Monitor / Prometheus data source."
Write-Host "  2. Register the Grafana MCP endpoint on the SRE Agent (managed-identity auth)."
Write-Host "  3. Import historical data into the storage containers / Data Explorer."
Write-Host "  See post-setup.md for the full post-deployment guide."
Write-Host "=============================================================================="
