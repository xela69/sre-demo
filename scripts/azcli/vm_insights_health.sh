#!/usr/bin/env bash
# =============================================================================
# vm_insights_health.sh — VM Insights health check for hub and/or apps VMs
#
# Dynamically discovers VM names from Azure, injects them into the KQL queries,
# and runs both the detailed health and RAG (red/amber/green) checks.
#
# Usage:
#   ./vm_insights_health.sh                  # hub + apps VMs (default)
#   ./vm_insights_health.sh --hub-only       # hub VMs only
#   ./vm_insights_health.sh --apps-only      # apps VMs only
#   ./vm_insights_health.sh --lookback 12    # lookback window in hours (default 6)
#   ./vm_insights_health.sh --dry-run        # show resolved VMs + patched KQL, no exec
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

HEALTH_QUERY_FILE="$DOCS_DIR/vm-insights-health.kql"
RAG_QUERY_FILE="$DOCS_DIR/vm-insights-rag-health.kql"

# ── Subscription / resource group constants ───────────────────────────────────
HUB_SUB="ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9"
APPS_SUB="42021d44-97d2-47a1-8245-a77149dda4c3"

HUB_VM_RG="hubRG-VM"
HUB_MONITOR_RG="hubRG-Monitor"

APPS_VM_RG="AppsRG-VM"
APPS_SQL_RG="AppsRG-SQL"

# ── Defaults ──────────────────────────────────────────────────────────────────
SCOPE="both"    # hub | apps | both
LOOKBACK=6      # hours
DRY_RUN=false

args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    --hub-only)  SCOPE="hub";  i=$((i+1)) ;;
    --apps-only) SCOPE="apps"; i=$((i+1)) ;;
    --lookback)  LOOKBACK="${args[$((i+1))]}"; i=$((i+2)) ;;
    --dry-run)   DRY_RUN=true; i=$((i+1)) ;;
    *)           i=$((i+1)) ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
require_file() {
  [[ -f "$1" ]] || { echo "ERROR: Missing KQL file: $1" >&2; exit 1; }
}

list_vms_in_rg() {
  local sub="$1" rg="$2"
  az vm list -g "$rg" --subscription "$sub" \
    --query "[].name" -o tsv 2>/dev/null || true
}

# ── Discover VMs ──────────────────────────────────────────────────────────────
VM_NAMES=()

echo "============================================================"
echo " VM Insights Health Check"
echo " scope=$SCOPE  lookback=${LOOKBACK}h  dry-run=$DRY_RUN"
echo "============================================================"
echo ""
echo "Discovering VMs..."

if [[ "$SCOPE" == "hub" || "$SCOPE" == "both" ]]; then
  echo "  [hub]  sub=$HUB_SUB  rg=$HUB_VM_RG"
  while IFS= read -r name; do
    [[ -n "$name" ]] && VM_NAMES+=("$name") && echo "         + $name"
  done < <(list_vms_in_rg "$HUB_SUB" "$HUB_VM_RG")
fi

if [[ "$SCOPE" == "apps" || "$SCOPE" == "both" ]]; then
  echo "  [apps] sub=$APPS_SUB  rg=$APPS_VM_RG"
  while IFS= read -r name; do
    [[ -n "$name" ]] && VM_NAMES+=("$name") && echo "         + $name"
  done < <(list_vms_in_rg "$APPS_SUB" "$APPS_VM_RG")

  echo "  [apps] sub=$APPS_SUB  rg=$APPS_SQL_RG"
  while IFS= read -r name; do
    [[ -n "$name" ]] && VM_NAMES+=("$name") && echo "         + $name"
  done < <(list_vms_in_rg "$APPS_SUB" "$APPS_SQL_RG")
fi

if [[ ${#VM_NAMES[@]} -eq 0 ]]; then
  echo "ERROR: No VMs found for scope='$SCOPE'. Check subscription access." >&2
  exit 1
fi

echo ""
echo "Total VMs: ${#VM_NAMES[@]}"

# ── Build KQL VM list string ──────────────────────────────────────────────────
# Produces: "vmA", "vmB", "vmC"  (used in dynamic([...]) and datatable)
KQL_VM_CSV=$(printf '"%s", ' "${VM_NAMES[@]}" | sed 's/, $//')

# ── Patch KQL content in-memory via Python ────────────────────────────────────
# Updates:  1) let lookback
#           2) let vmList = dynamic([...])   (single-line form)
#           3) let vmList = datatable(...)    (multi-line form)
#           4) print Computer = "x" | union (print ...)  →  datatable(...)
patch_query() {
  local file="$1"
  python3 - "$file" "$KQL_VM_CSV" "${LOOKBACK}h" << 'PYEOF'
import sys, re

file_path, vm_csv, lookback = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(file_path).read()

# 1. Strip KQL single-line comments
content = re.sub(r'^\s*//.*$', '', content, flags=re.MULTILINE)

# 2. Replace lookback value
content = re.sub(
    r'let lookback\s*=\s*\d+h\s*;',
    f'let lookback = {lookback};',
    content
)

# 3. Replace vmList = dynamic([...]) — single-line form
content = re.sub(
    r'let vmList\s*=\s*dynamic\(\[.*?\]\)\s*;',
    f'let vmList = dynamic([{vm_csv}]);',
    content
)

# 4. Replace vmList = datatable(Computer:string) [...] — multi-line form
# Keep as datatable (NOT dynamic) — downstream queries pipe it: vmList | join ...
content = re.sub(
    r'let vmList\s*=\s*datatable\s*\(\s*Computer\s*:\s*string\s*\)\s*\[.*?\]\s*;',
    f'let vmList = datatable(Computer:string)[{vm_csv}];',
    content,
    flags=re.DOTALL
)

# 5. Replace hardcoded  print Computer = "x" | union (print Computer = "y") ...
#    with a datatable(...) so it auto-scales to any number of VMs
content = re.sub(
    r'print\s+Computer\s*=\s*"[^"]+"\s*(?:\|\s*union\s*\(\s*print\s+Computer\s*=\s*"[^"]+"\s*\)\s*)*',
    f'datatable(Computer:string)[{vm_csv}]\n',
    content
)

# Clean up excessive blank lines
content = re.sub(r'\n{3,}', '\n\n', content)
print(content.strip())
PYEOF
}

# ── Resolve Log Analytics workspace (always in hub subscription) ──────────────
resolve_workspace_id() {
  az account set --subscription "$HUB_SUB" 2>/dev/null
  az monitor log-analytics workspace list \
    -g "$HUB_MONITOR_RG" \
    --subscription "$HUB_SUB" \
    --query "[0].customerId" -o tsv 2>/dev/null
}

run_query() {
  local title="$1"
  local kql="$2"
  local ws_id="$3"

  echo ""
  echo "== $title =="

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] KQL payload:"
    echo "$kql"
    return
  fi

  az monitor log-analytics query \
    -w "$ws_id" \
    --analytics-query "$kql" \
    -o table 2>&1 || echo "(no results or query error — check that VMs are sending heartbeats)"
}

require_file "$HEALTH_QUERY_FILE"
require_file "$RAG_QUERY_FILE"

# ── Resolve workspace ─────────────────────────────────────────────────────────
echo ""
echo "Resolving Log Analytics workspace in $HUB_MONITOR_RG..."
WS_ID="$(resolve_workspace_id)"

if [[ -z "$WS_ID" ]]; then
  echo "ERROR: Could not resolve workspace customerId in $HUB_MONITOR_RG (sub: $HUB_SUB)" >&2
  exit 1
fi

echo "Workspace ID: $WS_ID"

# ── Patch and run both queries ────────────────────────────────────────────────
HEALTH_KQL="$(patch_query "$HEALTH_QUERY_FILE")"
RAG_KQL="$(patch_query "$RAG_QUERY_FILE")"

run_query "VM Insights Detailed Health  [scope=$SCOPE  lookback=${LOOKBACK}h]" \
  "$HEALTH_KQL" "$WS_ID"

run_query "VM Insights RAG Health Summary  [scope=$SCOPE  lookback=${LOOKBACK}h]" \
  "$RAG_KQL" "$WS_ID"

echo ""
echo "============================================================"
echo " Done."
echo "============================================================"
