# Azure Deployment Validation Plan

**Status:** Dual-tenant validation passed; tenant-scope phase remains blocked
**Mode:** Validate existing infrastructure orchestration
**IaC:** Bicep
**Execution boundary:** Compile, ARM validation, and what-if only. Do not deploy resources.

## 1. Scope

Validate the existing orchestrated phases in dependency order:

1. Tenant management: `platform/mngt/main.bicep` at tenant scope.
2. Management-group policy: `platform/policy/main.bicep` at management-group scope.
3. Platform identity: `platform/identity/main.bicep` at subscription scope.
4. Hub: `main/hub/hubmain.bicep` in subscription `ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9`, location `westus2`.
5. TenantB source network: `main/tenantb/tenantbmain.bicep` in the Xelatech tenant subscription `ed70102f-f789-4d4e-ac00-074283844a0c`, location `westus2`.
6. DC spoke: `main/dc-spoke/dcmain.bicep` in subscription `8de6c6e8-53af-4ded-a480-fd20c6093e78`, location `centralus`.
7. Apps spoke: `main/apps-spoke/appsmain.bicep` in subscription `42021d44-97d2-47a1-8245-a77149dda4c3`, location `centralus`.

Post-deployment scripts are excluded because they mutate resources and are not ARM/Bicep what-if phases.

The former MCAPS data-spoke phase is retired from the active architecture. TenantB and MCAPS are validated independently and exchange only VPN endpoint metadata, static address prefixes, and an out-of-band PSK.

## 2. Existing Inputs

- Use checked-in parameter files where populated.
- Supply required secure parameters from local files or ephemeral environment variables; never record secret values.
- Use the subscription IDs and locations already declared by the repository orchestration.
- Tenant and management-group validations run only when their required target identifiers are available from the current Azure context and checked-in parameters.

## 3. Validation Steps

- Verify Azure CLI authentication and access to all target subscriptions.
- Compile every top-level Bicep entry point.
- Run scope-appropriate ARM validation for every phase with complete inputs.
- Run scope-appropriate what-if for every phase with complete inputs.
- Record pass, fail, or blocked status and the actionable diagnostic for each phase.
- Do not run any `create` command unless it includes `--what-if`; do not run post-deployment scripts.

## 4. Validation Proof

Executed 2026-09-03 against MCAPS tenant `e2703bc7-74fd-40a0-8d0b-761571d44939` as `arnold@MngEnvMCAP833156.onmicrosoft.com`.

All seven entry points compiled successfully. `platform/mngt/main.bicep` emitted two BCP318 warnings for conditional module output access; the other entry points emitted no compiler diagnostics.

| Phase | ARM validation | What-if result | Notes |
| --- | --- | --- | --- |
| Tenant management | Blocked | Blocked | The principal lacks `Microsoft.Resources/deployments/validate/action` and `Microsoft.Resources/deployments/whatIf/action` at tenant scope `/`. It is Owner at the tenant-root management group, which is a different scope. |
| Management-group policy | Passed | Passed: 0 changes | Evaluated at the existing `Infra-grp` management group. The checked-in policy parameters are empty. |
| Platform identity | Passed | Passed: 8 creates | Evaluated in the Infra-hub subscription. |
| Hub | Passed | Passed: 171 creates, 1 deploy, 14 unsupported | Revalidated with the TenantB VPN contract. No deletes were reported. The 14 unsupported analyses are role assignments whose IDs depend on identities created during deployment. |
| TenantB source network | Passed | Passed: 9 creates | Validated independently in the Xelatech `vsCode_Subs` subscription with FortiGate BYOL (evaluation mode). No deletes or unsupported changes were reported. |
| DC spoke | Passed | Passed: 0 changes | No changes were reported. |
| Apps spoke | Passed | Passed: 52 creates, 2 unsupported | No deletes were reported. |

Validation used `az deployment tenant|mg|sub validate` followed by the matching `what-if` command with `ResourceIdOnly` output. Required passwords and SSH keys were read from local secure inputs and were not printed or recorded.

A static RBAC scan found role assignments scoped through the owning modules and using built-in role IDs or names. Provider validation passed for the policy, identity, hub, DC, and apps phases. No deployment or post-deployment command was executed.

TenantB and MCAPS were revalidated together on 2026-09-04 with `scripts/validate-dual-tenant.sh`. The TenantB template supports a `licenseModel` toggle. The chosen deployment model is **BYOL (default)** hosted in the Visual Studio subscription `ed70102f-f789-4d4e-ac00-074283844a0c` (`vsCode_Subs`):

- **BYOL (default, chosen):** uses the free ($0) FortiGate Marketplace plan `fortinet_fg-vm`, version `7.4.9`. With no license supplied (`fortigateLicenseContent` empty), the appliance runs in **evaluation mode**, which has **no expiry timer** but is feature-limited (approximately 1 vCPU, throttled throughput, no FortiGuard updates or support). This satisfies the ongoing/no-reset demo need on `vsCode_Subs`, which cannot use PAYG. For full features, inject a Fortinet 15-day free-trial `.lic` via `fortigateLicenseContent` (the trial clock is bound to the FortiCloud license registration, not the VM).
- **PAYG (toggle, not usable on vsCode_Subs):** bundles the license into hourly billing and needs no license file, but requires a subscription with a supported payment instrument. `vsCode_Subs` fails Marketplace eligibility with `The 'unknown' payment instrument(s) is not supported`. `Hub_Subs` and `XelaCorp_Subs` are PAYG-eligible if this model is ever needed.

The FortiGate VM size is `Standard_D2s_v5` (2 vCPU / 8 GB, two NICs), which has quota in `westus2` on `vsCode_Subs`. Note: `standardDSv5Family` has a 0-core quota on `XelaCorp_Subs`, so a PAYG move there would require `Standard_D2s_v4` instead.

Open verification: whether unlicensed evaluation mode supports the site-to-site IPsec tunnel to MCAPS at a usable level must be confirmed hands-on after deployment; the 15-day trial `.lic` is the documented fallback if eval mode is too restrictive.

The MCAPS preview used documentation-only peer IP `192.0.2.10`. Supply `TENANTB_FORTIGATE_PUBLIC_IP` from the deployed TenantB static public IP before deployment.

Blocking remediation:

1. Grant the validating principal tenant-scope deployment permissions at `/`, or run the tenant phase with a principal that already has them.

## 5. Deployment

Not yet executed. A separate explicit approval is required before any deployment command runs.

### Agreed deployment sequence

MCAPS tenant is deployed first; the Xelatech `vsCode_Subs` TenantB source is deployed last, when VPN and Arc functionality are needed. The VPN is a two-way public-IP exchange, so the MCAPS VPN connection cannot be finalized until the TenantB FortiGate public IP exists. The SRE agent is registered and wired into MCAPS before TenantB, so the monitoring/analytics stack is live and the demo can observe the environment as it comes up.

1. **MCAPS core (first):** deploy hub, then DC and apps spokes. The VPN gateway provisions here and can take 30-45 minutes, so start it early. At this stage the MCAPS Local Network Gateway uses a placeholder peer IP. The hub deploy also stands up the SRE supporting infrastructure in `hubRG-Monitor`: Log Analytics, App Insights (`xelaAppsInsightfhmo`), DCRs/VM Insights, and the ADX/Kusto cluster (`xelaadx<suffix>`, database `sredb`). On this first pass leave `sreAgentIdentityName` and `sreAgentPrincipalId` empty — the agent identity does not exist yet.
2. **Register the SRE agent (MCAPS, before TenantB):** create the `sre-demo` agent at sre.azure.com (portal wizard, ~2-5 min) against hub subscription `ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9`, West US 2, using the existing `xelaAppsInsightfhmo` App Insights. The portal provisions the `sre-demo-<suffix>` managed identity in `hubRG-Monitor`.
3. **Wire the SRE agent into IaC (MCAPS):** run `./scripts/azcli/sre-agent-rewire.sh` to auto-discover the new identity name and principal ID, update `docs/sre-agent-config.txt`, and redeploy `main/hub/hubmain.bicep` with `sreAgentIdentityName` and `sreAgentPrincipalId` set. This applies the `CanNotDelete` lock on the identity and grants it `AllDatabasesViewer` on the ADX cluster. Then restore the portal-only connectors (ADX: `https://xelaadx<suffix>.westus2.kusto.windows.net` / `sredb`; GitHub OAuth) and grant the agent Azure resource access across the hub and apps subscriptions.
4. **TenantB (last):** deploy `main/tenantb/tenantbmain.bicep` into `vsCode_Subs` (BYOL evaluation mode). This creates the FortiGate and its **static public IP** (`TenantB-FortiGate-PIP`), exposed as the `tenantBFortigatePublicIp` output.
5. **Wire MCAPS to the real peer:** re-run the MCAPS hub deployment with `tenantBFortigatePublicIp` set to the deployed FortiGate public IP so the Local Network Gateway and connection point to TenantB. Keep `sreAgentIdentityName`/`sreAgentPrincipalId` populated so the SRE wiring is preserved.
6. **Configure FortiGate (FortiOS):** set the MCAPS VPN gateway public IP, the shared PSK, IKEv2/IPsec parameters, and static routes to the MCAPS prefixes via the tunnel.
7. **Bring up and verify the tunnel:** confirm the IPsec tunnel establishes and passes traffic both directions. If evaluation mode is too restrictive, inject the 15-day FortiCloud trial `.lic` via `fortigateLicenseContent` and redeploy TenantB.
8. **Arc functionality (last):** onboard the TenantB source servers to Azure Arc once the tunnel is up.

> SRE agent recovery note: before any MCAPS teardown, run `./scripts/azcli/sre-agent-snapshot.sh` to capture the identity into `docs/sre-agent-config.txt`. `hubRG-Monitor` is preserved across rebuilds so the agent, ADX, and monitoring survive lab teardown cycles.

Secrets (`FORTIGATE_ADMIN_PASSWORD`, `VPN_SHARED_KEY`, `MCAPS_ACCESS_KEY`, and any `.lic`) are read from local ignored files and are never committed or printed.
