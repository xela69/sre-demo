#!/usr/bin/env bash
# =============================================================================
# enable_vpngw_peering.sh
#
# Post-deploy script — run AFTER hub is redeployed with deployVpnGw=true.
#
# What it does:
#   1. (Optional) Redeploys hub with deployVpnGw=true  -- skip w/ --skip-hub
#   2. Waits for VPN GW to reach Succeeded provisioning state
#   3. Patches each spoke VNet peering to useRemoteGateways=true via az CLI
#
# Usage:
#   ./enable_vpngw_peering.sh
#   ./enable_vpngw_peering.sh --skip-hub        # skip hub redeploy, just patch peerings
#   ./enable_vpngw_peering.sh --dry-run         # print actions without executing
#
# Prerequisites:
#   az login done, contributor on hub + spoke subscriptions
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Subscription IDs ──────────────────────────────────────────────────────────
HUB_SUB="ed70102f-f789-4d4e-ac00-074283844a0c"
APPS_SUB="86d55e1e-4ca9-4ddd-85df-2e7633d77534"
DATA_SUB="8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"

# ── Hub resources ─────────────────────────────────────────────────────────────
HUB_RG="hubRG"
HUB_VNET="hubRG-VNet"
VPN_GW_NAME="xelavpngw"
HUB_LOCATION="westus2"

# ── Spoke peerings to update  (vnet_rg|vnet_name|peering_name|subscription) ──
SPOKES=(
  "AppsRG|AppsRG-VNet|AppsRG-VNet-to-hubRG-VNet-Peering|$APPS_SUB"
  "DataRG|DataRG-VNet|DataRG-VNet-to-hubRG-VNet-Peering|$DATA_SUB"
)

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_HUB=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --skip-hub)  SKIP_HUB=true  ;;
    --dry-run)   DRY_RUN=true   ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

echo "============================================================"
echo " VPN GW + Peering enablement script"
echo " dry-run=$DRY_RUN  skip-hub=$SKIP_HUB"
echo "============================================================"

# ── Step 1: Redeploy hub with VPN GW ─────────────────────────────────────────
if [[ "$SKIP_HUB" == "false" ]]; then
  echo ""
  echo "[1/3] Redeploying hub with deployVpnGw=true (this takes 30-45 min)..."
  run az deployment sub create \
    --subscription "$HUB_SUB" \
    -l "$HUB_LOCATION" \
    --template-file "$REPO_ROOT/main/hub/hubmain.bicep" \
    --parameters \
      natPublicIP="$(curl -4 -s ifconfig.me)" \
      accessKey="$(cat "$REPO_ROOT/docs/pwd.txt")" \
      sshPublicKey="$(cat ~/.ssh/id_ed25519.pub)" \
      deployVpnGw=true
  echo "[1/3] Hub redeploy complete."
else
  echo "[1/3] Skipped hub redeploy (--skip-hub)."
fi

# ── Step 2: Wait for VPN GW to reach Succeeded ───────────────────────────────
echo ""
echo "[2/3] Waiting for VPN Gateway '$VPN_GW_NAME' to reach Succeeded state..."

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Would poll: az network vnet-gateway show -g $HUB_RG -n $VPN_GW_NAME --subscription $HUB_SUB"
else
  MAX_WAIT=60   # max 60 × 60s = 60 min
  COUNT=0
  while true; do
    PROV_STATE=$(az network vnet-gateway show \
      -g "$HUB_RG" -n "$VPN_GW_NAME" \
      --subscription "$HUB_SUB" \
      --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

    echo "  $(date +%H:%M:%S)  provisioningState=$PROV_STATE"

    if [[ "$PROV_STATE" == "Succeeded" ]]; then
      echo "[2/3] VPN Gateway is Succeeded."
      break
    elif [[ "$PROV_STATE" == "Failed" ]]; then
      echo "ERROR: VPN Gateway provisioning Failed. Check the portal." >&2
      exit 1
    fi

    COUNT=$((COUNT + 1))
    if [[ $COUNT -ge $MAX_WAIT ]]; then
      echo "ERROR: Timed out waiting for VPN Gateway after $((MAX_WAIT)) minutes." >&2
      exit 1
    fi
    sleep 60
  done
fi

# ── Step 3: Patch spoke peerings ─────────────────────────────────────────────
echo ""
echo "[3/3] Updating spoke peerings to useRemoteGateways=true..."

for spoke in "${SPOKES[@]}"; do
  IFS='|' read -r VNET_RG VNET_NAME PEERING_NAME SPOKE_SUB <<< "$spoke"

  echo "  Patching $SPOKE_SUB / $VNET_RG / $VNET_NAME / $PEERING_NAME"

  # Read current peering config so we preserve all existing properties
  PEERING_JSON=$(az network vnet peering show \
    --resource-group "$VNET_RG" \
    --vnet-name "$VNET_NAME" \
    --name "$PEERING_NAME" \
    --subscription "$SPOKE_SUB" \
    -o json 2>/dev/null || echo "{}")

  if [[ "$PEERING_JSON" == "{}" ]]; then
    echo "  WARNING: Peering '$PEERING_NAME' not found in $VNET_RG/$VNET_NAME — skipping."
    continue
  fi

  run az network vnet peering update \
    --resource-group "$VNET_RG" \
    --vnet-name "$VNET_NAME" \
    --name "$PEERING_NAME" \
    --subscription "$SPOKE_SUB" \
    --set useRemoteGateways=true

  echo "  Done: $PEERING_NAME"
done

echo ""
echo "============================================================"
echo " All done. Spoke peerings now use remote VPN GW."
echo " Next: wire TenantA LNG with hub VPN GW public IP."
echo ""
echo " Hub VPN GW public IP:"
if [[ "$DRY_RUN" == "false" ]]; then
  az network vnet-gateway show \
    -g "$HUB_RG" -n "$VPN_GW_NAME" \
    --subscription "$HUB_SUB" \
    --query "bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]" -o tsv 2>/dev/null \
    || az network public-ip list \
         --subscription "$HUB_SUB" -g "$HUB_RG" \
         --query "[?contains(name,'vpn')].ipAddress" -o tsv
fi
echo "============================================================"
