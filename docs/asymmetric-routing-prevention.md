# Asymmetric Routing Prevention: Hub-Spoke Inspection Strategy

the hub and spoke topology setup specifically with respect to traffic inspection, are as followed:

East-West Inspection:
  hubSubsubnets to spokeSubnets -- inspected
  spokesubnet to spokesubnet -- inspected

Azure to Internet -- inspected

Azure to Onprem: inspected
  hub subnet or spokes Subnet to onprem prefixes vpn gateway -- Inspected
  return traffic onprem to azure -- Not Inspected


## Overview

In a hub-spoke topology with Azure Firewall and a VPN Gateway, traffic inspection goals are:

| Flow | Direction | Inspection |
|------|-----------|------------|
| Spoke ↔ Spoke (East-West) | Both | ✅ Inspected by Azure Firewall |
| Azure (Hub/Spoke) → On-prem | Outbound | ✅ Inspected by Azure Firewall |
| On-prem → Azure (Hub/Spoke) | Return | ❌ Not inspected (bypass firewall) |

Return traffic from on-prem bypasses the firewall to avoid double-inspection and asymmetric routing issues. The Azure VPN Gateway routes directly to spoke VNets via gateway transit peering.

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
   • 10.2.1.0/24 → VirtualNetworkGateway        ← on-prem UDRs on firewall RT (not hub VM RT)
   • 10.6.1.0/24 → VirtualNetworkGateway
   • 172.16.110.0/24 → VirtualNetworkGateway
   • 172.17.111.0/24 → VirtualNetworkGateway
   • 0.0.0.0/0   → Internet                     ← Azure requirement for AzureFirewallSubnet

4. VPN Gateway → on-prem tunnel → FortiGate receives packet

✅ INSPECTED
```

### Flow 2: On-prem → Azure Spoke (NOT INSPECTED — bypasses firewall)

```
On-prem (10.2.1.5) → Spoke VM (10.51.0.4)

1. Packet arrives at hub VPN Gateway via IPsec tunnel

2. No UDR on GatewaySubnet — VPN GW routes directly using:
   • BGP-learned route: 10.51.0.0/20 via hub→spoke VNet peering
   • useRemoteGateways: true on spoke peering enables this bypass path

3. Packet delivered directly to spoke VM — Azure Firewall is bypassed

❌ NOT INSPECTED — on-prem return traffic bypasses the firewall by design
```

> **Design intent**: GatewaySubnet has no route table. The VPN Gateway uses BGP-learned peering routes to deliver on-prem traffic directly to spoke VNets. Azure-initiated sessions (Flow 1) are still inspected outbound; the return leg is not. Acceptable when the on-prem site is a trusted corporate network and the primary inspection boundary is Azure-outbound traffic.

### Flow 3: On-prem → Hub VM (NOT INSPECTED — same as Flow 2)

```
On-prem (10.2.1.5) → Hub VM (10.50.0.4)

1. No UDR on GatewaySubnet — VPN GW routes directly to hub VM subnet
2. Packet delivered directly to hub VM — Azure Firewall is bypassed

❌ NOT INSPECTED
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

### GatewaySubnet
No route table is applied. The VPN Gateway routes return traffic from on-prem directly to spoke VNets using BGP-learned peering routes (`useRemoteGateways: true` on spokes). This is intentional — on-prem return traffic bypasses the firewall.

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

`useRemoteGateways: true` on spoke peering enables the VPN Gateway in the hub to route traffic directly to spoke VNets — this is what allows on-prem return traffic to bypass the firewall.

---

## Firewall Policy Rules

| Rule | Source | Destination | Protocols | Action |
|------|--------|-------------|-----------|--------|
| `AllowTrustedAzureTraffic` | trustedAzureIpGroup | trustedAzureIpGroup | TCP/UDP/ICMP | ALLOW |
| `AllowAzureToOnPrem` | trustedAzureIpGroup | trustedOnPremIpGroup | TCP/UDP/ICMP | ALLOW |
| `AllowOnPremToAzure` | trustedOnPremIpGroup | trustedAzureIpGroup | TCP/UDP/ICMP | ALLOW |

**On-prem IP Group** (`ipg-trusted-onprem`): `10.2.1.0/24`, `10.6.1.0/24`, `172.16.110.0/24`, `172.17.111.0/24`

**`AllowOnPremToAzure`** is intentionally defined but effectively unused for traffic that bypasses the firewall via VPN GW → peering. It handles the edge case where on-prem traffic arrives at a hub subnet with only a `0.0.0.0/0 → Firewall` UDR (e.g., hub VMs initiating sessions back to on-prem sources).

---

## Files Modified

| File | Change |
|------|--------|
| `modules/hub/hubvnet.bicep` | Removed `gatewaySubnetRouteTable` (GatewaySubnet has no RT — on-prem return traffic bypasses FW by design); fixed `hubRouteTable.disableBgpRoutePropagation: true`; hub/spoke VM subnets use `0.0.0.0/0 → FW` |
| `modules/spokes/spokevnets.bicep` | `disableBgpRoutePropagation: true`; `useRemoteGateways: true` on spoke peering |

---

## Validation

### Check hub VM effective routes (expect no on-prem UDRs, only 0.0.0.0/0 → VirtualAppliance)
```bash
az network nic show-effective-route-table \
  --resource-group hubRG-VM \
  --name <hub-vm-nic> \
  --output table
```

### Check firewall subnet effective routes (expect on-prem UDRs + 0.0.0.0/0 → Internet)
```bash
az network nic show-effective-route-table \
  --resource-group hubRG \
  --name <firewall-mgmt-nic> \
  --output table
```

### End-to-end ping test (from FortiGate — should succeed and show in firewall logs)
```
execute ping-options source 10.2.1.1
execute ping 10.50.0.5
```

### Firewall log — confirm Azure→OnPrem traffic is logged (inspected)
```bash
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where ResourceType == 'AZUREFIREWALLS' | where msg_s contains '10.2.1'"
```


