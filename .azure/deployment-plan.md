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
| TenantB source network | Passed | Passed: 9 creates | Validated independently in the Xelatech subscription. No deletes or unsupported changes were reported. |
| DC spoke | Passed | Passed: 0 changes | No changes were reported. |
| Apps spoke | Passed | Passed: 52 creates, 2 unsupported | No deletes were reported. |

Validation used `az deployment tenant|mg|sub validate` followed by the matching `what-if` command with `ResourceIdOnly` output. Required passwords and SSH keys were read from local secure inputs and were not printed or recorded.

A static RBAC scan found role assignments scoped through the owning modules and using built-in role IDs or names. Provider validation passed for the policy, identity, hub, DC, and apps phases. No deployment or post-deployment command was executed.

TenantB and MCAPS were revalidated together on 2026-09-03 with `scripts/validate-dual-tenant.sh`. The initial TenantB validation reached ARM but the FortiGate PAYG plan was rejected because the Visual Studio subscription does not support its Marketplace payment instrument. The TenantB template now defaults to FortiGate BYOL plan `fortinet_fg-vm`, version `7.4.9`; Marketplace terms were accepted and both ARM validations and what-if previews passed.

The MCAPS preview used documentation-only peer IP `192.0.2.10`. Supply `TENANTB_FORTIGATE_PUBLIC_IP` from the deployed TenantB static public IP before deployment. FortiGate BYOL also requires a valid Fortinet license before the appliance can become operational.

Blocking remediation:

1. Grant the validating principal tenant-scope deployment permissions at `/`, or run the tenant phase with a principal that already has them.

## 5. Deployment

Not approved and not requested. A separate explicit approval is required after all validation failures are resolved.
