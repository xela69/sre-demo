#!/bin/bash

# === Required Inputs ===
SUBSCRIPTION_ID="your-subscription-id"
RESOURCE_GROUP="your-resource-group"
WORKSPACE_NAME="your-loganalytics-workspace-name"
FIREWALL_PUBLIC_IP=$(curl -4 -s ifconfig.me) # or set manually

# === Optional: Rule name (must match existing rule if updating) ===
RULE_NAME="AllowOnlyFirewall"

# === API Version for networkAccessControlRules ===
API_VERSION="2022-10-01-preview"

# === Build URL ===
URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/networkAccessControlRules/${RULE_NAME}?api-version=${API_VERSION}"

# === Define JSON Body ===
BODY=$(jq -n \
	--arg desc "Allow access only from Azure Firewall" \
	--arg action "Allow" \
	--arg ip "$FIREWALL_PUBLIC_IP" \
	'{ properties: { description: $desc, action: $action, matchIPv4Address: $ip } }')

# === Execute REST Call ===
az rest --method PUT --url "$URL" --body "$BODY"