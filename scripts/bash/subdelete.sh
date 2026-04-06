#!/bin/bash

# Use positional arguments as subscription IDs, or default to current subscription
if [[ $# -gt 0 ]]; then
  subscriptions=("$@")
else
  currentSub=$(az account show --query id -o tsv)
  subscriptions=("$currentSub")
fi

# Build list of resource groups across all subscriptions
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

# If no resource groups are found, exit
if [[ ${#rg_list[@]} -eq 0 ]]; then
    echo "No resource groups found."
    exit 0
fi

echo "Resource groups to be deleted: ${rg_list[*]}"

# Loop through each resource group and delete it in parallel
for entry in "${rg_list[@]}"; do
  sub="${entry%%::*}"
  rg="${entry##*::}"
  if [[ "$rg" == "ImportantRG" ]]; then
    echo "Skipping resource group: $rg in subscription: $sub"
    continue
  fi
  echo "Deleting resource group: $rg in subscription: $sub"

  # Check for locks and remove them
  locks=$(az lock list --subscription "$sub" --resource-group "$rg" --query "[].id" --output tsv)
  if [[ -n "$locks" ]]; then
      echo "Removing locks from $rg..."
      for lock in $locks; do
          az lock delete --ids "$lock"
      done
  fi

  # Purge Key Vaults if any
  kvs=$(az keyvault list --subscription "$sub" --resource-group "$rg" --query "[].name" --output tsv)
  for kv in $kvs; do
      echo "Purging soft-deleted Key Vault: $kv"
      az keyvault purge --subscription "$sub" --name "$kv"
  done

  # Delete the resource group asynchronously
  az group delete --subscription "$sub" --name "$rg" --no-wait --yes &
done

# Delete subscription-level deployments for each subscription
DEPLOY_NAME="main"
for sub in "${subscriptions[@]}"; do
  if az deployment sub show --subscription "$sub" --name "$DEPLOY_NAME" &>/dev/null; then
    echo "Deleting subscription deployment: $DEPLOY_NAME in $sub"
    az deployment sub delete --subscription "$sub" --name "$DEPLOY_NAME"
  else
    echo "No subscription deployment named '$DEPLOY_NAME' found in $sub."
  fi
done

# Wait for deletions to complete (Max wait time: 5 minutes)
timeout=300 # 5 min
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
  total_remaining=0
  for sub in "${subscriptions[@]}"; do
    subs_rem=$(az group list --subscription "$sub" --query "[].name" -o tsv)
    # Count non-empty lines
    while IFS= read -r line; do
      [[ -n "$line" ]] && (( total_remaining++ ))
    done <<< "$subs_rem"
  done

  if (( total_remaining == 0 )); then
    echo "All resource groups have been deleted."
    exit 0
  fi

  echo "Waiting for resource groups to be deleted... ($elapsed sec; remaining: $total_remaining)"
  sleep 5
  ((elapsed += 5))
done
echo "Warning: Some resource groups may still be deleting. Check manually."