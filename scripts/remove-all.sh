#!/opt/homebrew/bin/bash
set -euo pipefail

# ── Resource groups to NEVER delete ──
SKIP_RGS=(
  "cloud-shell-storage-westus"
  # Add any other platform / shared RGs here
)

# ── Subscription-level deployment names to clean up ──
DEPLOY_NAMES=(
  "hubmain"
  "spokemain"
  "appsmain"
  "datamain"
  "hubdeployment"
)

# ── Helper: check if an RG is in the skip list ──
should_skip() {
  local rg="$1"
  for skip in "${SKIP_RGS[@]}"; do
    if [[ "$rg" == "$skip" ]]; then
      return 0
    fi
  done
  # Also skip any RG that starts with "DefaultResourceGroup-" or "cloud-shell-"
  if [[ "$rg" == DefaultResourceGroup-* || "$rg" == cloud-shell-* ]]; then
    return 0
  fi
  return 1
}

# ── Parse optional subscription list ──
subsParam=""
dryRun=false
for arg in "$@"; do
  if [[ "$arg" == subs=* ]]; then
    subsParam="${arg#subs=}"
  elif [[ "$arg" == "--dry-run" ]]; then
    dryRun=true
  fi
done
if [[ -n "$subsParam" ]]; then
  IFS=',' read -r -a subscriptions <<< "$subsParam"
else
  mapfile -t subscriptions < <(az account list --query "[?state=='Enabled'].id" -o tsv 2>/dev/null)
fi

echo "═══════════════════════════════════════════════════════"
echo "  Subscriptions: ${subscriptions[*]}"
echo "  Dry run: $dryRun"
echo "═══════════════════════════════════════════════════════"

# ── Build list of resource groups across all subscriptions ──
rg_list=()
for sub in "${subscriptions[@]}"; do
  echo "🔍 Listing resource groups in subscription: $sub"
  subs_rgs=$(az group list --subscription "$sub" --query "[].name" -o tsv)
  while IFS= read -r rg; do
    if [[ -n "$rg" ]]; then
      rg_list+=("$sub::$rg")
    fi
  done <<< "$subs_rgs"
done

if [[ ${#rg_list[@]} -eq 0 ]]; then
    echo "No resource groups found."
    exit 0
fi

# ── Filter out skipped RGs and display plan ──
delete_list=()
for entry in "${rg_list[@]}"; do
  rg="${entry##*::}"
  if should_skip "$rg"; then
    echo "⏭️  Skipping: $rg"
  else
    delete_list+=("$entry")
  fi
done

if [[ ${#delete_list[@]} -eq 0 ]]; then
    echo "All resource groups are in the skip list. Nothing to delete."
    exit 0
fi

echo ""
echo "🗑️  Resource groups to be deleted:"
for entry in "${delete_list[@]}"; do
  sub="${entry%%::*}"
  rg="${entry##*::}"
  echo "   - $rg  (sub: ${sub:0:8}...)"
done
echo ""

if [[ "$dryRun" == true ]]; then
  echo "🏁 Dry run complete. No resources were deleted."
  exit 0
fi

# ── Confirmation prompt (safety net) ──
read -r -p "⚠️  Proceed with deletion? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# ── Track RGs being deleted (for the wait loop) ──
tracked_rgs=()

# ── Phase 1: Remove locks and delete RGs ──
for entry in "${delete_list[@]}"; do
  sub="${entry%%::*}"
  rg="${entry##*::}"
  echo "🔓 Processing: $rg"

  # Remove resource locks
  locks=$(az lock list --subscription "$sub" --resource-group "$rg" --query "[].id" --output tsv 2>/dev/null || true)
  if [[ -n "$locks" ]]; then
      echo "   Removing locks from $rg..."
      while IFS= read -r lock; do
          az lock delete --ids "$lock" 2>/dev/null || true
      done <<< "$locks"
  fi

  # Record Key Vaults for post-delete purge
  echo "   Deleting resource group: $rg"
  az group delete --subscription "$sub" --name "$rg" --no-wait --yes &
  tracked_rgs+=("$entry")
done

# ── Phase 2: Delete subscription-level deployments ──
for sub in "${subscriptions[@]}"; do
  for deploy_name in "${DEPLOY_NAMES[@]}"; do
    if az deployment sub show --subscription "$sub" --name "$deploy_name" &>/dev/null; then
      echo "🧹 Deleting subscription deployment: $deploy_name in $sub"
      az deployment sub delete --subscription "$sub" --name "$deploy_name" --no-wait 2>/dev/null || true
    fi
  done
done

# ── Phase 3: Wait for RG deletions, then purge Key Vaults ──
timeout=600 # 10 min (large firewalls/gateways can take a while)
elapsed=0
echo ""
while [[ $elapsed -lt $timeout ]]; do
  still_remaining=()
  for entry in "${tracked_rgs[@]}"; do
    sub="${entry%%::*}"
    rg="${entry##*::}"
    # Check if the RG still exists
    if az group show --subscription "$sub" --name "$rg" &>/dev/null; then
      still_remaining+=("$entry")
    fi
  done

  if [[ ${#still_remaining[@]} -eq 0 ]]; then
    echo "✅ All resource groups have been deleted."
    break
  fi

  tracked_rgs=("${still_remaining[@]}")
  echo "⏳ Waiting... ($elapsed sec; ${#still_remaining[@]} remaining)"
  sleep 10
  ((elapsed += 10))
done

if [[ $elapsed -ge $timeout ]]; then
  echo "⚠️  Timeout reached. These RGs may still be deleting:"
  for entry in "${tracked_rgs[@]}"; do
    echo "   - ${entry##*::}"
  done
fi

# ── Phase 4: Purge soft-deleted Key Vaults ──
echo ""
echo "🔑 Checking for soft-deleted Key Vaults to purge..."
for sub in "${subscriptions[@]}"; do
  soft_deleted=$(az keyvault list-deleted --subscription "$sub" --query "[].name" -o tsv 2>/dev/null || true)
  if [[ -n "$soft_deleted" ]]; then
    while IFS= read -r kv; do
      echo "   Purging soft-deleted Key Vault: $kv"
      az keyvault purge --subscription "$sub" --name "$kv" --no-wait 2>/dev/null || true
    done <<< "$soft_deleted"
  fi
done

# ── Phase 5: Purge soft-deleted App Configuration stores (if any) ──
soft_appconfig=$(az appconfig list-deleted --query "[].name" -o tsv 2>/dev/null || true)
if [[ -n "$soft_appconfig" ]]; then
  echo "🧹 Purging soft-deleted App Configuration stores..."
  while IFS= read -r ac; do
    echo "   Purging: $ac"
    az appconfig purge --name "$ac" --yes 2>/dev/null || true
  done <<< "$soft_appconfig"
fi

echo ""
echo "🏁 Cleanup complete."