#!/usr/bin/env bash
# =============================================================================
# stress-appsvm.sh — Generate CPU / Memory / Disk load on AppsVM (Windows 2022)
#                    to produce metric data visible in Azure Monitor / VM Insights
#
# Usage:
#   ./stress-appsvm.sh                       # all: CPU + memory + disk, 5 min
#   ./stress-appsvm.sh --cpu                 # CPU only
#   ./stress-appsvm.sh --memory              # memory only
#   ./stress-appsvm.sh --disk                # disk I/O only
#   ./stress-appsvm.sh --duration 10         # run for 10 minutes
#   ./stress-appsvm.sh --dry-run             # print payload, no exec
# =============================================================================
set -euo pipefail

APPS_SUB="42021d44-97d2-47a1-8245-a77149dda4c3"
VM_RG="AppsRG-VM"
VM_NAME="AppsVM"

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
    --duration) DURATION="${args[$((i+1))]}"; DO_ALL=false; i=$((i+2)) ;;
    --cpu)      DO_CPU=true;  DO_ALL=false; i=$((i+1)) ;;
    --memory)   DO_MEM=true;  DO_ALL=false; i=$((i+1)) ;;
    --disk)     DO_DISK=true; DO_ALL=false; i=$((i+1)) ;;
    --dry-run)  DRY_RUN=true; i=$((i+1)) ;;
    *)          i=$((i+1)) ;;
  esac
done

# --duration alone keeps DO_ALL=true; explicit resource flags override it
if [[ "$DO_ALL" == "true" ]]; then
  DO_CPU=true; DO_MEM=true; DO_DISK=true
fi

run_stress() {
  local ps1="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] az vm run-command invoke -g $VM_RG --name $VM_NAME --command-id RunPowerShellScript ..."
    echo "--- PowerShell payload ---"
    cat "$ps1"
    echo "--------------------------"
  else
    az account set --subscription "$APPS_SUB"
    az vm run-command invoke \
      -g "$VM_RG" --name "$VM_NAME" \
      --command-id RunPowerShellScript \
      --scripts "@$ps1" \
      --query "value[0].message" -o tsv 2>&1
  fi
}

MODE_LABEL=""
[[ "$DO_CPU"  == "true" ]] && MODE_LABEL="${MODE_LABEL}cpu "
[[ "$DO_MEM"  == "true" ]] && MODE_LABEL="${MODE_LABEL}memory "
[[ "$DO_DISK" == "true" ]] && MODE_LABEL="${MODE_LABEL}disk"

echo "============================================================"
echo " VM Stress — AppsVM (Windows 2022)"
echo " VM: $VM_RG/$VM_NAME  sub: $APPS_SUB"
echo " modes=[${MODE_LABEL}]  duration=${DURATION}m  dry-run=$DRY_RUN"
echo "============================================================"

STRESS_PS1=$(mktemp /tmp/stress-vm-XXXXXX.ps1)
trap 'rm -f "$STRESS_PS1"' EXIT

# ── Build PowerShell payload dynamically ──────────────────────────────────────
cat > "$STRESS_PS1" << PSEOF
\$durationMinutes = $DURATION
\$endTime         = (Get-Date).AddMinutes(\$durationMinutes)
\$logicalCores    = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
\$jobs            = @()

Write-Host "=== VM Stress starting: $MODE_LABEL for \$durationMinutes minute(s) ==="
Write-Host "    Logical cores: \$logicalCores  End time: \$endTime"
PSEOF

# ── CPU block ─────────────────────────────────────────────────────────────────
if [[ "$DO_CPU" == "true" ]]; then
cat >> "$STRESS_PS1" << 'PSEOF'

Write-Host "[CPU] Launching 1 worker per logical core..."
$jobs += 1..$logicalCores | ForEach-Object {
    $workerIdx = $_
    Start-Job -ScriptBlock {
        param($end, $idx)
        $iter = 0
        while ((Get-Date) -lt $end) {
            # Math-intensive loop — keeps FPU busy without OS sleep
            for ($j = 0; $j -lt 50000; $j++) {
                [Math]::Sqrt([Math]::PI * $j) | Out-Null
            }
            $iter++
        }
        "CPU worker $idx done — $iter loop-sets"
    } -ArgumentList $endTime, $workerIdx
}
PSEOF
fi

# ── Memory block ──────────────────────────────────────────────────────────────
if [[ "$DO_MEM" == "true" ]]; then
cat >> "$STRESS_PS1" << 'PSEOF'

Write-Host "[MEM] Allocating and touching 512 MB in a worker..."
$jobs += Start-Job -ScriptBlock {
    param($end)
    $chunkMB  = 512
    $buf      = New-Object byte[] ($chunkMB * 1MB)
    $iter     = 0
    while ((Get-Date) -lt $end) {
        # Touch every 4 KB page to keep it resident and generate page faults
        for ($i = 0; $i -lt $buf.Length; $i += 4096) {
            $buf[$i] = [byte]($iter % 256)
        }
        $iter++
    }
    "MEM worker done — $iter passes over ${chunkMB} MB"
} -ArgumentList $endTime
PSEOF
fi

# ── Disk block ────────────────────────────────────────────────────────────────
if [[ "$DO_DISK" == "true" ]]; then
cat >> "$STRESS_PS1" << 'PSEOF'

Write-Host "[DISK] Starting sequential write/read worker on C:\..."
$jobs += Start-Job -ScriptBlock {
    param($end)
    $tmpFile  = [System.IO.Path]::GetTempFileName()
    $chunkMB  = 64
    $buf      = New-Object byte[] ($chunkMB * 1MB)
    [System.Random]::new().NextBytes($buf)
    $writeOps = 0; $readOps = 0
    try {
        while ((Get-Date) -lt $end) {
            # Write
            [System.IO.File]::WriteAllBytes($tmpFile, $buf)
            $writeOps++
            # Read back to generate read I/O
            $read = [System.IO.File]::ReadAllBytes($tmpFile)
            $readOps++
        }
    } finally {
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    }
    "DISK worker done — writes=$writeOps reads=$readOps (${chunkMB} MB chunks)"
} -ArgumentList $endTime
PSEOF
fi

# ── Wait and collect ──────────────────────────────────────────────────────────
cat >> "$STRESS_PS1" << 'PSEOF'

Write-Host "Workers running — waiting for completion..."
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

Write-Host "=== Results ==="
$results | ForEach-Object { Write-Host "  $_" }
Write-Host "=== VM Stress complete ==="
PSEOF

echo ""
echo "[1/1] Launching VM stress on $VM_NAME (modes: ${MODE_LABEL}, ${DURATION}m)..."
run_stress "$STRESS_PS1"

echo ""
echo "============================================================"
echo " Done. Metrics (% Processor Time, Available MBytes,"
echo " Disk Read/Write Bytes/sec) appear in Azure Monitor"
echo " / VM Insights Performance within ~1-2 minutes."
echo "============================================================"
