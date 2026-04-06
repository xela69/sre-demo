#!/bin/bash

# Set these based on your environment
KV_NAME="xelavaultskcw"
KV_RG="keyvaultRG"
CERT_NAME="xelaSslCert"
SUBSCRIPTION_ID="155abeb8-c0a9-4927-a455-986a03026829"

# Identities to test (replace with actual principalIds)
APP_IDENTITY_PRINCIPAL_ID="60362d2a-23b5-42d9-8ad0-80b1d5873b78"
WAF_IDENTITY_PRINCIPAL_ID="9626da72-e2b5-4110-ba42-3bb76f80b5ce"

# Function to test role assignment
test_rbac_access() {
  local PRINCIPAL_ID=$1
  local NAME=$2

  echo "🔎 Testing RBAC for $NAME ($PRINCIPAL_ID)..."

  az role assignment list \
    --assignee $PRINCIPAL_ID \
    --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$KV_RG/providers/Microsoft.KeyVault/vaults/$KV_NAME \
    --query "[?roleDefinitionName=='Key Vault Secrets User']" \
    --output table
}

# Function to test if cert secret can be read (assumes script is running as MI)
test_secret_read() {
  echo "🔐 Attempting to read certificate secret from Key Vault: $CERT_NAME"
  az keyvault secret show \
    --vault-name $KV_NAME \
    --name $CERT_NAME \
    --query "[id, contentType]" \
    --output table
}

echo "🔁 Validating Key Vault Access..."
test_rbac_access $APP_IDENTITY_PRINCIPAL_ID "App Service"
test_rbac_access $WAF_IDENTITY_PRINCIPAL_ID "WAF"

echo ""
echo "🔁 Testing secret access using current Azure identity..."
test_secret_read