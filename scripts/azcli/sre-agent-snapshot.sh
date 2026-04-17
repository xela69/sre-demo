#!/usr/bin/env bash
# =============================================================================
# sre-agent-snapshot.sh
#
# Captures the current SRE agent managed identity name + principalId
# and writes them to docs/sre-agent-config.txt for recovery use.
#
# Run BEFORE deleting the SRE agent from sre.azure.com.
#
# Usage:
#   ./scripts/azcli/sre-agent-snapshot.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HUB_SUB="ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9"
MONITOR_RG="hubRG-Monitor"
CONFIG_FILE="$REPO_ROOT/docs/sre-agent-config.txt"

echo "═══════════════════════════════════════════════════════"
echo "  SRE Agent Snapshot"
echo "  Subscription : $HUB_SUB"
echo "  Resource Group: $MONITOR_RG"
echo "═══════════════════════════════════════════════════════"

# Find the managed identity created by the SRE portal (name starts with 'sre-demo-')
MI_NAME=$(az identity list \
  --resource-group "$MONITOR_RG" \
  --subscription "$HUB_SUB" \
  --query "[?starts_with(name,'sre-demo-')].name" -o tsv)

if [[ -z "$MI_NAME" ]]; then
  echo "ERROR: No 'sre-demo-*' managed identity found in $MONITOR_RG."
  echo "       Has the SRE agent been created at sre.azure.com yet?"
  exit 1
fi

MI_PRINCIPAL=$(az identity show \
  --name "$MI_NAME" \
  --resource-group "$MONITOR_RG" \
  --subscription "$HUB_SUB" \
  --query principalId -o tsv)

echo "  Identity Name : $MI_NAME"
echo "  Principal ID  : $MI_PRINCIPAL"

cat > "$CONFIG_FILE" <<EOF
sreAgentIdentityName=$MI_NAME
sreAgentPrincipalId=$MI_PRINCIPAL
EOF

echo ""
echo "✅  Saved to $CONFIG_FILE"
echo "    Keep this file safe — you need it to rewire ADX after recreation."