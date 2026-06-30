<#
.SYNOPSIS
  Pre-deployment region capability check for the Azure SRE Agent sandbox.

.DESCRIPTION
  Validates that the selected Azure region can host every component of the
  sandbox BEFORE any resources are deployed, and prints clear, actionable
  guidance when a region is not supported. Intended to run as an azd
  'preprovision' hook or manually before `az deployment sub create`.

.EXAMPLE
  ./scripts/preflight-region.ps1 -Location swedencentral
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Location,

    # Kusto dev SKU used by dataExplorer.bicep.
    [string]$DataExplorerSku = 'Dev(No SLA)_Standard_D11_v2'
)

$ErrorActionPreference = 'Stop'
$loc = $Location.ToLower().Replace(' ', '')
$ok = $true

# Regions where the Azure SRE Agent (Microsoft.App/agents) is available.
$sreAgentRegions = @(
    'swedencentral', 'uksouth', 'eastus2', 'australiaeast',
    'francecentral', 'canadacentral', 'koreacentral'
)

Write-Host ""
Write-Host "Preflight: validating region '$Location' for the Azure SRE Agent sandbox" -ForegroundColor Cyan
Write-Host ("-" * 70)

# 1) Azure SRE Agent region availability ------------------------------------
if ($sreAgentRegions -contains $loc) {
    Write-Host "[PASS] Azure SRE Agent is available in '$Location'."
}
else {
    $ok = $false
    Write-Host "[FAIL] Azure SRE Agent is NOT available in '$Location'." -ForegroundColor Red
    Write-Host "       Choose one of: $($sreAgentRegions -join ', ')" -ForegroundColor Yellow
}

# 2) Azure Data Explorer (Kusto) dev SKU availability -----------------------
try {
    $sub = az account show --query id -o tsv 2>$null
    $catalog = az rest --method get --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Kusto/skus?api-version=2024-04-13" 2>$null | ConvertFrom-Json
    $regionSkus = $catalog.value | Where-Object { $_.resourceType -eq 'clusters' -and ($_.locations -contains $loc) } | Select-Object -ExpandProperty name -Unique
    if ($regionSkus -contains $DataExplorerSku) {
        Write-Host "[PASS] Data Explorer dev SKU ($DataExplorerSku) is available in '$Location'."
    }
    else {
        $ok = $false
        $devSkus = ($regionSkus | Where-Object { $_ -like 'Dev*' }) -join ', '
        Write-Host "[FAIL] Data Explorer SKU '$DataExplorerSku' is NOT available in '$Location'." -ForegroundColor Red
        if ($devSkus) {
            Write-Host "       Available dev SKUs here: $devSkus  (set dataExplorerSkuName accordingly)" -ForegroundColor Yellow
        }
        else {
            Write-Host "       No Data Explorer dev SKUs are available in this region. Choose another region." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "[WARN] Could not query Kusto SKUs for '$Location': $($_.Exception.Message)" -ForegroundColor Yellow
}

# 3) Resource provider registration (informational) -------------------------
$providers = @(
    'Microsoft.App', 'Microsoft.Dashboard', 'Microsoft.Monitor', 'Microsoft.Kusto',
    'Microsoft.Insights', 'Microsoft.OperationalInsights', 'Microsoft.Storage',
    'Microsoft.KeyVault', 'Microsoft.ManagedIdentity'
)
foreach ($rp in $providers) {
    $state = az provider show --namespace $rp --query registrationState -o tsv 2>$null
    if ($state -ne 'Registered') {
        Write-Host "[WARN] Provider $rp is '$state'. Register it: az provider register --namespace $rp" -ForegroundColor Yellow
    }
}

Write-Host ("-" * 70)
if (-not $ok) {
    Write-Error "Preflight FAILED for region '$Location'. Choose a supported region and retry."
    exit 1
}
Write-Host "Preflight PASSED for region '$Location'." -ForegroundColor Green
