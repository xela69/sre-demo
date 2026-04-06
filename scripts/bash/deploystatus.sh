#!/opt/homebrew/bin/bash
# deploystatus.sh — Monitor Azure deployments across resource groups
# Usage: ./deploystatus.sh [--poll] [--all-subs] [subs=sub1,sub2]
#   --poll   Keep polling until all Running/Accepted deployments finish
#   --all-subs Scan all enabled subscriptions
#   subs=    Comma-separated subscription IDs (overrides --all-subs/current subscription)

set -euo pipefail

POLL=false
ALL_SUBS=false
POLL_INTERVAL=15

# ── Parse arguments ──
subsParam=""
for arg in "$@"; do
  case "$arg" in
    --poll) POLL=true ;;
    --all-subs) ALL_SUBS=true ;;
    subs=*) subsParam="${arg#subs=}" ;;
  esac
done

if [[ -n "$subsParam" ]]; then
  IFS=',' read -r -a subscriptions <<< "$subsParam"
elif $ALL_SUBS; then
  mapfile -t subscriptions < <(az account list --query "[?state=='Enabled'].id" -o tsv 2>/dev/null || true)
else
  current_sub=$(az account show --query id -o tsv 2>/dev/null || true)
  if [[ -n "$current_sub" ]]; then
    subscriptions=("$current_sub")
  else
    subscriptions=()
  fi
fi

if [[ ${#subscriptions[@]} -eq 0 ]]; then
  echo "⚠️  No subscriptions found."
  exit 1
fi

# ── Colours ──
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ── Helper: format seconds to Xm Ys ──
fmt_duration() {
  local secs=$1
  if (( secs < 0 )); then secs=0; fi
  printf '%dm %ds' $(( secs / 60 )) $(( secs % 60 ))
}

# ── Helper: elapsed time from Azure timestamp (UTC) ──
elapsed_from_ts() {
  local ts="$1"
  if [[ -z "$ts" || "$ts" == "None" ]]; then
    echo "n/a"
    return
  fi

  # Use python for reliable ISO8601 parsing across macOS/GNU environments.
  local elapsed_secs
  elapsed_secs=$(python3 -c '
import datetime, sys
ts = sys.argv[1]
try:
    # Azure typically returns UTC timestamps ending with Z.
    dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - dt).total_seconds()))
except Exception:
    print(-1)
' "$ts" 2>/dev/null || echo "-1")

  if [[ -z "$elapsed_secs" || "$elapsed_secs" == "-1" ]]; then
    echo "n/a"
    return
  fi

  fmt_duration "$elapsed_secs"
}

# ── Main loop ──
check_deployments() {
  local has_running=false

  echo -e "${CYAN}🔎 Scanning ${#subscriptions[@]} subscription(s) for deployment status...${NC}"

  # Accumulators for final summary
  succeeded_list=""
  failed_list=""
  running_list=""
  skipped_list=""

  for sub in "${subscriptions[@]}"; do
    subName=$(az account show --subscription "$sub" --query name -o tsv 2>/dev/null || echo "$sub")
    echo -e "${CYAN}   • Checking subscription: ${subName} (${sub})${NC}"
    sub_has_active=false
    sub_output=""

    rgs=($(az group list --subscription "$sub" --query "[].name" -o tsv 2>/dev/null | sort -u))
    if [[ ${#rgs[@]} -eq 0 ]]; then
      continue
    fi

    for rg in "${rgs[@]}"; do
      # Query deployments with timestamps and status in one call
      deployments=$(az deployment group list \
        --subscription "$sub" \
        --resource-group "$rg" \
        --query "[].{name:name, state:properties.provisioningState, ts:properties.timestamp, duration:properties.duration}" \
        -o tsv 2>/dev/null)

      if [[ -z "$deployments" ]]; then
        continue  # skip RGs with no deployments (don't clutter output)
      fi

      # Only print RG header if it has active (Running/Accepted/Failed) deployments
      if ! echo "$deployments" | awk -F$'\t' '{print $2}' | grep -qE '^(Running|Accepted|Failed)$'; then
        # All done — count successes but stay quiet
        while IFS=$'\t' read -r name state ts duration; do
          [[ "$state" == "Succeeded" ]] && succeeded_list+="      ${GREEN}✅ $name${NC}  in $rg"$'\n'
        done <<< "$deployments"
        continue
      fi

      rg_output="\n   ${BOLD}📦 $rg${NC}\n"

      while IFS=$'\t' read -r name state ts duration; do
        # Clean up duration (Azure returns ISO 8601 like PT1M23.456S)
        friendly_dur=""
        if [[ -n "$duration" && "$duration" != "None" ]]; then
          # Extract minutes and seconds from PT format
          local mins=0 secs=0
          if [[ "$duration" =~ ([0-9]+)M ]]; then mins=${BASH_REMATCH[1]}; fi
          if [[ "$duration" =~ ([0-9]+(\.[0-9]+)?)S ]]; then secs=${BASH_REMATCH[1]%%.*}; fi
          friendly_dur="${mins}m ${secs}s"
        fi

        case "$state" in
          Succeeded)
            succeeded_list+="      ${GREEN}✅ $name${NC}  in $rg  (${friendly_dur:-n/a})"$'\n'
            ;;  # count only — don't echo, RG was already filtered above
          Failed)
            rg_output+="      ${RED}❌ $name${NC}  (${friendly_dur:-n/a})"$'\n'
            # Fetch the failure reason
            error_msg=$(az deployment group show \
              --subscription "$sub" \
              --resource-group "$rg" \
              --name "$name" \
              --query "properties.error.{code:code, message:message, details:details[0].{code:code, message:message}}" \
              -o json 2>/dev/null || echo '{}')
            # Extract a concise error message
            err_code=$(echo "$error_msg" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null || echo "")
            err_detail=$(echo "$error_msg" | python3 -c "
import sys, json
d = json.load(sys.stdin)
detail = d.get('details', {})
if detail:
    msg = detail.get('message', '')
    # Nested JSON in message — try to extract inner message
    try:
        inner = json.loads(msg)
        print(inner.get('message', msg)[:200])
    except:
        print(msg[:200])
else:
    print(d.get('message', 'Unknown error')[:200])
" 2>/dev/null || echo "Unknown error")
            rg_output+="         ${RED}└─ ${err_code}: ${err_detail}${NC}"$'\n'
            failed_list+="      ${RED}❌ $name${NC}  in $rg  (${friendly_dur:-n/a})"$'\n'
            failed_list+="         ${RED}└─ ${err_code}: ${err_detail}${NC}"$'\n'
            ;;
          Running|Accepted)
            elapsed_lapse=$(elapsed_from_ts "$ts")
            rg_output+="      ${YELLOW}🔄 $name${NC}  ($state, elapsed: ${elapsed_lapse})"$'\n'
            running_list+="      ${YELLOW}🔄 $name${NC}  in $rg  ($state, elapsed: ${elapsed_lapse})"$'\n'
            has_running=true
            ;;
          *)
            rg_output+="      ⚪ $name  ($state)"$'\n'
            ;;
        esac
      done <<< "$deployments"

      sub_has_active=true
      sub_output+="$rg_output"
    done

    if $sub_has_active; then
      echo -e "\n${BOLD}📡 Subscription: ${CYAN}${subName}${NC} (${sub})"
      echo -e "$sub_output"
    fi
  done

  # ── Summary ──
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}📊 DEPLOYMENT SUMMARY${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"

  # Count totals
  s_count=$(echo -n "$succeeded_list" | grep -c '✅' 2>/dev/null || echo 0)
  f_count=$(echo -n "$failed_list" | grep -c '❌' 2>/dev/null || echo 0)
  r_count=$(echo -n "$running_list" | grep -c '🔄' 2>/dev/null || echo 0)

  echo -e "   ${GREEN}Succeeded: $s_count${NC}    ${RED}Failed: $f_count${NC}    ${YELLOW}Running: $r_count${NC}"
  echo ""

  if [[ -n "$failed_list" ]]; then
    echo -e "${RED}${BOLD}── Failed ──${NC}"
    echo -e "$failed_list"
  fi

  if [[ -n "$running_list" ]]; then
    echo -e "${YELLOW}${BOLD}── Still Running ──${NC}"
    echo -e "$running_list"
  fi

  if [[ -z "$succeeded_list" && -z "$failed_list" && -z "$running_list" ]]; then
    echo "   No deployments found."
  fi

  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"

  # Return whether anything is still running
  $has_running
}

# ── Execute ──
if $POLL; then
  echo -e "${CYAN}📡 Polling mode — refreshing every ${POLL_INTERVAL}s until all deployments complete.${NC}"
  echo -e "${CYAN}   Press Ctrl+C to stop.${NC}"
  while true; do
    echo ""
    echo -e "${BOLD}──────────────── $(date '+%Y-%m-%d %H:%M:%S') ────────────────${NC}"
    if ! check_deployments; then
      echo -e "\n${GREEN}${BOLD}🎉 All deployments finished.${NC}"
      break
    fi
    echo -e "\n${YELLOW}⏳ Refreshing in ${POLL_INTERVAL}s...${NC}"
    sleep "$POLL_INTERVAL"
  done
else
  check_deployments || true
fi