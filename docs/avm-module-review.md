# SRE-Demo AVM-First Module Review

Date: 2026-08-25
Goal: Prefer Azure Verified Modules (AVM) wherever practical, and flag non-AVM modules for conversion or explicit retention.

## Summary

- Total module invocations in Bicep: 53
- AVM module invocations: 34
- Non-AVM module invocations: 19
- AVM adoption by invocation: 64.15%

## Completed Conversions

| Date | Module | Change | Validation |
|---|---|---|---|
| 2026-09-03 | `modules/apps/grubifyFrontend.bicep` | Removed one-use custom wrapper and called `br/public:avm/res/app/container-app:0.22.0` directly from `main/apps-spoke/appsmain.bicep` | `az bicep build --file main/apps-spoke/appsmain.bicep` |
| 2026-09-03 | `modules/apps/containerApp.bicep` | Removed API Container App wrapper; `main/apps-spoke/appsmain.bicep` now calls `br/public:avm/res/app/managed-environment:0.13.1` and `br/public:avm/res/app/container-app:0.22.0` directly | `az bicep build --file main/apps-spoke/appsmain.bicep` |
| 2026-09-03 | `modules/spokes/spokevnets.bicep` | Converted internals to AVM route table and AVM virtual network modules while retaining the wrapper contract for apps/data/DC spokes | `az bicep build --file main/apps-spoke/appsmain.bicep`; `az bicep build --file main/data-spoke/datamain.bicep`; `az bicep build --file main/dc-spoke/dcmain.bicep` |
| 2026-09-03 | `modules/hub/hubvnet.bicep` | Converted internals to AVM route table and AVM virtual network modules while retaining the wrapper for firewall-routing and subnet orchestration | `az bicep build --file main/hub/hubmain.bicep` |
| 2026-09-03 | `modules/hub/vnet-peering.bicep` | Reviewed for AVM conversion; retained as custom because AVM peering support is embedded in the VNet module and would remove the isolated peering deployment boundary | `az bicep build --file main/hub/hubmain.bicep` |
| 2026-09-03 | `modules/hub/monitor-diag.bicep` | Moved App Insights diagnostics into the AVM App Insights module; retained custom wrapper for DCR diagnostics and SRE identity lock | `az bicep build --file main/hub/hubmain.bicep` |
| 2026-09-03 | `modules/hub/firewall-vnet.bicep` | Parameterized IP group lists, added optional zone parameters, fixed DNAT naming ambiguity, scoped route-table RBAC correctly, and converted the base Azure Firewall resource to `br/public:avm/res/network/azure-firewall:0.10.1`. Firewall Policy and rule collection groups remain custom for now. | `az bicep build --file main/hub/hubmain.bicep` |

## AVM-First Policy (for this repo)

1. Use AVM directly for Azure resources where AVM exists and meets requirements.
2. Keep custom modules only when they add orchestration/business logic AVM cannot express cleanly.
3. If a custom module is only wrapping AVM, prefer calling AVM directly from the parent template unless wrapper adds reusable policy/guardrails.
4. For each retained custom module, document why it is retained.

---

## Non-AVM Modules Flagged For Review

| Module Path | Calls | Current Role | AVM Opportunity | Recommendation | Priority |
|---|---:|---|---|---|---|
| ../../modules/hub/hubvnet.bicep | 1 | Hub VNet orchestration | Hybrid complete | Retain wrapper for firewall-routing and subnet orchestration; internals now use AVM route table and AVM VNet modules | Low |
| ../../modules/spokes/spokevnets.bicep | 3 | Spoke VNet orchestration | Hybrid complete | Retain wrapper for stable spoke contract; internals now use AVM route table and AVM VNet modules | Low |
| ../../modules/hub/vnet-peering.bicep | 1 | VNet peering logic | Keep custom | Retain custom module to preserve separate cross-subscription peering deployment and RBAC failure isolation | Low |
| ../../modules/hub/firewall-vnet.bicep | 1 | Azure Firewall + policy/rules orchestration | Hybrid in progress | Base firewall now uses AVM. Keep wrapper and custom policy/rule groups until firewall policy and rule collection group conversion can be compared safely. | Medium |
| ../../modules/hub/privatednslinks.bicep | 1 | Private DNS links orchestration | Likely yes | Review conversion to AVM/private DNS modules if parity exists | Medium |
| ../../modules/hub/failure-anomalies.bicep | 1 | App Insights smart detection rules | Partial/uncertain | Keep custom for now; verify AVM coverage before migration | Medium |
| ../../modules/hub/monitor-diag.bicep | 1 | DCR diagnostics + SRE identity lock | Partial AVM reduction complete | Keep custom for DCR diagnostics and lock; App Insights diagnostics now live in AVM App Insights module | Low |
| ../../modules/hub/network-diag.bicep | 1 | Network diagnostics settings | Partial | Consolidate into AVM-supported diagnostic settings where possible | Medium |
| ../../modules/hub/vm-diag.bicep | 1 | VM diagnostics settings | Partial | Replace with AVM-supported diagnostics on VM modules where possible | Medium |
| ../../modules/apps/vmDiag.bicep | 3 | App/SQL VM diagnostics wrapper | Partial | Replace wrapper with direct AVM diagnostics support if feasible | Medium |
| ../../platform/identity/mgnt-Identity.bicep | 1 | Managed identity + role orchestration | Partial | Keep custom for orchestration; optionally use AVM for identity resource creation inside module | Low |
| ./mg-policy.bicep | 1 | Management group policy orchestration | No direct one-size AVM fit | Keep custom; this is governance orchestration | Low |
| ./subscription-baseline.bicep | 1 | Subscription baseline orchestration | No direct one-size AVM fit | Keep custom | Low |
| ./resource-group-baseline.bicep | 1 | Resource group baseline orchestration | No direct one-size AVM fit | Keep custom | Low |
| ./mgnt-Identity.bicep | 1 | Identity orchestration wrapper | Partial | Same as platform identity note; retain for orchestration | Low |

---

## Proposed Conversion Waves

### Wave 1 (High impact, lowest disruption)
- Complete

### Wave 2 (Security/platform consistency)
- firewall-vnet.bicep (next: evaluate AVM firewall-policy and rule-collection-group modules)
- privatednslinks.bicep

### Wave 3 (Reduce wrapper indirection)
- apps/vmDiag.bicep and hub diag wrappers where AVM supports direct diagnostic settings

---

## Decision Log Template (use per module)

For each flagged module, record:
- Decision: Convert to AVM / Keep Custom / Hybrid
- Reason: Feature parity, orchestration complexity, cross-subscription handling, timeline
- Owner:
- Target sprint:
- Validation: what-if + deployment test + rollback plan

---

## Current Recommendation

Proceed with AVM-first in all new work. For existing custom modules, treat this document as a migration backlog and execute by wave to avoid destabilizing demo timelines.
