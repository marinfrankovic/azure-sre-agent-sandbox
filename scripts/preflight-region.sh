#!/usr/bin/env bash
# Pre-deployment region check for the Azure SRE Agent + Managed Grafana sandbox.
# Validates SRE Agent region support BEFORE deploying. Runs as an azd
# 'preprovision' hook or manually: scripts/preflight-region.sh <location>
set -euo pipefail

LOCATION="${1:?Usage: preflight-region.sh <location>}"
LOC="$(echo "$LOCATION" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
OK=1

SRE_REGIONS=(swedencentral uksouth eastus2 australiaeast francecentral canadacentral koreacentral)

echo ""
echo "Preflight: validating region '$LOCATION' for the SRE Agent + Grafana sandbox"
echo "----------------------------------------------------------------------"

if printf '%s\n' "${SRE_REGIONS[@]}" | grep -qx "$LOC"; then
  echo "[PASS] Azure SRE Agent is available in '$LOCATION'."
else
  OK=0
  echo "[FAIL] Azure SRE Agent is NOT available in '$LOCATION'."
  echo "       Choose one of: ${SRE_REGIONS[*]}"
fi

for rp in Microsoft.App Microsoft.Dashboard Microsoft.ManagedIdentity; do
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
