#!/bin/bash

# Hub details
HUB_RG="CPS-NCUS-Infra"
HUB_VNET="NCUS-Infra-VNet"
HUB_SUB="8cbc59b1-7d9e-4cf1-8851-58fffe68fb79"

# Apps details
APPS_RG="CPS-NCUS-Apps"
APPS_VNET="CPS-NCUS-Apps-VNet"
APPS_SUB="86d55e1e-4ca9-4ddd-85df-2e7633d77534"

# Data details
DATA_RG="CPS-NCUS-Data"
DATA_VNET="CPS-NCUS-Data-VNet"
DATA_SUB="155abeb8-c0a9-4927-a455-986a03026829"

# Set to HUB subscription for hub-initiated peerings
az account set --subscription $HUB_SUB

HUB_VNET_ID=$(az network vnet show --resource-group $HUB_RG --name $HUB_VNET --query id -o tsv)
APPS_VNET_ID=$(az network vnet show --resource-group $APPS_RG --name $APPS_VNET --subscription $APPS_SUB --query id -o tsv)
DATA_VNET_ID=$(az network vnet show --resource-group $DATA_RG --name $DATA_VNET --subscription $DATA_SUB --query id -o tsv)

# Hub to Apps
az network vnet peering create \
  --name "hub-to-apps" \
  --resource-group $HUB_RG \
  --vnet-name $HUB_VNET \
  --remote-vnet $APPS_VNET_ID \
  --allow-vnet-access \
  --subscription $HUB_SUB

# Hub to Data
az network vnet peering create \
  --name "hub-to-data" \
  --resource-group $HUB_RG \
  --vnet-name $HUB_VNET \
  --remote-vnet $DATA_VNET_ID \
  --allow-vnet-access \
  --subscription $HUB_SUB