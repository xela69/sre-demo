# Symmetric Routing: TenantB to MCAPS

## Scope

TenantB and MCAPS are independently deployed Azure tenants connected through a route-based IKEv2 IPsec tunnel:

- TenantB endpoint: FortiGate NVA with a static Standard public IP.
- MCAPS endpoint: Azure VPN Gateway and a Local Network Gateway containing the TenantB public IP and prefixes.
- Routing mode: static prefixes; VPN BGP is disabled.
- MCAPS inspection point: Azure Firewall at `10.50.4.4`.
- TenantB inspection point: FortiGate.

TenantB is a remote VPN site, not an MCAPS spoke. There is no cross-tenant VNet peering, private DNS VNet link, or resource-ID dependency.

## Address Spaces

| Zone | Prefix |
| --- | --- |
| MCAPS hub | `10.50.0.0/20` |
| MCAPS apps spoke | `10.52.0.0/20` |
| MCAPS DC spoke, when deployed | `10.53.0.0/20` |
| TenantB | `10.61.0.0/20` |
| TenantB source workloads | `10.61.2.0/23` |

## Route Ownership

| Owner | Route | Next hop |
| --- | --- | --- |
| TenantB workload subnet | MCAPS address spaces | FortiGate internal IP `10.61.0.36` |
| FortiGate | MCAPS address spaces | IPsec tunnel interface |
| MCAPS Local Network Gateway | TenantB address spaces | TenantB FortiGate public IP |
| MCAPS GatewaySubnet | Each MCAPS address space | Azure Firewall `10.50.4.4` |
| MCAPS workload subnets | `0.0.0.0/0` | Azure Firewall `10.50.4.4` |
| AzureFirewallSubnet | `0.0.0.0/0` | Internet |

The AzureFirewallSubnet route table keeps gateway route propagation enabled. Azure therefore injects the static TenantB prefixes from the Local Network Gateway into the firewall subnet's effective routes. This mechanism works with VPN BGP disabled.

## Traffic Flows

### MCAPS to TenantB

```text
MCAPS workload
  -> workload UDR 0.0.0.0/0
  -> Azure Firewall
  -> gateway-propagated TenantB route
  -> Azure VPN Gateway
  -> IPsec tunnel
  -> FortiGate
  -> TenantB workload
```

The MCAPS workload subnet disables gateway route propagation so a more-specific VPN route cannot bypass Azure Firewall.

### TenantB to MCAPS

```text
TenantB workload
  -> workload UDR for MCAPS prefixes
  -> FortiGate
  -> IPsec tunnel
  -> Azure VPN Gateway
  -> GatewaySubnet UDR for the destination MCAPS prefix
  -> Azure Firewall
  -> MCAPS workload
```

The GatewaySubnet UDR is required for MCAPS stateful symmetry. Without it, the VPN Gateway could deliver the initial packet directly to a workload while the reply follows that workload's default route through Azure Firewall. The firewall would then see only the reply and could drop it because no session state exists.

## Route Table Constraints

### TenantB workload route table

- Add one route for each declared MCAPS address space.
- Use `VirtualAppliance` with the FortiGate internal IP as next hop.
- Do not attach this route table to the FortiGate internal subnet; that would create a forwarding loop.
- Do not send TenantB-to-TenantB traffic through the IPsec tunnel.

### MCAPS GatewaySubnet route table

- Add only specific MCAPS destination prefixes through Azure Firewall.
- Do not add `0.0.0.0/0` to GatewaySubnet.
- Keep gateway route propagation enabled.

### MCAPS workload route tables

- Keep `0.0.0.0/0 -> 10.50.4.4`.
- Disable gateway route propagation so TenantB routes do not bypass Azure Firewall.

### AzureFirewallSubnet route table

- Keep gateway route propagation enabled.
- Keep the required `0.0.0.0/0 -> Internet` route.
- Do not add duplicate custom routes for TenantB; they are propagated from the Local Network Gateway.

## Firewall Policy

| Direction | Source group | Destination group | Action |
| --- | --- | --- | --- |
| MCAPS to TenantB | `trustedAzureIpGroup` | `trustedTenantBIpGroup` | Allow approved protocols and ports |
| TenantB to MCAPS | `trustedTenantBIpGroup` | `trustedAzureIpGroup` | Allow approved protocols and ports |

The initial lab policy retains the existing approved port set. Tighten it to the Arc, migration, DNS, administrative, and application flows actually required by the demonstration.

## FortiGate Requirements

- Enable IP forwarding on both Azure NICs.
- Use the external NIC as the primary NIC and bind its static public IP.
- Configure a route-based IKEv2 tunnel to the MCAPS VPN Gateway public IP.
- Match the MCAPS IPsec proposal exactly: AES-256, SHA-256, DH group 14, and the agreed phase-2 settings.
- Configure static routes for the MCAPS prefixes through the tunnel.
- Configure FortiGate policies in both directions without NAT for private VPN traffic.
- Restrict management access to approved public source CIDRs.

## Validation

1. Confirm both deployment roots compile independently.
2. Run subscription-scope ARM validation and `what-if` in TenantB.
3. Record the FortiGate public IP from the TenantB deployment output.
4. Run subscription-scope ARM validation and `what-if` in MCAPS with that IP and the secure PSK.
5. After deployment, verify effective routes on the TenantB workload NIC, AzureFirewallSubnet, GatewaySubnet, and MCAPS workload NICs.
6. Verify VPN connection status and IKE diagnostics on both endpoints.
7. Test a connection initiated in each direction and confirm both legs appear in Azure Firewall network-rule logs.

The PSK must be injected securely into each tenant. It must not be committed to a parameter file or emitted as a deployment output.
