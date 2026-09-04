#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TENANTB_SUBSCRIPTION="${TENANTB_SUBSCRIPTION:-ed70102f-f789-4d4e-ac00-074283844a0c}"
MCAPS_SUBSCRIPTION="${MCAPS_SUBSCRIPTION:-ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9}"
MCAPS_TENANT_ID="e2703bc7-74fd-40a0-8d0b-761571d44939"
LOCATION="${LOCATION:-westus2}"
# BYOL uses the free Marketplace plan and runs unlicensed in evaluation mode (no timer) on vsCode_Subs. PAYG requires a payment instrument (not available on vsCode_Subs).
LICENSE_MODEL="${LICENSE_MODEL:-BYOL}"

: "${FORTIGATE_ADMIN_PASSWORD:?Set FORTIGATE_ADMIN_PASSWORD for validation.}"
: "${VPN_SHARED_KEY:?Set VPN_SHARED_KEY for validation.}"
: "${MCAPS_ACCESS_KEY:?Set MCAPS_ACCESS_KEY for the existing hub secure inputs.}"

SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
if [[ ! -r "$SSH_PUBLIC_KEY_FILE" ]]; then
  echo "ERROR: SSH public key not readable: $SSH_PUBLIC_KEY_FILE" >&2
  exit 1
fi

NAT_PUBLIC_IP="${NAT_PUBLIC_IP:-$(curl -4 --fail --silent https://ifconfig.me)}"
TENANTB_FORTIGATE_PUBLIC_IP="${TENANTB_FORTIGATE_PUBLIC_IP:-192.0.2.10}"
if [[ "$TENANTB_FORTIGATE_PUBLIC_IP" == "192.0.2.10" ]]; then
  echo "WARNING: using documentation-only TenantB peer 192.0.2.10 for MCAPS preview."
  echo "Set TENANTB_FORTIGATE_PUBLIC_IP to the deployed FortiGate static public IP before deployment."
fi

tenantb_tenant_id="$(az account show --subscription "$TENANTB_SUBSCRIPTION" --query tenantId -o tsv 2>/dev/null || true)"
if [[ -z "$tenantb_tenant_id" ]]; then
  echo "ERROR: TenantB subscription is not available in the Azure CLI cache." >&2
  echo "Run: az login --tenant xelatech.net" >&2
  exit 1
fi
if [[ "$tenantb_tenant_id" == "$MCAPS_TENANT_ID" ]]; then
  echo "ERROR: TenantB subscription resolved to the MCAPS tenant." >&2
  exit 1
fi

mcaps_tenant_id="$(az account show --subscription "$MCAPS_SUBSCRIPTION" --query tenantId -o tsv 2>/dev/null || true)"
if [[ "$mcaps_tenant_id" != "$MCAPS_TENANT_ID" ]]; then
  echo "ERROR: MCAPS subscription is unavailable or resolved to the wrong tenant." >&2
  exit 1
fi

echo "Compiling TenantB and MCAPS deployment roots..."
az bicep build --file "$REPO_ROOT/main/tenantb/tenantbmain.bicep" --stdout >/dev/null
az bicep build --file "$REPO_ROOT/main/hub/hubmain.bicep" --stdout >/dev/null

echo "Validating TenantB subscription deployment..."
az deployment sub validate \
  --name tenantb-validation \
  --subscription "$TENANTB_SUBSCRIPTION" \
  --location "$LOCATION" \
  --template-file "$REPO_ROOT/main/tenantb/tenantbmain.bicep" \
  --parameters @"$REPO_ROOT/main/tenantb/tenantb.parameters.json" \
               adminPassword="$FORTIGATE_ADMIN_PASSWORD" \
               licenseModel="$LICENSE_MODEL" \
  --only-show-errors >/dev/null

echo "Running TenantB what-if..."
az deployment sub what-if \
  --name tenantb-whatif \
  --subscription "$TENANTB_SUBSCRIPTION" \
  --location "$LOCATION" \
  --template-file "$REPO_ROOT/main/tenantb/tenantbmain.bicep" \
  --parameters @"$REPO_ROOT/main/tenantb/tenantb.parameters.json" \
               adminPassword="$FORTIGATE_ADMIN_PASSWORD" \
               licenseModel="$LICENSE_MODEL" \
  --result-format ResourceIdOnly

echo "Validating MCAPS hub deployment..."
az deployment sub validate \
  --name mcaps-hub-validation \
  --subscription "$MCAPS_SUBSCRIPTION" \
  --location "$LOCATION" \
  --template-file "$REPO_ROOT/main/hub/hubmain.bicep" \
  --parameters @"$REPO_ROOT/main/hub/hub.parameters.json" \
               tenantBFortigatePublicIp="$TENANTB_FORTIGATE_PUBLIC_IP" \
               vpnSharedKey="$VPN_SHARED_KEY" \
               natPublicIP="$NAT_PUBLIC_IP" \
               accessKey="$MCAPS_ACCESS_KEY" \
               sshPublicKey="$(<"$SSH_PUBLIC_KEY_FILE")" \
  --only-show-errors >/dev/null

echo "Running MCAPS hub what-if..."
az deployment sub what-if \
  --name mcaps-hub-whatif \
  --subscription "$MCAPS_SUBSCRIPTION" \
  --location "$LOCATION" \
  --template-file "$REPO_ROOT/main/hub/hubmain.bicep" \
  --parameters @"$REPO_ROOT/main/hub/hub.parameters.json" \
               tenantBFortigatePublicIp="$TENANTB_FORTIGATE_PUBLIC_IP" \
               vpnSharedKey="$VPN_SHARED_KEY" \
               natPublicIP="$NAT_PUBLIC_IP" \
               accessKey="$MCAPS_ACCESS_KEY" \
               sshPublicKey="$(<"$SSH_PUBLIC_KEY_FILE")" \
  --result-format ResourceIdOnly

echo "TenantB and MCAPS validation completed. No resources were deployed."