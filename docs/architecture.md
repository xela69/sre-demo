# SRE-Demo — SRE Demo Deployment Plan 

## Architecture: 
Hub and spokes

### Subscription Layout

```bash
hubSubId="ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9"   # hub subscription
appsSubId="42021d44-97d2-47a1-8245-a77149dda4c3"  # apps-spoke subscription
dataSubId="8de6c6e8-53af-4ded-a480-fd20c6093e78"  # data-spoke subscription
```

## CIDR Scheme HUB/SPOKES

| Spoke | Address Space | vmSubnet | fwPrivateIP | Status |
|-------|--------------|----------|-------------|--------|
|Hub | `10.50.0.0/20` | `10.50.0.0/24` | `10.50.4.4` | done |
| data-spoke | `10.51.0.0/20` | `10.51.0.0/24` | `10.50.4.4` | done |
| Apps-spoke | `10.52.0.0/20` | `10.52.0.0/24` | `10.50.4.4` | done |
| onprem-spoke | `10.53.0.0/20` | `10.53.0.0/24` | `10.50.4.4` | future |

**On-Prem Networks** (BGP-advertised via FortiGate):

| Network | Address Space | Function | Notes |
|---------|---------------|----------|-------|
| WiFi | `10.2.1.0/24` | — | User SSID |
| internal3 | `172.16.110.0/24` | — | On-prem data segment |
| internal2 | `172.17.111.0/24` | — | On-prem internal segment |
| internal1 | `10.6.1.0/24` | — | On-prem infrastructure |

---

## AVM Module Status (hub)

All hub resources migrated to AVM in `main/hub/hubmain.bicep`.
Custom modules kept where AVM replacement adds no value (complex UDR/peering/firewall policy logic).

| Resource | AVM Module | Status |
|----------|-----------|--------|
| ACR | `avm/res/container-registry/registry:0.9.3` | done |
| Log Analytics | `avm/res/operational-insights/workspace:0.9.1` | done |
| App Insights | `avm/res/insights/component:0.7.1` | done |
| DCR (base + perf) | `avm/res/insights/data-collection-rule:0.10.0` | done |
| Storage | `avm/res/storage/storage-account:0.14.3` | done |
| Windows VM | `avm/res/compute/virtual-machine:0.9.0` | done |
| Linux VM | `avm/res/compute/virtual-machine:0.9.0` | done |
| Bastion | `avm/res/network/bastion-host:0.8.2` | done |
| DNS Resolver | `avm/res/network/dns-resolver:0.5.6` | done |
| DNS Forwarding Ruleset | `avm/res/network/dns-forwarding-ruleset:0.5.3` | done |
| Key Vault | `avm/res/key-vault/vault:0.9.0` | done |
| VPN Gateway | `avm/res/network/virtual-network-gateway:0.9.0` | done |
| Local Network Gateway | `avm/res/network/local-network-gateway:0.4.0` | done |
| VPN Connection | `avm/res/network/connection:0.1.6` | done |
| Hub VNet | `modules/hub/hubvnet.bicep` (custom - kept) | done |
| Firewall | `modules/hub/firewall-vnet.bicep` (custom - kept) | done |
| Private DNS links | `modules/hub/privatednslinks.bicep` (custom - kept) | done |
| DCR Association | `modules/hub/dcr-association.bicep` (custom - kept) | done |

---

## VM Deployment (data-spoke)

Deployed via `main/data-spoke/opmain.bicep` using AVM `compute/virtual-machine:0.9.0`.
Subscription: `$dataSubId`

| VM | Image | DSC Script | Purpose |
|----|-------|-----------|---------|
| `onprem-win-vm` | Community gallery `WS2012R2_SQL2014_Base` (Tahubu) | `windows-vm-config.zip` -> ArcConnect | Azure Arc onboarding |
| `onprem-sql-vm` | Marketplace `SQL2019-WS2022/Standard` | `sql-vm-config.zip` -> Main + DbRestore | SQL source for migration |

DSC scripts from `https://raw.githubusercontent.com/{repositoryOwner}/migrate-to-azure-landing-zone/{repositoryBranch}/...`
Defaults: `repositoryOwner=microsoft`, `repositoryBranch=main`.

### Lab Credentials (from original tailspin lab)

| Credential | Value | Used For |
|-----------|-------|---------|
| `adminUsername` | `demouser` | VM local admin (both VMs), SQL MI admin login |
| `labPassword` | `demo!pass123` | VM admin password, DSC `DatabasePassword` (SQL restore SA password) |

`labPassword` is a required param in `datamain.bicep` with no default — pass inline at deploy time:
`--parameters labPassword='demo!pass123'`

NSG removed. Azure Firewall (`10.50.4.4`) is the sole control plane via UDR `0.0.0.0/0 -> AzFW`.

---

## Firewall Rules (firewall-vnet.bicep)

| Rule Collection | Group Priority | Notes |
|----------------|---------------|-------|
| `AllowTrustedAzureTraffic` | 300 | East-west within Azure subnets. Ports incl. 1433, 5022, 11000-11999 |
| `AllowAzureToOnPrem` | 300 | Azure -> onprem direction. Same port set |
| `AllowOnPremToAzure` | 300 | Onprem -> Azure direction. Same port set |

IP Group `trustedAzureSubnets`: `10.50.0.0/20` (hub), `10.51.0.0/20` (data), `10.52.0.0/20` (apps)
IP Group `infraServerSubnets`: `10.50.0.0/24`, `10.51.0.0/24`, `10.52.0.0/24` (internet egress rules)

---
┌─────────────────────────────────────────────────────────────────┐
│  AZURE HUB-SPOKE-ONPREM ROUTING MODEL                           │
└─────────────────────────────────────────────────────────────────┘

SPOKE VMs (10.51.1.0, 10.52.0.0, etc.)
  ├─ RouteTable: hubRouteTable (BGP disabled)
  ├─ Routes:
  │  ├─ 10.2.1.0/24 → Firewall 10.50.4.4 (inspection)
  │  ├─ 10.6.1.0/24 → Firewall 10.50.4.4 (inspection)
  │  ├─ 172.16.110.0/24 → Firewall 10.50.4.4 (inspection)
  │  ├─ 172.17.111.0/24 → Firewall 10.50.4.4 (inspection)
  │  └─ 0.0.0.0/0 → Firewall 10.50.4.4 (default)

FIREWALL SUBNET (10.50.4.0/26)
  ├─ RouteTable: firewallSubnetRouteTable (BGP ENABLED ✅)
  ├─ Explicit routes:
  │  ├─ 10.2.1.0/24 → VPN Gateway
  │  ├─ 10.6.1.0/24 → VPN Gateway
  │  ├─ 172.16.110.0/24 → VPN Gateway
  │  └─ 172.17.111.0/24 → VPN Gateway
  └─ Dynamic routes (learned via BGP):
     ├─ 10.50.0.0/20 (Hub VNet, system route)
     ├─ 10.51.0.0/20 (Spoke1, if peered)
     ├─ 10.52.0.0/20 (Spoke2, if peered)
     └─ 10.53.0.0/20 (Spoke3, if peered)

GATEWAY SUBNET (10.50.2.0/26, contains VPN Gateway)
  ├─ RouteTable: hubVpnGatewayTable (BGP disabled)
  ├─ Routes:
  │  └─ 0.0.0.0/0 → Firewall 10.50.4.4
  └─ System routes (ALWAYS present, no table needed):
     ├─ 10.50.0.0/20 (Hub VNet direct)
     └─ 10.2.1.0/24, etc. (from on-prem via IPsec)

ONPREM
  ├─ Sends to Azure via IPsec tunnel
  └─ Receives via return route in VPN tunnel

## Apps-Spoke VM Inventory (SQL VM)

Deployed via `main/apps-spoke/appsmain.bicep` using AVM `compute/virtual-machine:0.9.0`.
Subscription: `$appsSubId` (centralus)

| VM | RG | Image | Purpose |
|----|----|-------|---------|
| `AppsVM` | `AppsRG-VM` | `MicrosoftWindowsServer/WindowsServer/2022-datacenter-azure-edition` | General-purpose app server |
| `AppsSQLVM` | `AppsRG-SQL` | `MicrosoftSQLServer/sql2022-ws2022/sqldev-gen2` | SQL Server 2022 Developer — Azure Migrate source |

### AppsSQLVM — Lab Database (AzMigrate Source)

- **SQL instance**: `localhost` (default), Windows auth
- **Database**: `LabAppDB`
- **Seeded via**: CSE extension → `C:\labsql.ps1` (decoded from base64 at deploy time)
- **Logs**: `C:\labsql-setup.log`, `C:\labappdb-out.log`
- **Tag**: `AzMigrateSource: true`
- **Data disk**: 64 GB Standard_LRS (LUN 0, caching ReadOnly — SQL data files)

#### LabAppDB Schema

| Table | Rows | Notes |
|-------|------|-------|
| `dbo.Customers` | 8 | Name, email, city, country |
| `dbo.Products` | 10 | Name, category, price, stock |
| `dbo.Orders` | 10 | FK → Customers, status, total |
| `dbo.OrderItems` | 21 | FK → Orders + Products, qty, unit price |

#### Migration Path (TenantA targets)

| Source | Target | Tool |
|--------|--------|------|
| `AppsSQLVM\MSSQLSERVER` (`LabAppDB`) | Azure SQL MI or Azure SQL DB | Azure Migrate + DMS online migration |

---

## Apps-Spoke Storage

| Resource | RG | SKU | Purpose |
|----------|----|-----|---------|
| `appsbswj` | `AppsRG-Storage` | Standard_GRS | Blob (inputs/outputs/errors) + File share (notesdoc) |

Role assignments: `xelaStorage-Identity` (hub sub) → Storage Blob Data Contributor + Storage Queue Data Contributor

---



```bash
# Hub (Tenant)
az deployment sub create --subscription $hubSubId -l westus2 --template-file ./main/hub/hubmain.bicep   --parameters natPublicIP=$(curl -4 -s ifconfig.me) accessKey=$(cat ./docs/pwd.txt) sshPublicKey="$(cat ~/.ssh/id_ed25519.pub)" --what-if

# data-spoke (lab VMs)
az deployment sub create --subscription $dataSubId -l westus2 --template-file ./main/data-spoke/datamain.bicep --parameters accessKey=$(cat ./docs/pwd.txt) labPassword=<lab-vm-password> --what-if

# Apps-spoke (Server2019 and SQL)
az deployment sub create --subscription $appsSubId -l westus2 --template-file ./main/apps-spoke/appsmain.bicep --parameters accessKey=$(cat ./docs/pwd.txt) --what-if

---

## Outstanding Items

| Item | Priority | Notes |
|------|----------|-------|
| VPN GW + peering | high | Run `./scripts/azcli/enable_vpngw_peering.sh` — redeploys hub with `deployVpnGw=true`, then patches spoke peerings to `useRemoteGateways=true` |

| TenantA SQL MI + AKS | medium | Validated regions: `northcentralus`, `westus3`, `swedencentral` |

onprem fortigate confi details:

On macOS, native RDP via Bastion requires the manual tunnel approach:
# Step 1 — open tunnel (keep this running in background)
az network bastion tunnel \
  --name CPSBastion \
  --resource-group hubRG \
  --target-resource-id /subscriptions/ed70102f-f789-4d4e-ac00-074283844a0c/resourceGroups/hubRG-VM/providers/Microsoft.Compute/virtualMachines/hubVMpu54 \
  --resource-port 3389 \
  --port 54321 &

# Step 2 — connect Microsoft Remote Desktop to localhost:54321
# Username: vmuser  Password: <contents of docs/pwd.txt>

Summary:

Method	Windows	macOS
Web browser (portal)	✅	✅
Portal "Download RDP file"	✅ (mstsc.exe)	❌
az network bastion tunnel + RDP client	✅	✅