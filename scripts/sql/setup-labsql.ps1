<#
.SYNOPSIS  Seed LabAppDB on SQL Server 2022 Developer VM — Azure Migrate demo source.
.NOTES     Runs via CSE as LocalSystem (Windows auth). Idempotent — safe to re-run.
#>
$ErrorActionPreference = 'Continue'
$log = 'C:\labsql-setup.log'
function Log($m) { "$(Get-Date -f 's')  $m" | Tee-Object $log -Append | Write-Host }

Log "=== LabAppDB setup starting ==="

# ── 1. Wait for SQL service ────────────────────────────────────────────────────
$max = 12; $i = 0
do {
    $svc = Get-Service -Name 'MSSQLSERVER' -EA SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { break }
    Log "Waiting for MSSQLSERVER ($i/$max)..."; Start-Sleep 30; $i++
} while ($i -lt $max)

if (-not $svc -or $svc.Status -ne 'Running') {
    Log "Starting MSSQLSERVER..."; Start-Service MSSQLSERVER -EA SilentlyContinue; Start-Sleep 15
}

# ── 2. Locate sqlcmd ──────────────────────────────────────────────────────────
$sqlcmd = (Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse `
    -Filter sqlcmd.exe -EA SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $sqlcmd) { $sqlcmd = 'sqlcmd' }
Log "sqlcmd: $sqlcmd"

# ── 2b. Grant NT AUTHORITY\SYSTEM sysadmin via single-user mode ───────────────
# CSE runs as SYSTEM which has no SQL login by default — bootstrap access first.
Log "Granting SYSTEM sysadmin via single-user mode restart..."
$svcPath = ((Get-WmiObject Win32_Service -Filter "Name='MSSQLSERVER'").PathName).Replace('"','').Trim() -replace '\s+-\S+.*$',''
Stop-Service MSSQLSERVER -Force -EA SilentlyContinue
Start-Sleep 8
$proc = Start-Process $svcPath -ArgumentList '-m','-s','MSSQLSERVER' -PassThru -NoNewWindow
Start-Sleep 20
& $sqlcmd -S '.' -E -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name='NT AUTHORITY\SYSTEM') CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM];" 2>&1 | Out-Null
Log "SYSTEM sysadmin granted (exit=$LASTEXITCODE). Restarting service..."
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
Start-Sleep 8
Start-Service MSSQLSERVER
Start-Sleep 15
Log "MSSQLSERVER: $((Get-Service MSSQLSERVER).Status)"

# ── 3. DDL + seed data ────────────────────────────────────────────────────────
$sql = @'
IF DB_ID('LabAppDB') IS NULL CREATE DATABASE LabAppDB;
GO
USE LabAppDB;
GO

IF OBJECT_ID('dbo.Customers','U') IS NULL
  CREATE TABLE dbo.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName  NVARCHAR(50)  NOT NULL,
    LastName   NVARCHAR(50)  NOT NULL,
    Email      NVARCHAR(100) NOT NULL UNIQUE,
    City       NVARCHAR(50),
    Country    NVARCHAR(50)  NOT NULL DEFAULT 'USA');

IF OBJECT_ID('dbo.Products','U') IS NULL
  CREATE TABLE dbo.Products (
    ProductID   INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category    NVARCHAR(50),
    UnitPrice   DECIMAL(10,2) NOT NULL,
    Stock       INT NOT NULL DEFAULT 0);

IF OBJECT_ID('dbo.Orders','U') IS NULL
  CREATE TABLE dbo.Orders (
    OrderID    INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES dbo.Customers(CustomerID),
    OrderDate  DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    Status     NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    Total      DECIMAL(10,2) NOT NULL DEFAULT 0);

IF OBJECT_ID('dbo.OrderItems','U') IS NULL
  CREATE TABLE dbo.OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID     INT NOT NULL REFERENCES dbo.Orders(OrderID),
    ProductID   INT NOT NULL REFERENCES dbo.Products(ProductID),
    Qty         INT NOT NULL,
    UnitPrice   DECIMAL(10,2) NOT NULL);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Customers)
BEGIN
  SET IDENTITY_INSERT dbo.Customers ON;
  INSERT dbo.Customers(CustomerID,FirstName,LastName,Email,City,Country) VALUES
    (1,'Alice','Johnson','alice@contoso.com','Seattle','USA'),
    (2,'Bob','Smith','bob@contoso.com','Portland','USA'),
    (3,'Carol','Williams','carol@fabrikam.com','San Francisco','USA'),
    (4,'David','Brown','david@tailspin.com','Denver','USA'),
    (5,'Eve','Davis','eve@contoso.com','Austin','USA'),
    (6,'Frank','Miller','frank@northwind.com','Chicago','USA'),
    (7,'Grace','Wilson','grace@adventure.com','Miami','USA'),
    (8,'Hank','Moore','hank@contoso.com','Boston','USA');
  SET IDENTITY_INSERT dbo.Customers OFF;

  SET IDENTITY_INSERT dbo.Products ON;
  INSERT dbo.Products(ProductID,ProductName,Category,UnitPrice,Stock) VALUES
    (1,'Azure Notebook Pro','Electronics',1299.99,45),
    (2,'Cloud Keyboard X1','Peripherals',89.99,200),
    (3,'Smart Monitor 27in','Electronics',499.99,30),
    (4,'Wireless Mouse M3','Peripherals',39.99,500),
    (5,'USB-C Hub 7-Port','Accessories',59.99,150),
    (6,'Headset Pro 900','Audio',179.99,80),
    (7,'Webcam 1080p HD','Video',129.99,60),
    (8,'SSD 1TB External','Storage',99.99,90),
    (9,'Ergonomic Chair','Furniture',349.99,15),
    (10,'Standing Desk Pro','Furniture',799.99,10);
  SET IDENTITY_INSERT dbo.Products OFF;

  SET IDENTITY_INSERT dbo.Orders ON;
  INSERT dbo.Orders(OrderID,CustomerID,OrderDate,Status,Total) VALUES
    (1,1,'2025-11-01','Completed',1389.98),
    (2,2,'2025-11-05','Completed',129.98),
    (3,3,'2025-11-10','Shipped',1299.99),
    (4,4,'2025-12-01','Processing',439.98),
    (5,5,'2025-12-15','Completed',259.98),
    (6,1,'2026-01-03','Completed',799.99),
    (7,6,'2026-01-10','Cancelled',179.99),
    (8,7,'2026-02-14','Shipped',99.99),
    (9,8,'2026-02-28','Processing',1429.98),
    (10,3,'2026-03-05','Pending',649.98);
  SET IDENTITY_INSERT dbo.Orders OFF;

  SET IDENTITY_INSERT dbo.OrderItems ON;
  INSERT dbo.OrderItems(OrderItemID,OrderID,ProductID,Qty,UnitPrice) VALUES
    (1,1,1,1,1299.99),(2,1,4,1,89.99),
    (3,2,2,1,89.99),(4,2,4,1,39.99),
    (5,3,1,1,1299.99),
    (6,4,3,1,499.99),(7,4,5,1,59.99),(8,4,2,1,89.99),(9,4,4,1,39.99),
    (10,5,6,1,179.99),(11,5,4,2,39.99),
    (12,6,10,1,799.99),
    (13,7,6,1,179.99),
    (14,8,8,1,99.99),
    (15,9,1,1,1299.99),(16,9,3,1,499.99),(17,9,6,1,179.99),
    (18,10,9,1,349.99),(19,10,5,1,59.99),(20,10,7,1,129.99),(21,10,4,1,39.99);
  SET IDENTITY_INSERT dbo.OrderItems OFF;
END
PRINT 'LabAppDB seeded OK.';
GO
'@

$sqlFile = 'C:\labappdb.sql'
$sql | Set-Content $sqlFile -Encoding UTF8
Log "Running DDL + seed via sqlcmd (Windows auth)..."
& $sqlcmd -S localhost -E -i $sqlFile -o 'C:\labappdb-out.log' 2>&1
Log "sqlcmd exit=$LASTEXITCODE  (details: C:\labappdb-out.log)"
Log "=== LabAppDB setup complete ==="
