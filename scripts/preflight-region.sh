#!/usr/bin/env bash
# Pre-deployment region capability check for the Azure SRE Agent sandbox.
# Validates that the selected Azure region can host every component BEFORE any
# resources are deployed, with clear guidance when a region is not supported.
# Intended as an azd 'preprovision' hook or a manual pre-check.
#
# Usage: scripts/preflight-region.sh <location> [dataExplorerVmSize]
set -euo pipefail

LOCATION="${1:?Usage: preflight-region.sh <location> [dataExplorerSku]}"
ADX_SKU="${2:-Dev(No SLA)_Standard_D11_v2}"
LOC="$(echo "$LOCATION" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
OK=1

# Regions where the Azure SRE Agent (Microsoft.App/agents) is available.
SRE_REGIONS=(swedencentral uksouth eastus2 australiaeast francecentral canadacentral koreacentral)

echo ""
echo "Preflight: validating region '$LOCATION' for the Azure SRE Agent sandbox"
echo "----------------------------------------------------------------------"

# 1) Azure SRE Agent region availability
if printf '%s\n' "${SRE_REGIONS[@]}" | grep -qx "$LOC"; then
  echo "[PASS] Azure SRE Agent is available in '$LOCATION'."
else
  OK=0
  echo "[FAIL] Azure SRE Agent is NOT available in '$LOCATION'."
  echo "       Choose one of: ${SRE_REGIONS[*]}"
fi

# 2) Azure Data Explorer (Kusto) dev SKU availability
SUB="$(az account show --query id -o tsv 2>/dev/null || true)"
REGION_SKUS="$(az rest --method get --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Kusto/skus?api-version=2024-04-13" 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(sorted({s['name'] for s in d['value'] if s.get('resourceType')=='clusters' and '$LOC' in s.get('locations',[])})))" 2>/dev/null || true)"
if printf '%s\n' "$REGION_SKUS" | grep -qx "$ADX_SKU"; then
  echo "[PASS] Data Explorer dev SKU ($ADX_SKU) is available in '$LOCATION'."
else
  OK=0
  DEV_SKUS="$(printf '%s\n' "$REGION_SKUS" | grep '^Dev' | paste -sd ', ' - || true)"
  echo "[FAIL] Data Explorer SKU '$ADX_SKU' is NOT available in '$LOCATION'."
  if [ -n "$DEV_SKUS" ]; then
    echo "       Available dev SKUs here: $DEV_SKUS  (set dataExplorerSkuName accordingly)"
  else
    echo "       No Data Explorer dev SKUs are available in this region. Choose another region."
  fi
fi

# 3) Resource provider registration (informational)
for rp in Microsoft.App Microsoft.Dashboard Microsoft.Monitor Microsoft.Kusto \
          Microsoft.Insights Microsoft.OperationalInsights Microsoft.Storage \
          Microsoft.KeyVault Microsoft.ManagedIdentity; do
  state="$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
  if [ "$state" != "Registered" ]; then
    echo "[WARN] Provider $rp is '$state'. Register it: az provider register --namespace $rp"
  fi
done

echo "----------------------------------------------------------------------"
if [ "$OK" -ne 1 ]; then
  echo "Preflight FAILED for region '$LOCATION'. Choose a supported region and retry." >&2
  exit 1
fi
echo "Preflight PASSED for region '$LOCATION'."
