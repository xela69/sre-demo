#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

WORKSPACE_RG="${1:-hubRG-Monitor}"
WORKSPACE_NAME="${2:-}"

HEALTH_QUERY_FILE="$DOCS_DIR/vm-insights-health.kql"
RAG_QUERY_FILE="$DOCS_DIR/vm-insights-rag-health.kql"

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing query file: $file_path" >&2
    exit 1
  fi
}

build_query() {
  local file_path="$1"
  grep -vE '^\s*//' "$file_path" | tr '\n' ' '
}

resolve_workspace_id() {
  if [[ -n "$WORKSPACE_NAME" ]]; then
    az monitor log-analytics workspace show \
      -g "$WORKSPACE_RG" \
      -n "$WORKSPACE_NAME" \
      --query customerId \
      -o tsv
  else
    az monitor log-analytics workspace list \
      -g "$WORKSPACE_RG" \
      --query "[0].customerId" \
      -o tsv
  fi
}

run_query() {
  local title="$1"
  local file_path="$2"
  local ws_id="$3"
  local query

  query="$(build_query "$file_path")"

  echo ""
  echo "== $title =="
  az monitor log-analytics query \
    -w "$ws_id" \
    --analytics-query "$query" \
    -o table
}

require_file "$HEALTH_QUERY_FILE"
require_file "$RAG_QUERY_FILE"

WS_ID="$(resolve_workspace_id)"

if [[ -z "$WS_ID" ]]; then
  echo "Unable to resolve Log Analytics workspace customerId in resource group: $WORKSPACE_RG" >&2
  exit 1
fi

echo "Using workspace customerId: $WS_ID"
run_query "VM Insights Detailed Health" "$HEALTH_QUERY_FILE" "$WS_ID"
run_query "VM Insights RAG Health" "$RAG_QUERY_FILE" "$WS_ID"
