<#
.SYNOPSIS
  Pre-deployment region check for the Azure SRE Agent + Managed Grafana sandbox.

.DESCRIPTION
  Validates that the selected Azure region supports the Azure SRE Agent BEFORE
  any resources are deployed, with clear guidance when it isn't. Runs as an azd
  'preprovision' hook or manually.

.EXAMPLE
  ./scripts/preflight-region.ps1 -Location swedencentral
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Location
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
Write-Host "Preflight: validating region '$Location' for the SRE Agent + Grafana sandbox" -ForegroundColor Cyan
Write-Host ("-" * 70)

if ($sreAgentRegions -contains $loc) {
    Write-Host "[PASS] Azure SRE Agent is available in '$Location'."
}
else {
    $ok = $false
    Write-Host "[FAIL] Azure SRE Agent is NOT available in '$Location'." -ForegroundColor Red
    Write-Host "       Choose one of: $($sreAgentRegions -join ', ')" -ForegroundColor Yellow
}

foreach ($rp in @('Microsoft.App', 'Microsoft.Dashboard', 'Microsoft.ManagedIdentity')) {
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
