#!/bin/bash

# --- Define subscriptions, resource groups, and locations ---
# List of subscription IDs (order matters!)
subs=(
  "155abeb8-c0a9-4927-a455-986a03026829" # Hub subs
  "86d55e1e-4ca9-4ddd-85df-2e7633d77534" # Apps subs
  "8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"  # Datacenter Subs
  "8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"
  "8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"
  "8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"
)

# VNet Resource Groups and locations (must match the order of 'subs')
vnetRGs=(
  "CPS-Hub"
  "CPS-Apps"
  "CPS-Data"
  "CPS-Dev"  # DC
  "CPS-Uat" # DC
  "CPS-DC"  # Datacenter_sub
)
vnetLocations=(
  "centralus"
  "northcentralus"
  "northcentralus"
  "centralus"
  "centralus"
  "centralus"
)

# VM Resource Groups and locations (customize as needed; order must match 'subs')
vmRGs=(
  "CPS-Hub-VM"
  "CPS-Apps-VM"
  "CPS-Data-VM"
  "CPS-Dev-VM"
  "CPS-Uat-VM"
  "CPS-DC-VM"

)
vmLocations=(
  "centralus"
  "northcentralus"
  "northcentralus"
  "centralus"
  "centralus"
  "centralus"
)
# --- Create VNet Resource Groups ---
for i in "${!subs[@]}"; do
  az group create \
    --name "${vnetRGs[$i]}" \
    --location "${vnetLocations[$i]}" \
    --subscription "${subs[$i]}"
done

# --- Create VM Resource Groups ---
for i in "${!subs[@]}"; do
  az group create \
    --name "${vmRGs[$i]}" \
    --location "${vmLocations[$i]}" \
    --subscription "${subs[$i]}"
done
# List all resource groups in the subs
for sub in $(az account list --query "[].id" -o tsv); do
  echo "Resource Groups in subscription: $sub"
  az group list --subscription $sub --output table
  echo ""
done