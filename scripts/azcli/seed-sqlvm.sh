#!/usr/bin/env bash
# =============================================================================
# seed-sqlvm.sh — Post-deploy: seed LabAppDB on AppsSQLVM via az vm run-command
#
# Usage:
#   ./seed-sqlvm.sh              # seed (idempotent — safe to re-run)
#   ./seed-sqlvm.sh --check      # validate row counts only, no seeding
#   ./seed-sqlvm.sh --dry-run    # print what would run without executing
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PS1_FILE="$REPO_ROOT/scripts/sql/setup-labsql.ps1"

APPS_SUB="86d55e1e-4ca9-4ddd-85df-2e7633d77534"
VM_RG="AppsRG-SQL"
VM_NAME="AppsSQLVM"

CHECK_ONLY=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --check)    CHECK_ONLY=true ;;
    --dry-run)  DRY_RUN=true    ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] az vm run-command invoke -g $VM_RG --name $VM_NAME ..."
  else
    az account set --subscription "$APPS_SUB"
    az vm run-command invoke \
      -g "$VM_RG" --name "$VM_NAME" \
      --command-id RunPowerShellScript \
      --scripts "@$1" \
      --query "value[0].message" -o tsv 2>&1
  fi
}

echo "============================================================"
echo " LabAppDB Seed Script"
echo " VM: $VM_RG/$VM_NAME  sub: $APPS_SUB"
echo " dry-run=$DRY_RUN  check-only=$CHECK_ONLY"
echo "============================================================"

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo ""
  echo "[CHECK] Validating LabAppDB row counts..."
  VALIDATE_PS1=$(mktemp /tmp/validate-XXXXXX.ps1)
  cat > "$VALIDATE_PS1" << 'PSEOF'
$c=(gci "C:\Program Files\Microsoft SQL Server" -r -fil sqlcmd.exe -EA 0|sort LastWriteTime -d|select -f 1).FullName
&$c -S localhost -E -d LabAppDB -Q "SELECT 'Customers' AS T,COUNT(*) AS N FROM dbo.Customers UNION ALL SELECT 'Products',COUNT(*) FROM dbo.Products UNION ALL SELECT 'Orders',COUNT(*) FROM dbo.Orders UNION ALL SELECT 'OrderItems',COUNT(*) FROM dbo.OrderItems;"
PSEOF
  run_cmd "$VALIDATE_PS1"
  rm -f "$VALIDATE_PS1"
  exit 0
fi

# ── Seed ──────────────────────────────────────────────────────────────────────
if [[ ! -f "$PS1_FILE" ]]; then
  echo "ERROR: $PS1_FILE not found." >&2
  exit 1
fi

echo ""
echo "[1/2] Running setup-labsql.ps1 on $VM_NAME..."
echo "      (includes single-user SQL restart + sysadmin grant + DB seed)"
run_cmd "$PS1_FILE"

echo ""
echo "[2/2] Validating row counts..."
VALIDATE_PS1=$(mktemp /tmp/validate-XXXXXX.ps1)
cat > "$VALIDATE_PS1" << 'PSEOF'
$c=(gci "C:\Program Files\Microsoft SQL Server" -r -fil sqlcmd.exe -EA 0|sort LastWriteTime -d|select -f 1).FullName
&$c -S localhost -E -d LabAppDB -Q "SELECT 'Customers' AS T,COUNT(*) AS N FROM dbo.Customers UNION ALL SELECT 'Products',COUNT(*) FROM dbo.Products UNION ALL SELECT 'Orders',COUNT(*) FROM dbo.Orders UNION ALL SELECT 'OrderItems',COUNT(*) FROM dbo.OrderItems;"
PSEOF
run_cmd "$VALIDATE_PS1"
rm -f "$VALIDATE_PS1"

echo ""
echo "============================================================"
echo " Done. LabAppDB is ready for Azure Migrate assessment."
echo "============================================================"
