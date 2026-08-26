# SRE-Demo AVM-First Module Review

Date: 2026-08-25
Goal: Prefer Azure Verified Modules (AVM) wherever practical, and flag non-AVM modules for conversion or explicit retention.

## Summary

- Total module invocations in Bicep: 48
- AVM module invocations: 27
- Non-AVM module invocations: 21
- AVM adoption by invocation: 56.25%

## AVM-First Policy (for this repo)

1. Use AVM directly for Azure resources where AVM exists and meets requirements.
2. Keep custom modules only when they add orchestration/business logic AVM cannot express cleanly.
3. If a custom module is only wrapping AVM, prefer calling AVM directly from the parent template unless wrapper adds reusable policy/guardrails.
4. For each retained custom module, document why it is retained.

---

## Non-AVM Modules Flagged For Review

| Module Path | Calls | Current Role | AVM Opportunity | Recommendation | Priority |
|---|---:|---|---|---|---|
| ../../modules/hub/hubvnet.bicep | 1 | Hub VNet build, subnets/UDR composition | Likely yes (VNet AVM) | Review for conversion if custom route composition can be preserved via params/child modules | High |
| ../../modules/spokes/spokevnets.bicep | 3 | Spoke VNet creation | Likely yes (VNet AVM) | Convert to AVM for consistency across spokes if feature parity confirmed | High |
| ../../modules/hub/vnet-peering.bicep | 1 | VNet peering logic | Likely yes (peering AVM or child resource pattern) | Review for AVM conversion; retain only if cross-subscription orchestration is cleaner custom | High |
| ../../modules/hub/firewall-vnet.bicep | 1 | Azure Firewall + policy/rules orchestration | Likely yes (Firewall AVM exists, rules may still be custom) | Hybrid approach: AVM for base firewall resource, keep custom rule collections if needed | High |
| ../../modules/hub/privatednslinks.bicep | 1 | Private DNS links orchestration | Likely yes | Review conversion to AVM/private DNS modules if parity exists | Medium |
| ../../modules/hub/failure-anomalies.bicep | 1 | App Insights smart detection rules | Partial/uncertain | Keep custom for now; verify AVM coverage before migration | Medium |
| ../../modules/hub/monitor-diag.bicep | 1 | Diagnostic settings + lock/orchestration | Partial | Keep custom unless AVM extension modules fully cover lock + diagnostics flow | Medium |
| ../../modules/hub/network-diag.bicep | 1 | Network diagnostics settings | Partial | Consolidate into AVM-supported diagnostic settings where possible | Medium |
| ../../modules/hub/vm-diag.bicep | 1 | VM diagnostics settings | Partial | Replace with AVM-supported diagnostics on VM modules where possible | Medium |
| ../../modules/apps/vmDiag.bicep | 3 | App/SQL VM diagnostics wrapper | Partial | Replace wrapper with direct AVM diagnostics support if feasible | Medium |
| ../../modules/apps/containerApp.bicep | 1 | Wrapper around AVM managed environment + container app | Yes (already AVM inside) | Consider removing wrapper and calling AVM directly from parent if no unique logic retained | Medium |
| ../../modules/apps/grubifyFrontend.bicep | 1 | Wrapper around AVM container app | Yes (already AVM inside) | Same as above: flatten wrapper if no unique logic retained | Medium |
| ../../platform/identity/mgnt-Identity.bicep | 1 | Managed identity + role orchestration | Partial | Keep custom for orchestration; optionally use AVM for identity resource creation inside module | Low |
| ./mg-policy.bicep | 1 | Management group policy orchestration | No direct one-size AVM fit | Keep custom; this is governance orchestration | Low |
| ./subscription-baseline.bicep | 1 | Subscription baseline orchestration | No direct one-size AVM fit | Keep custom | Low |
| ./resource-group-baseline.bicep | 1 | Resource group baseline orchestration | No direct one-size AVM fit | Keep custom | Low |
| ./mgnt-Identity.bicep | 1 | Identity orchestration wrapper | Partial | Same as platform identity note; retain for orchestration | Low |

---

## Proposed Conversion Waves

### Wave 1 (High impact, lowest disruption)
- spokevnets.bicep
- vnet-peering.bicep
- hubvnet.bicep (if parity confirmed)

### Wave 2 (Security/platform consistency)
- firewall-vnet.bicep (hybrid AVM base + custom policy rules)
- privatednslinks.bicep

### Wave 3 (Reduce wrapper indirection)
- apps/containerApp.bicep
- apps/grubifyFrontend.bicep
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
