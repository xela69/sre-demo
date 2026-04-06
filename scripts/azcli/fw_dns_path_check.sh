#!/usr/bin/env bash
set -euo pipefail

VM_RG="${VM_RG:-hubRG-VM}"
VM_NAME="${VM_NAME:-LinuxVMpu54}"
FW_IP="${FW_IP:-10.50.4.4}"
PUBLIC_DNS_IP="${PUBLIC_DNS_IP:-8.8.8.8}"
WORKSPACE_RG="${WORKSPACE_RG:-hubRG-Monitor}"
WORKSPACE_NAME="${WORKSPACE_NAME:-xelaLogsfhmo}"
LOOKBACK="${LOOKBACK:-30m}"

echo "[1/3] Run DNS path tests from VM $VM_RG/$VM_NAME"
RUN_CMD_OUTPUT="$(az vm run-command invoke \
  -g "$VM_RG" \
  -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "set -e; echo 'TEST1: direct DNS to ${PUBLIC_DNS_IP}'; timeout 8 nslookup github.com ${PUBLIC_DNS_IP} || true; echo '---'; echo 'TEST2: DNS via firewall ${FW_IP}'; timeout 8 nslookup github.com ${FW_IP} || true" \
  --query "value[0].message" -o tsv)"

echo "$RUN_CMD_OUTPUT"

DIRECT_STATUS="UNKNOWN"
FW_STATUS="UNKNOWN"

if echo "$RUN_CMD_OUTPUT" | grep -qiE "communications error|timed out"; then
  DIRECT_STATUS="BLOCKED_OR_TIMED_OUT"
else
  DIRECT_STATUS="NOT_BLOCKED"
fi

if echo "$RUN_CMD_OUTPUT" | grep -qi "Server:[[:space:]]*${FW_IP}" && echo "$RUN_CMD_OUTPUT" | grep -qi "Non-authoritative answer"; then
  FW_STATUS="OK"
else
  FW_STATUS="FAILED"
fi

echo ""
echo "[2/3] Verify firewall DNS query logs in Log Analytics (${WORKSPACE_RG}/${WORKSPACE_NAME})"
WS_ID="$(az monitor log-analytics workspace show -g "$WORKSPACE_RG" -n "$WORKSPACE_NAME" --query customerId -o tsv)"

az monitor log-analytics query \
  -w "$WS_ID" \
  --analytics-query "AzureDiagnostics | where TimeGenerated > ago(${LOOKBACK}) | where Category == 'AZFWDnsQuery' | where SourceIP == '10.50.0.5' | where QueryName_s has 'github.com' | project TimeGenerated, SourceIP, QueryName_s, ResponseCode_s, Protocol_s | sort by TimeGenerated desc | take 5" \
  -o table

echo ""
echo "[3/3] Summary"
echo "- Direct DNS to ${PUBLIC_DNS_IP}: ${DIRECT_STATUS}"
echo "- DNS via firewall ${FW_IP}: ${FW_STATUS}"

if [[ "$DIRECT_STATUS" == "BLOCKED_OR_TIMED_OUT" && "$FW_STATUS" == "OK" ]]; then
  echo "Result: PASS"
  exit 0
fi

echo "Result: CHECK_MANUALLY"
exit 1
