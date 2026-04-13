#!/usr/bin/env bash
# =============================================================================
# stress-sqlvm.sh — Generate SQL load on AppsSQLVM to produce metric data
#                   visible in Azure Monitor / VM Insights
#
# Usage:
#   ./stress-sqlvm.sh                        # 4 workers x 5 min (default)
#   ./stress-sqlvm.sh --duration 10          # run for 10 minutes
#   ./stress-sqlvm.sh --workers 8            # 8 parallel sqlcmd threads
#   ./stress-sqlvm.sh --dry-run              # print what would run, no exec
# =============================================================================
set -euo pipefail

APPS_SUB="42021d44-97d2-47a1-8245-a77149dda4c3"
VM_RG="AppsRG-SQL"
VM_NAME="AppsSQLVM"

DURATION=5     # minutes
WORKERS=4
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --duration) ;;
    --workers)  ;;
    --dry-run)  DRY_RUN=true ;;
    [0-9]*)
      # positional numeric — assigned to the last named flag context
      ;;
  esac
done

# Parse key=value and --flag value pairs
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    --duration) DURATION="${args[$((i+1))]}"; i=$((i+2)) ;;
    --workers)  WORKERS="${args[$((i+1))]}";  i=$((i+2)) ;;
    --dry-run)  DRY_RUN=true; i=$((i+1)) ;;
    *)          i=$((i+1)) ;;
  esac
done

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

echo "============================================================"
echo " SQL Stress — AppsSQLVM"
echo " VM: $VM_RG/$VM_NAME  sub: $APPS_SUB"
echo " workers=$WORKERS  duration=${DURATION}m  dry-run=$DRY_RUN"
echo "============================================================"

STRESS_PS1=$(mktemp /tmp/stress-sql-XXXXXX.ps1)
trap 'rm -f "$STRESS_PS1"' EXIT

cat > "$STRESS_PS1" << PSEOF
# Locate sqlcmd
\$sqlcmd = (Get-ChildItem "C:\Program Files\Microsoft SQL Server" -Recurse -Filter sqlcmd.exe -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName

if (-not \$sqlcmd) {
    Write-Error "sqlcmd.exe not found on \$env:COMPUTERNAME"
    exit 1
}

\$durationMinutes = $DURATION
\$workerCount     = $WORKERS
\$endTime         = (Get-Date).AddMinutes(\$durationMinutes)

Write-Host "=== SQL Stress starting: \$workerCount workers for \$durationMinutes minute(s) ==="
Write-Host "    End time: \$endTime"

# Queries that exercise CPU, I/O, and tempdb — uses the seeded LabAppDB data
\$queries = @(
    # Cross-join scan — CPU + I/O heavy
    "SELECT TOP 500000 c.CustomerID, c.Name, o.OrderID, p.Name AS Product, oi.Quantity
     FROM dbo.Customers c
     CROSS JOIN dbo.Orders o
     CROSS JOIN dbo.Products p
     INNER JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
     ORDER BY NEWID()",

    # Aggregation — forces hash/sort spill to tempdb
    "SELECT c.Name, COUNT(o.OrderID) AS OrderCount, SUM(oi.Quantity * p.Price) AS TotalValue
     FROM dbo.Customers c
     JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
     JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
     JOIN dbo.Products p ON p.ProductID = oi.ProductID
     GROUP BY c.Name
     ORDER BY TotalValue DESC",

    # Update churn — dirty pages, log writes
    "UPDATE TOP (200) dbo.Orders
     SET UpdatedAt = GETDATE()
     WHERE OrderID IN (SELECT TOP 200 OrderID FROM dbo.Orders ORDER BY NEWID())"
)

\$jobs = 1..\$workerCount | ForEach-Object {
    \$workerIdx = \$_
    Start-Job -ScriptBlock {
        param(\$sc, \$end, \$qs, \$idx)
        \$iter = 0
        while ((Get-Date) -lt \$end) {
            \$q = \$qs[\$iter % \$qs.Count]
            & \$sc -S localhost -E -d LabAppDB -Q \$q -b 2>&1 | Out-Null
            \$iter++
        }
        "Worker \$idx completed \$iter iterations"
    } -ArgumentList \$sqlcmd, \$endTime, \$queries, \$workerIdx
}

Write-Host "Workers launched — waiting for completion..."
\$results = \$jobs | Wait-Job | Receive-Job
\$jobs | Remove-Job

Write-Host "=== Results ==="
\$results | ForEach-Object { Write-Host "  \$_" }
Write-Host "=== SQL Stress complete ==="
PSEOF

echo ""
echo "[1/2] Launching SQL stress on $VM_NAME (${WORKERS} workers x ${DURATION}m)..."
echo "      Queries: cross-join scan, aggregation, update churn"
run_stress "$STRESS_PS1"

echo ""
echo "[2/2] Spot-checking row counts to confirm DB integrity..."
CHECK_PS1=$(mktemp /tmp/stress-check-XXXXXX.ps1)
trap 'rm -f "$STRESS_PS1" "$CHECK_PS1"' EXIT

cat > "$CHECK_PS1" << 'PSEOF'
$c=(gci "C:\Program Files\Microsoft SQL Server" -r -fil sqlcmd.exe -EA 0|sort LastWriteTime -d|select -f 1).FullName
&$c -S localhost -E -d LabAppDB -Q "SELECT 'Customers' AS T,COUNT(*) AS N FROM dbo.Customers UNION ALL SELECT 'Products',COUNT(*) FROM dbo.Products UNION ALL SELECT 'Orders',COUNT(*) FROM dbo.Orders UNION ALL SELECT 'OrderItems',COUNT(*) FROM dbo.OrderItems;"
PSEOF
run_stress "$CHECK_PS1"

echo ""
echo "============================================================"
echo " Done. Metrics (CPU %, Disk Read/Write Bytes, Logical I/O)"
echo " will appear in Azure Monitor / VM Insights within ~1-2 min."
echo "============================================================"
