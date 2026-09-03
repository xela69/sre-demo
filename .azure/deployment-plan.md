# Azure Deployment Validation Plan

**Status:** Ready for Validation
**Mode:** Validate existing infrastructure orchestration
**IaC:** Bicep
**Execution boundary:** Compile, ARM validation, and what-if only. Do not deploy resources.

## 1. Scope

Validate the existing orchestrated phases in dependency order:

1. Tenant management: `platform/mngt/main.bicep` at tenant scope.
2. Management-group policy: `platform/policy/main.bicep` at management-group scope.
3. Platform identity: `platform/identity/main.bicep` at subscription scope.
4. Hub: `main/hub/hubmain.bicep` in subscription `ebc6a927-fe4b-49dc-8e99-3ffe8e8d01d9`, location `westus2`.
5. Data spoke: `main/data-spoke/datamain.bicep` in subscription `8de6c6e8-53af-4ded-a480-fd20c6093e78`, location `westus3`.
6. DC spoke: `main/dc-spoke/dcmain.bicep` in subscription `8de6c6e8-53af-4ded-a480-fd20c6093e78`, location `centralus`.
7. Apps spoke: `main/apps-spoke/appsmain.bicep` in subscription `42021d44-97d2-47a1-8245-a77149dda4c3`, location `centralus`.

Post-deployment scripts are excluded because they mutate resources and are not ARM/Bicep what-if phases.

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

Pending execution.

## 5. Deployment

Not approved and not requested. A separate explicit approval is required after all validation failures are resolved.
