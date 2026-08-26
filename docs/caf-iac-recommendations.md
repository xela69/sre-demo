# SRE-Demo CAF + IaC Recommendations Backlog

Date: 2026-08-25
Scope: Architecture (CAF/WAF) and Bicep IaC review
Purpose: Keep a practical hardening backlog while the environment remains demo-first.

## How To Use This File

- Demo now: keep items marked as "Defer" documented with risk notes.
- Production prep: complete all "Critical" and "High" items before go-live.
- Track status per item: `Open`, `In Progress`, `Done`, `Deferred (Demo)`.

---

## Priority 0 - Critical Before Production

### 1) Remove secrets and passwords from docs and examples
Status: Open  
Severity: Critical  
Evidence:
- docs/architecture.md contains explicit lab password examples and local secret file usage.
Actions:
- Remove inline credential values from docs.
- Replace with placeholders and secure retrieval instructions.
- Rotate any credentials that were exposed.

### 2) Harden Key Vault deletion protections
Status: Open  
Severity: Critical  
Evidence:
- main/hub/hubmain.bicep currently sets purge protection disabled and low retention.
- modules/hub/keyvault.bicep has soft delete disabled.
Actions:
- Set soft delete enabled.
- Set soft delete retention to 90 days.
- Set purge protection enabled for production.

### 3) Eliminate nondeterministic image versions
Status: Open  
Severity: Critical  
Evidence:
- Multiple files use image `version: 'latest'`.
Actions:
- Pin image versions for Windows/Linux base images.
- Create a periodic update process (quarterly review).

---

## Priority 1 - High Value Hardening

### 4) Restrict public network access on sensitive services
Status: Open  
Severity: High  
Evidence:
- Public access enabled in several service definitions (Key Vault/ACR/ADX/others).
Actions:
- Disable public network access where possible.
- Use private endpoints and private DNS links.
- Keep explicit exceptions documented for demo scenarios.

### 5) Enable encryption-at-host for VM workloads
Status: Open  
Severity: High  
Evidence:
- VM definitions currently set encryption-at-host to false in multiple spokes/hub paths.
Actions:
- Enable feature on subscription.
- Set encryption-at-host true for eligible VM resources.
- Document exceptions if SKU/region constraints exist.

### 6) Enforce governance policy assignments
Status: Open  
Severity: High  
Evidence:
- platform/policy/main.bicep has framework support but empty defaults.
Actions:
- Add baseline policy definitions/initiatives and assignments:
  - Required tags
  - Allowed locations/SKUs
  - Encryption requirements
  - Public network restrictions

### 7) Add backup and recovery baseline
Status: Open  
Severity: High  
Evidence:
- No clear backup policy baseline for VM/SQL demo workloads.
Actions:
- Define backup policy by workload tier.
- Add restore test cadence and RTO/RPO notes in docs.

---

## Priority 2 - Medium Improvements

### 8) Standardize API versions
Status: Open  
Severity: Medium  
Evidence:
- Wide mix of API versions and preview usage across modules.
Actions:
- Prefer stable API versions for production paths.
- Keep a documented API version policy and update cadence.

### 9) Parameterize hardcoded network/IP values
Status: Open  
Severity: Medium  
Evidence:
- Firewall and related modules contain hardcoded address lists.
Actions:
- Move mutable network values into parameters/parameter files.
- Keep environment-specific defaults in dedicated env parameter files.

### 10) Tighten Bicep linting gates for release pipeline
Status: Open  
Severity: Medium  
Evidence:
- bicepconfig has useful rules but many are warnings.
Actions:
- Promote key warnings to errors in CI for production branch.
- Add pre-deploy validation and what-if checks as required pipeline steps.

### 11) Improve naming, descriptions, and validations
Status: Open  
Severity: Medium  
Actions:
- Add @description consistently to parameters/outputs.
- Add input validation decorators (@allowed, @minLength, @maxLength).
- Keep naming convention guide in docs.

---

## Demo-Mode Exceptions (Documented Risk Acceptance)

Use this section to record temporary exceptions while staying demo-first.

- Public network access temporarily enabled for selected services:
  Status: Deferred (Demo)
  Exit criteria: private endpoints configured and validated.

- Purge protection relaxed in some environments:
  Status: Deferred (Demo)
  Exit criteria: production subscription uses purge protection enabled.

- `latest` image usage for rapid demo iteration:
  Status: Deferred (Demo)
  Exit criteria: pinned image matrix established for production.

---

## Suggested Execution Plan

### Phase A (1-2 days)
- Remove credential leakage from docs.
- Key Vault deletion protection fixes.
- Pin critical VM image versions.

### Phase B (2-4 days)
- Public access reduction + private endpoints for highest-risk services.
- Enable encryption-at-host where supported.
- Add baseline policy assignments.

### Phase C (next sprint)
- API version normalization.
- Parameterization cleanup.
- Lint/validation CI gate hardening.

---

## Sign-off Checklist For “Ready Deploy”

- [ ] No credentials in markdown or committed parameter files.
- [ ] Key Vault deletion protections aligned with production baseline.
- [ ] VM and data plane encryption baselines met.
- [ ] Public endpoints minimized with justified exceptions only.
- [ ] Governance policy assignments active at intended scope.
- [ ] Reproducible image/version strategy implemented.
- [ ] Pre-deploy validation pipeline enforced.
