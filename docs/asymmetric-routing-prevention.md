# Asymmetric Routing Prevention: Hub-Spoke Inspection Strategy

## Overview

In a hub-spoke topology with Azure Firewall and a VPN Gateway, traffic inspection goals are:

| Flow | Direction | Inspection |
|------|-----------|------------|
| Spoke ↔ Spoke (East-West) | Both | ✅ Inspected by Azure Firewall |
| Azure (Hub/Spoke) → On-prem | Outbound | ✅ Inspected by Azure Firewall |
| On-prem → Azure (Hub/Spoke) | Inbound | ✅ Inspected by Azure Firewall (via GatewaySubnet RT) |

All three flows are inspected by Azure Firewall to maintain **symmetric stateful inspection**. The GatewaySubnet route table (`hubRouteTable-gw`) redirects on-prem-initiated traffic through the firewall before it reaches spoke/hub VMs. This is required because spoke and hub VM subnets use `0.0.0.0/0 → Firewall` UDRs — if on-prem traffic bypassed the firewall, the VM's reply would hit the firewall which has **no session state** (never saw the SYN), causing the firewall to drop the reply.

> **Common misconception**: It may seem like on-prem → Azure traffic should bypass the firewall to "avoid double-inspection". In reality, the firewall handles both legs of the same session statelessly on the return path — there is no double-inspection. The firewall sees the initial SYN, creates state, and return packets match that state without re-inspection.

---

## Traffic Flows

### Flow 1: Spoke → On-prem (INSPECTED outbound)

```
Spoke VM (10.51.0.4) → On-prem (10.2.1.5)

1. Spoke subnet route table:
   • 0.0.0.0/0 → Azure Firewall (10.50.4.4)   ← UDR catches all outbound
   • disableBgpRoutePropagation: true           ← prevents VPN GW from adding on-prem bypass routes

2. Azure Firewall receives packet:
   • Rule: AllowAzureToOnPrem
   • Source:      trustedAzureIpGroup (10.50-53.x)
   • Destination: trustedOnPremIpGroup (10.2.1.0/24, 10.6.1.0/24, 172.16.110.0/24, 172.17.111.0/24)
   • Protocol:    TCP/UDP/ICMP → ALLOW ✓

3. Firewall subnet route table:
   • 0.0.0.0/0 → Internet                       ← Azure requirement for AzureFirewallSubnet
   • on-prem routes injected via BGP propagation from VPN GW (disableBgpRoutePropagation: false)

4. VPN Gateway → on-prem tunnel → FortiGate receives packet

✅ INSPECTED
```

### Flow 2: On-prem → Azure Spoke (INSPECTED — symmetric with Flow 1)

```
On-prem (10.2.1.5) → Spoke VM (10.51.0.4)

1. Packet arrives at hub VPN Gateway via IPsec tunnel

2. GatewaySubnet route table (hubRouteTable-gw) lookup:
   • 10.51.0.0/20 → Azure Firewall (10.50.4.4)   ← redirects to FW before delivery to spoke
   • 10.50.0.0/20 → Azure Firewall (10.50.4.4)   ← same for hub prefixes
   • 10.52.0.0/20 → Azure Firewall (10.50.4.4)   ← apps spoke
   • disableBgpRoutePropagation: false            ← GatewaySubnet must keep BGP routes to function

3. Azure Firewall receives packet:
   • Rule: AllowOnPremToAzure
   • Source:      trustedOnPremIpGroup
   • Destination: trustedAzureIpGroup
   • Protocol:    TCP/UDP/ICMP → ALLOW ✓
   • FW creates session state ✓

4. Firewall routes packet to spoke VM (via VNet routing)

5. Spoke VM replies → 0.0.0.0/0 → Firewall:
   • FW matches existing state → ALLOW (no re-inspection)
   → FW routes to VPN GW → on-prem

✅ INSPECTED — symmetric, stateful (FW sees both legs)
```

> **Why GatewaySubnet RT is required**: Without it, VPN GW delivers on-prem packets directly to the destination subnet, bypassing the firewall. The Azure VM then replies via `0.0.0.0/0 → Firewall`, but the firewall has **no state** for the connection (never saw the SYN) and drops the reply. The GatewaySubnet RT forces on-prem-initiated traffic through the firewall first, making both legs symmetric.

### Flow 3: On-prem → Hub VM (INSPECTED — same as Flow 2)

```
On-prem (10.2.1.5) → Hub VM (10.50.0.4)

1. GatewaySubnet RT (hubRouteTable-gw): 10.50.0.0/20 → Azure Firewall ✓
2. Firewall: AllowOnPremToAzure → ALLOW, creates state
3. Hub VM replies → 0.0.0.0/0 → Firewall → matches state → on-prem

✅ INSPECTED — symmetric
```

### Flow 4: Spoke ↔ Spoke East-West (INSPECTED both directions)

```
Spoke A (10.51.0.4) ↔ Spoke B (10.52.0.4)

OUTBOUND (Spoke A → Spoke B):
1. Spoke A route table: 0.0.0.0/0 → Firewall → ALLOW (AllowTrustedAzureTraffic) ✓

RETURN (Spoke B → Spoke A):
1. Spoke B route table: 0.0.0.0/0 → Firewall → ALLOW (AllowTrustedAzureTraffic) ✓

✅ BOTH DIRECTIONS INSPECTED
```

---

## Route Table Design

### Hub Route Table (`hubRouteTable`)
Applied to: all hub subnets except GatewaySubnet, AzureFirewallSubnet, AzureBastionSubnet, privateEPSubnet, dns subnets

```bicep
properties: {
  disableBgpRoutePropagation: true  // prevent BGP from injecting on-prem prefixes that bypass 0.0.0.0/0 → Firewall
  routes: [
    {
      name: '${routeTableName}-to-hubAzFirewall'
      properties: {
        addressPrefix: '0.0.0.0/0'
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: fwPrivateIP  // all outbound through firewall
      }
    }
  ]
}
```

> **`disableBgpRoutePropagation: true`**: Without this, the VPN GW could inject on-prem prefixes (e.g., `10.2.1.0/24`) into hub VM subnet route tables. Those more-specific routes would override `0.0.0.0/0 → Firewall` and bypass inspection for Azure→On-prem traffic.

### Firewall Subnet Route Table (`hubRouteTable-fw`)
Applied to: `AzureFirewallSubnet` only

```bicep
properties: {
  disableBgpRoutePropagation: false  // BGP enabled: VPN GW propagates on-prem routes into firewall's effective routes
  routes: [
    // Azure mandate: only 0.0.0.0/0 → Internet is supported as a custom UDR on AzureFirewallSubnet
    // On-prem routes reach the firewall via BGP propagation from VPN GW — NOT via custom UDRs
    { name: 'fw-subnet-to-internet', addressPrefix: '0.0.0.0/0', nextHopType: 'Internet' }
  ]
}
```

> **Why no on-prem UDRs here**: Azure Firewall subnet does **not** support custom UDRs for on-prem prefixes. Adding them puts the firewall into a faulted state (`FirewallPolicyUpdateFailed`). Instead, `disableBgpRoutePropagation: false` lets the VPN GW automatically inject on-prem routes into the firewall subnet's effective routes via BGP. The firewall uses those BGP-propagated routes to forward inspected traffic to the VPN GW.

### GatewaySubnet Route Table (`hubRouteTable-gw`)
Applied to: `GatewaySubnet` only

```bicep
properties: {
  disableBgpRoutePropagation: false  // must stay false — GatewaySubnet needs BGP routes to function
  routes: [
    // One entry per Azure address space (hub + each spoke)
    // Only specific Azure prefixes — 0.0.0.0/0 must NOT be added to GatewaySubnet
    { name: 'gw-to-fw-hub',       addressPrefix: '10.50.0.0/20', nextHopType: 'VirtualAppliance', nextHopIpAddress: fwPrivateIP }
    { name: 'gw-to-fw-apps',      addressPrefix: '10.52.0.0/20', nextHopType: 'VirtualAppliance', nextHopIpAddress: fwPrivateIP }
    // add dc-spoke, data-spoke entries when those VNets are deployed
  ]
}
```

> **Why only specific prefixes (not 0.0.0.0/0)**: Azure does not support `0.0.0.0/0` on GatewaySubnet. Only host or network routes for your Azure address space are valid here.

### Spoke Route Tables (`appsRouteTable`, `dcRouteTable`, `dataRouteTable`)

```bicep
properties: {
  disableBgpRoutePropagation: true  // prevent VPN GW from injecting on-prem bypass routes
  routes: [
    {
      name: '${routeTableName}-to-hubAzFirewall'
      properties: {
        addressPrefix: '0.0.0.0/0'
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: fwPrivateIP
      }
    }
  ]
}
```

> **Why `disableBgpRoutePropagation: true`**: With `useRemoteGateways: true` on spoke peering and a VPN GW in the hub, the VPN GW could inject on-prem prefixes into spoke route tables. Those more-specific routes would bypass the `0.0.0.0/0 → Firewall` UDR and allow spoke VMs to reach on-prem without firewall inspection.

---

## VNet Peering Configuration

```
Hub peering  → Spoke:  allowGatewayTransit: true,  useRemoteGateways: false
Spoke peering → Hub:   allowGatewayTransit: false, useRemoteGateways: true
```

`useRemoteGateways: true` on spoke peering enables the VPN Gateway in the hub to advertise spoke VNet address spaces to on-prem. Without the GatewaySubnet route table (`hubRouteTable-gw`), the VPN GW would deliver on-prem traffic directly to spoke VNets, bypassing the firewall. The GatewaySubnet RT overrides this by redirecting all Azure-destined traffic (hub + spoke prefixes) to the firewall first.

---

## Firewall Policy Rules

| Rule | Source | Destination | Protocols | Action |
|------|--------|-------------|-----------|--------|
| `AllowTrustedAzureTraffic` | trustedAzureIpGroup | trustedAzureIpGroup | TCP/UDP/ICMP | ALLOW |
| `AllowAzureToOnPrem` | trustedAzureIpGroup | trustedOnPremIpGroup | TCP/UDP/ICMP | ALLOW |
| `AllowOnPremToAzure` | trustedOnPremIpGroup | trustedAzureIpGroup | TCP/UDP/ICMP | ALLOW |

**On-prem IP Group** (`ipg-trusted-onprem`): `10.2.1.0/24`, `10.6.1.0/24`, `172.16.110.0/24`, `172.17.111.0/24`

**`AllowOnPremToAzure`** is actively used for all on-prem → Azure traffic. The GatewaySubnet route table (`hubRouteTable-gw`) forces on-prem-initiated packets through the firewall, where this rule evaluates and allows matching traffic. This ensures the firewall creates session state for the connection, enabling symmetric stateful inspection for the entire session lifecycle.

---

## Deployment Prerequisites

The hub VNet module (`modules/hub/hubvnet.bicep`) gates all firewall routing on the `enableFirewallRouting` parameter. This **must** be set to `true` for the traffic inspection design to work:

```json
// hub deployment parameters — ensure this is set
"enableFirewallRouting": { "value": true }
```

When `enableFirewallRouting: true`:
1. `hubRouteTable` gets the `0.0.0.0/0 → 10.50.4.4` route (hub VM subnets)
2. `hubRouteTable-gw` is created with all Azure address space routes → `10.50.4.4` (GatewaySubnet)
3. `hubRouteTable-gw` is attached to GatewaySubnet
4. Hub VNet DNS is set to the firewall private IP

When `enableFirewallRouting: false` (or omitted), none of the above are deployed and **all traffic bypasses the firewall**.

> **Note**: The spoke VNet module (`modules/spokes/spokevnets.bicep`) always creates the `0.0.0.0/0 → Firewall` route with `disableBgpRoutePropagation: true` — it does not have a conditional flag.

## Files Modified

| File | Change |
|------|--------|
| `modules/hub/hubvnet.bicep` | `hubRouteTable` and `hubRouteTable-gw` gated on `enableFirewallRouting`; `hubRouteTable.disableBgpRoutePropagation: true`; `hubRouteTable-gw` has Azure address space routes → FW; GatewaySubnet wired to `hubRouteTable-gw` |
| `modules/spokes/spokevnets.bicep` | `disableBgpRoutePropagation: true`; `useRemoteGateways: true` on spoke peering |

---

## Live Environment Audit (2026-04-08)

Audit performed against subscriptions `ebc6a927-*` (hub) and `42021d44-*` (apps-spoke).

### Resources Confirmed

| Component | Name | Status |
|-----------|------|--------|
| Azure Firewall | `xelaAzFirewall` | Deployed, Premium, private IP `10.50.4.4` |
| VPN Gateway | `xelavpngvnso` | Deployed, VpnGw1AZ, RouteBased, BGP off (static routes) |
| VPN Connection | `XelaVPNConnection` | Connected, IKEv2, DPD 45s, 0 bytes (routing fix pending) |
| Local Network Gateway | `xelalocalgw` | Peer `97.94.106.46`, prefixes: `10.6.1.0/24`, `172.16.110.0/24`, `172.17.111.0/24`, `10.2.1.0/24`, `192.168.0.0/24` |
| Hub VNet | `hubRG-VNet` | `10.50.0.0/20` |
| Apps Spoke VNet | `AppsRG-VNet` | `10.52.0.0/20` |
| Data Spoke VNet | — | Not yet deployed |
| DC Spoke VNet | — | Not yet deployed |

### Route Table Status

| Route Table | Routes | Subnets | Status |
|-------------|--------|---------|--------|
| `hubRouteTable` | `0.0.0.0/0 → 10.50.4.4` | `vmSubnet`, `appSubnet` | ✅ Manually remediated 2026-04-08 |
| `hubRouteTable-fw` | `0.0.0.0/0 → Internet` | `AzureFirewallSubnet` | ✅ Correct |
| `hubRouteTable-gw` | Azure address spaces → `10.50.4.4` | `GatewaySubnet` | ⚠️ Pending Bicep fix + redeploy |
| `appsRouteTable` | `0.0.0.0/0 → 10.50.4.4` | `vmSubnet`, `appSubnet` | ✅ Correct |

### Peering Status

| Peering | AllowGwTransit | UseRemoteGW | State |
|---------|---------------|-------------|-------|
| `hub-to-Apps-VNet-peering` | true | false | Connected ✅ |
| `AppsRG-VNet-to-hubRG-VNet-Peering` | false | true | Connected ✅ |

---

## Validation

### 1. Verify route tables exist and have correct routes
```bash
az network route-table list \
  --resource-group hubRG \
  --subscription ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9 \
  --query "[].{name:name, disableBgp:disableBgpRoutePropagation, routes:routes[].{name:name, prefix:addressPrefix, nextHop:nextHopIpAddress}}" \
  --output json
```

### 2. Verify GatewaySubnet has hubRouteTable-gw attached
```bash
az network vnet subnet show \
  --resource-group hubRG --vnet-name hubRG-VNet --name GatewaySubnet \
  --subscription ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9 \
  --query "{routeTable:routeTable.id}" --output json
# Expected: routeTable references hubRouteTable-gw
```

### 3. Check hub VM effective routes (expect 0.0.0.0/0 → VirtualAppliance 10.50.4.4)
```bash
az network nic show-effective-route-table \
  --resource-group hubRG-VM \
  --name <hub-vm-nic> \
  --output table
```

### 4. Check firewall subnet effective routes (expect BGP-propagated on-prem routes + 0.0.0.0/0 → Internet)
```bash
az network nic show-effective-route-table \
  --resource-group hubRG \
  --name <firewall-mgmt-nic> \
  --output table
```

### 5. End-to-end ping test (from FortiGate — should succeed and show in firewall logs)
```
execute ping-options source 10.2.1.1
execute ping 10.50.0.5
```

### 6. Firewall log — confirm both directions are logged (inspected)
```bash
# Azure → On-prem (outbound)
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AZFWNetworkRule | where DestinationIp startswith '10.2.1' | project TimeGenerated, SourceIp, DestinationIp, Action | take 10"

# On-prem → Azure (inbound — confirms GatewaySubnet RT is working)
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AZFWNetworkRule | where SourceIp startswith '10.2.1' | project TimeGenerated, SourceIp, DestinationIp, Action | take 10"
```


