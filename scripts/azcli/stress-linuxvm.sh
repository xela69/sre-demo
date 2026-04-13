#!/usr/bin/env bash
# =============================================================================
# stress-linuxvm.sh — Generate CPU / Memory / Disk load on AppsLinuxVM (Ubuntu)
#                     to produce metric data in Azure Monitor / VM Insights
#
# Usage:
#   ./stress-linuxvm.sh                      # all: CPU + memory + disk, 5 min
#   ./stress-linuxvm.sh --cpu                # CPU only
#   ./stress-linuxvm.sh --memory             # memory only
#   ./stress-linuxvm.sh --disk               # disk I/O only
#   ./stress-linuxvm.sh --duration 10        # run for 10 minutes
#   ./stress-linuxvm.sh --dry-run            # print payload, no exec
# =============================================================================
set -euo pipefail

APPS_SUB="42021d44-97d2-47a1-8245-a77149dda4c3"
VM_RG="AppsRG-VM"
VM_NAME_PREFIX="AppsLinuxVM"

DURATION=5
DO_CPU=false
DO_MEM=false
DO_DISK=false
DO_ALL=true
DRY_RUN=false

args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    --duration) DURATION="${args[$((i+1))]}"; i=$((i+2)) ;;
    --cpu)      DO_CPU=true;  DO_ALL=false; i=$((i+1)) ;;
    --memory)   DO_MEM=true;  DO_ALL=false; i=$((i+1)) ;;
    --disk)     DO_DISK=true; DO_ALL=false; i=$((i+1)) ;;
    --dry-run)  DRY_RUN=true; i=$((i+1)) ;;
    *)          i=$((i+1)) ;;
  esac
done

if [[ "$DO_ALL" == "true" ]]; then
  DO_CPU=true; DO_MEM=true; DO_DISK=true
fi

# ── Resolve the VM name dynamically (name contains a uniqueString hash) ───────
resolve_vm_name() {
  az account set --subscription "$APPS_SUB" 2>/dev/null
  local name
  name=$(az vm list -g "$VM_RG" \
    --query "[?starts_with(name,'${VM_NAME_PREFIX}')].name | [0]" \
    -o tsv 2>/dev/null)
  if [[ -z "$name" ]]; then
    echo "ERROR: No VM starting with '${VM_NAME_PREFIX}' found in RG '$VM_RG'" >&2
    exit 1
  fi
  echo "$name"
}

run_stress() {
  local vm_name="$1"
  local script="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] az vm run-command invoke -g $VM_RG --name $vm_name --command-id RunShellScript ..."
    echo "--- Shell payload ---"
    echo "$script"
    echo "---------------------"
  else
    az account set --subscription "$APPS_SUB"
    az vm run-command invoke \
      -g "$VM_RG" --name "$vm_name" \
      --command-id RunShellScript \
      --scripts "$script" \
      --query "value[0].message" -o tsv 2>&1
  fi
}

# ── Resolve name (skip az call in dry-run) ────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  VM_NAME="${VM_NAME_PREFIX}<hash>"
else
  VM_NAME="$(resolve_vm_name)"
fi

MODE_LABEL=""
[[ "$DO_CPU"  == "true" ]] && MODE_LABEL="${MODE_LABEL}cpu "
[[ "$DO_MEM"  == "true" ]] && MODE_LABEL="${MODE_LABEL}memory "
[[ "$DO_DISK" == "true" ]] && MODE_LABEL="${MODE_LABEL}disk"

echo "============================================================"
echo " Linux VM Stress — $VM_NAME"
echo " VM: $VM_RG/$VM_NAME  sub: $APPS_SUB"
echo " modes=[${MODE_LABEL}]  duration=${DURATION}m  dry-run=$DRY_RUN"
echo "============================================================"

# ── Build the remote shell script ─────────────────────────────────────────────
# stress-ng is installed if absent; all work happens inside the VM as root.
REMOTE_SCRIPT=""

# Install stress-ng (idempotent)
REMOTE_SCRIPT+='
export DEBIAN_FRONTEND=noninteractive
if ! command -v stress-ng &>/dev/null; then
    echo "[setup] Installing stress-ng..."
    apt-get update -qq && apt-get install -y -qq stress-ng
else
    echo "[setup] stress-ng already installed: $(stress-ng --version)"
fi
'

# Convert minutes to seconds for stress-ng --timeout
DURATION_SEC=$(( DURATION * 60 ))

# Build stress-ng flags
STRESS_FLAGS="--timeout ${DURATION_SEC}s --metrics-brief"

if [[ "$DO_CPU" == "true" ]]; then
  # --cpu 0 = one worker per logical CPU; --cpu-method matrixprod is FPU-heavy
  STRESS_FLAGS+=" --cpu 0 --cpu-method matrixprod"
fi

if [[ "$DO_MEM" == "true" ]]; then
  # Allocate 512 MB and repeatedly write/read to generate paging pressure
  STRESS_FLAGS+=" --vm 2 --vm-bytes 256M --vm-method all"
fi

if [[ "$DO_DISK" == "true" ]]; then
  # Sequential read/write to a temp file; also exercises page cache eviction
  STRESS_FLAGS+=" --io 2 --hdd 2 --hdd-bytes 512M"
fi

REMOTE_SCRIPT+="
echo \"[stress] Running: stress-ng $STRESS_FLAGS\"
stress-ng $STRESS_FLAGS
echo \"[stress] Complete.\"
"

# Post-run: print a quick system summary for the run-command output
REMOTE_SCRIPT+='
echo "--- Post-stress system snapshot ---"
echo "Uptime / load:  $(uptime)"
echo "Memory (free):  $(free -h | awk '"'"'/^Mem/{print $3"/"$2}'"'"')"
echo "Disk util (sda):$(iostat -d sda 1 1 2>/dev/null | awk '"'"'/^sda/{print "reads="$3"/s writes="$4"/s"}'"'"' || echo "n/a")"
echo "-----------------------------------"
'

echo ""
echo "[1/1] Launching stress on $VM_NAME (modes: ${MODE_LABEL}, ${DURATION}m)..."
run_stress "$VM_NAME" "$REMOTE_SCRIPT"

echo ""
echo "============================================================"
echo " Done. Metrics (% Processor Time, Available MBytes,"
echo " Disk Read/Write Bytes/sec) appear in Azure Monitor"
echo " / VM Insights Performance within ~1-2 minutes."
echo "============================================================"
