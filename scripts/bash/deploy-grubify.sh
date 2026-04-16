#!/bin/bash
# ── deploy-grubify.sh ────────────────────────────────────────────────────────
# Builds the Grubify sample app (API + Frontend), pushes images to the hub ACR,
# then redeploys the apps-spoke with deployGrubify=true so both container apps
# go live in AppsRG-ContainerApp (centralus, apps subscription).
#
# Prerequisites:
#   - az login (hub + apps subscriptions accessible)
#   - Docker running locally
#   - az acr build or local docker build + az acr login
#
# Usage:
#   bash scripts/bash/deploy-grubify.sh [--dry-run]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Config ───────────────────────────────────────────────────────────────────
HUB_SUB="ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9"
APPS_SUB="42021d44-97d2-47a1-8245-a77149dda4c3"
HUB_ACR_RG="hubRG-Acr"
HUB_MONITOR_RG="hubRG-Monitor"
APPS_LOCATION="centralus"
GRUBIFY_REPO="https://github.com/dm-chelupati/grubify.git"
GRUBIFY_DIR="/tmp/grubify-src"
API_IMAGE="grubify-api:latest"
FRONTEND_IMAGE="grubify-frontend:latest"

echo "═══════════════════════════════════════════════════════"
echo "  Grubify → sre-demo apps-spoke deploy"
echo "  DRY_RUN=${DRY_RUN}"
echo "═══════════════════════════════════════════════════════"

# ── 1. Resolve hub ACR name ───────────────────────────────────────────────────
echo ""
echo "▶ Resolving hub ACR..."
az account set --subscription "$HUB_SUB"
ACR_NAME=$(az acr list --resource-group "$HUB_ACR_RG" --query "[0].name" -o tsv)
ACR_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
echo "  ACR: ${ACR_NAME} (${ACR_SERVER})"

# ── 2. Resolve App Insights connection string from hub ────────────────────────
echo ""
echo "▶ Resolving App Insights connection string..."
APPI_CONN=$(az monitor app-insights component show \
  --resource-group "$HUB_MONITOR_RG" \
  --query "[0].connectionString" -o tsv 2>/dev/null || echo "")
if [[ -z "$APPI_CONN" ]]; then
  APPI_CONN=$(az resource list --resource-group "$HUB_MONITOR_RG" \
    --resource-type "Microsoft.Insights/components" \
    --query "[0].id" -o tsv | xargs -I{} az resource show --ids {} \
    --query "properties.ConnectionString" -o tsv 2>/dev/null || echo "")
fi
echo "  App Insights: ${APPI_CONN:0:40}..."

# ── 3. Clone Grubify source ───────────────────────────────────────────────────
echo ""
echo "▶ Cloning Grubify source..."
if [[ -d "$GRUBIFY_DIR" ]]; then
  echo "  Already cloned — pulling latest"
  git -C "$GRUBIFY_DIR" pull --ff-only
else
  git clone "$GRUBIFY_REPO" "$GRUBIFY_DIR"
fi

# ── 4. Build & push images via ACR Tasks (no local Docker required) ───────────
echo ""
echo "▶ Building and pushing images via az acr build (ACR Tasks)..."

if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [DRY RUN] Would run:"
  echo "    az acr build --registry ${ACR_NAME} --image ${API_IMAGE} ${GRUBIFY_DIR}/api"
  echo "    az acr build --registry ${ACR_NAME} --image ${FRONTEND_IMAGE} ${GRUBIFY_DIR}/frontend"
else
  echo "  Building grubify-api..."
  az acr build \
    --registry "$ACR_NAME" \
    --image "$API_IMAGE" \
    "${GRUBIFY_DIR}/api"

  echo "  Building grubify-frontend..."
  az acr build \
    --registry "$ACR_NAME" \
    --image "$FRONTEND_IMAGE" \
    "${GRUBIFY_DIR}/frontend"
fi

# ── 5. Redeploy apps-spoke with Grubify enabled ───────────────────────────────
echo ""
echo "▶ Deploying apps-spoke with deployGrubify=true..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NAT_IP=$(curl -4 -s ifconfig.me)
ACCESS_KEY=$(cat "${REPO_ROOT}/docs/pwd.txt")
SSH_PUB_KEY="$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null || echo 'ssh-rsa AAAA no-key')"

DEPLOY_CMD=(
  az deployment sub create
    --subscription "$APPS_SUB"
    -l "$APPS_LOCATION"
    --template-file "${REPO_ROOT}/main/apps-spoke/appsmain.bicep"
    --parameters
      natPublicIP="$NAT_IP"
      accessKey="$ACCESS_KEY"
      sshPublicKey="$SSH_PUB_KEY"
      deployGrubify=true
      acrLoginServer="$ACR_SERVER"
      grubifyApiImage="$API_IMAGE"
      grubifyFrontendImage="$FRONTEND_IMAGE"
      appInsightsConnectionString="$APPI_CONN"
)

if [[ "$DRY_RUN" == "true" ]]; then
  DEPLOY_CMD+=(--what-if)
  echo "  [DRY RUN] Running --what-if..."
fi

az account set --subscription "$APPS_SUB"
"${DEPLOY_CMD[@]}"

# ── 6. Print URLs ─────────────────────────────────────────────────────────────
echo ""
echo "▶ Resolving container app URLs..."
az account set --subscription "$APPS_SUB"
API_FQDN=$(az containerapp show \
  --name grubify-api \
  --resource-group AppsRG-ContainerApp \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "not yet deployed")
FE_FQDN=$(az containerapp show \
  --name grubify-frontend \
  --resource-group AppsRG-ContainerApp \
  --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || echo "not yet deployed")

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Grubify deployed"
echo "  API:      https://${API_FQDN}"
echo "  Frontend: https://${FE_FQDN}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Next: register the SRE agent against AppsRG-ContainerApp"
echo "  → sre.azure.com → Azure resources → Add resource group: AppsRG-ContainerApp"
