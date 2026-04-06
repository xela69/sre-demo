#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HUB_DIR="$REPO_ROOT/alz/hub"

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
LOCATION="${LOCATION:-westus2}"
PARAM_FILE="${PARAM_FILE:-$HUB_DIR/hub.parameters.json}"
FW_RG="${FW_RG:-hubRG}"
FW_NAME="${FW_NAME:-xelaAzFirewall}"
DEPLOY_NAME_PREFIX="${DEPLOY_NAME_PREFIX:-hub-fwvpn}"
MODE="${MODE:-both}" # pass1 | pass2 | both

NAT_PUBLIC_IP="${NAT_PUBLIC_IP:-$(curl -4 -s ifconfig.me)}"
ACCESS_KEY="${ACCESS_KEY:-$(cat "$REPO_ROOT/docs/pwd.txt")}" 
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$(cat ~/.ssh/id_ed25519.pub)}"

first_deploy_name="${DEPLOY_NAME_PREFIX}-pass1-$(date +%Y%m%d%H%M%S)"
second_deploy_name="${DEPLOY_NAME_PREFIX}-pass2-$(date +%Y%m%d%H%M%S)"

cd "$HUB_DIR"

if [[ "$MODE" != "pass1" && "$MODE" != "pass2" && "$MODE" != "both" ]]; then
  echo "Invalid MODE: $MODE (expected pass1, pass2, or both)" >&2
  exit 1
fi

if [[ "$MODE" == "pass1" || "$MODE" == "both" ]]; then
  echo "[1/4] Pass 1 deploy (build FW + VPN and base wiring)"
  az deployment sub create \
    --name "$first_deploy_name" \
    --subscription "$SUBSCRIPTION_ID" \
    --location "$LOCATION" \
    --template-file ./hubmain.bicep \
    --parameters "$PARAM_FILE" \
    natPublicIP="$NAT_PUBLIC_IP" \
    accessKey="$ACCESS_KEY" \
    sshPublicKey="$SSH_PUBLIC_KEY" \
    deployFirewall=true \
    deployVpnGw=true
fi

echo "[2/4] Read actual firewall private IP from Azure"
FW_PRIVATE_IP="$(az network firewall show -g "$FW_RG" -n "$FW_NAME" --query "ipConfigurations[0].privateIPAddress" -o tsv)"

if [[ -z "$FW_PRIVATE_IP" ]]; then
  echo "Could not resolve Azure Firewall private IP from $FW_RG/$FW_NAME" >&2
  exit 1
fi

echo "Resolved firewall private IP: $FW_PRIVATE_IP"

if [[ "$MODE" == "pass2" || "$MODE" == "both" ]]; then
  echo "[3/4] Pass 2 deploy (reconcile VNet DNS + UDR next hop with real FW IP)"
  az deployment sub create \
    --name "$second_deploy_name" \
    --subscription "$SUBSCRIPTION_ID" \
    --location "$LOCATION" \
    --template-file ./hubmain.bicep \
    --parameters "$PARAM_FILE" \
    natPublicIP="$NAT_PUBLIC_IP" \
    accessKey="$ACCESS_KEY" \
    sshPublicKey="$SSH_PUBLIC_KEY" \
    deployFirewall=true \
    deployVpnGw=true \
    firewallPrivateIP="$FW_PRIVATE_IP"
fi

echo "[4/4] Verify network wiring"
az network vnet show -g "$FW_RG" -n hubRG-VNet --query "{dnsServers:dhcpOptions.dnsServers}" -o table
az network route-table route show -g "$FW_RG" --route-table-name hubRouteTable -n hubRouteTable-to-hubAzFirewall --query "{nextHopType:nextHopType,nextHopIpAddress:nextHopIpAddress,addressPrefix:addressPrefix}" -o table

echo "Completed. FW/VPN deployed and hub DNS/UDR reconciled to firewall private IP: $FW_PRIVATE_IP"
