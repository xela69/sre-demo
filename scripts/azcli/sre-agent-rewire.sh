#!/usr/bin/env bash
# =============================================================================
# sre-agent-rewire.sh
#
# After deleting and recreating the SRE agent at sre.azure.com, run this
# script to:
#   1. Read the new identity name + principalId (from arg or prompt)
#   2. Write them to docs/sre-agent-config.txt
#   3. Redeploy hubmain.bicep to place the CanNotDelete lock + ADX RBAC
#
# Usage:
#   ./scripts/azcli/sre-agent-rewire.sh
#   ./scripts/azcli/sre-agent-rewire.sh --dry-run
#
# Prerequisites:
#   - New SRE agent created at sre.azure.com (takes ~2-5 min)
#   - Note the new managed identity name from hubRG-Monitor in the portal
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HUB_SUB="ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9"
MONITOR_RG="hubRG-Monitor"
CONFIG_FILE="$REPO_ROOT/docs/sre-agent-config.txt"
DRY_RUN=false

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

echo "═══════════════════════════════════════════════════════"
echo "  SRE Agent Rewire"
echo "  Dry run: $DRY_RUN"
echo "═══════════════════════════════════════════════════════"

# ── Auto-discover the new identity (name may have changed) ──
MI_NAME=$(az identity list \
  --resource-group "$MONITOR_RG" \
  --subscription "$HUB_SUB" \
  --query "[?starts_with(name,'sre-demo-')].name" -o tsv)

if [[ -z "$MI_NAME" ]]; then
  echo "ERROR: No 'sre-demo-*' managed identity found in $MONITOR_RG."
  echo "       Create the agent at sre.azure.com first, then re-run."
  exit 1
fi

MI_PRINCIPAL=$(az identity show \
  --name "$MI_NAME" \
  --resource-group "$MONITOR_RG" \
  --subscription "$HUB_SUB" \
  --query principalId -o tsv)

echo "  Discovered identity : $MI_NAME"
echo "  New Principal ID    : $MI_PRINCIPAL"

# ── Update config snapshot ──
cat > "$CONFIG_FILE" <<EOF
sreAgentIdentityName=$MI_NAME
sreAgentPrincipalId=$MI_PRINCIPAL
EOF
echo "  Updated $CONFIG_FILE"

# ── Redeploy hub to wire the lock + ADX RBAC ──
ACCESS_KEY=$(cat "$REPO_ROOT/docs/pwd.txt")
NAT_IP=$(curl -4 -s ifconfig.me)
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)

echo ""
if $DRY_RUN; then
  echo "DRY RUN — would execute:"
  echo "  az deployment sub create \\"
  echo "    --subscription $HUB_SUB -l westus2 \\"
  echo "    --template-file ./main/hub/hubmain.bicep \\"
  echo "    --parameters natPublicIP=$NAT_IP \\"
  echo "                 sreAgentIdentityName=$MI_NAME \\"
  echo "                 sreAgentPrincipalId=$MI_PRINCIPAL \\"
  echo "                 accessKey=<from pwd.txt> \\"
  echo "                 sshPublicKey=<from ~/.ssh/id_ed25519.pub>"
else
  echo "Redeploying hub to apply CanNotDelete lock + ADX RBAC..."
  az deployment sub create \
    --subscription "$HUB_SUB" \
    -l westus2 \
    --template-file "$REPO_ROOT/main/hub/hubmain.bicep" \
    --parameters \
      natPublicIP="$NAT_IP" \
      accessKey="$ACCESS_KEY" \
      sshPublicKey="$SSH_KEY" \
      sreAgentIdentityName="$MI_NAME" \
      sreAgentPrincipalId="$MI_PRINCIPAL"
  echo ""
  echo "✅  Hub redeployed. ADX AllDatabasesViewer RBAC and identity lock are active."
  echo ""
  echo "Next manual steps (portal only — no API available):"
  echo "  1. sre.azure.com → Builder > Connectors → Add Azure Data Explorer connector"
  echo "     Cluster URI: https://xelaadxfhmo.westus2.kusto.windows.net"
  echo "     Database   : sredb"
  echo "  2. Builder > Connectors → re-add GitHub OAuth"
  echo "  3. Re-add Azure resource subscriptions (3 subs)"
  echo "  4. Re-create any runbooks, response plans, and scheduled tasks"
fi