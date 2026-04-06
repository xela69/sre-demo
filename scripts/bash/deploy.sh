#!/bin/bash

# Parameters
ENVIRONMENT=$1  # dev or prod
LOCATION="eastus"  # can make this dynamic
FILE="parameters/${ENVIRONMENT}.parameters.json"

# Validate
az bicep build --file main.bicep || exit 1

# Deploy
az deployment sub create \
  --location $LOCATION \
  --template-file main.bicep \
  --parameters @$FILE