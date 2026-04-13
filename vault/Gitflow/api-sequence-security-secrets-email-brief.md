# Email Brief: Angular API Sequence + Security Audit + Secrets Management

## Subject

Angular API Sequence Plan + Security Audit Spec + Dotnet User Secrets Rollout

## Body

Team,

Prepared a consolidated spec package for tomorrow covering API call order, security audit execution, and machine-level secret handling.

## What is included

1. API sequence documentation template for Angular -> Backend calls in user-order:
   - App boot
   - Login form submission
   - Redirect load
   - Form navigation and submit
   - Logout

2. Security audit spec to validate those flows before release:
   - Scope and threat-model baseline
   - SAST/dependency checks
   - DAST/negative testing
   - Manual review checklist
   - Evidence artifacts and sign-off criteria

3. Abstract dotnet user-secrets machine spec for .NET apps:
   - Standard `UserSecretsId` model per app
   - Shared secret key naming conventions
   - Setup steps for this machine (signal-router)
   - Equivalent setup steps for another machine/host (app-host)
   - Startup wiring (`AddUserSecrets` in Development)
   - Rotation and incident playbooks

## Primary outcomes

- We can diagram API behavior in exact sequence order (boot + click-driven paths).
- We have a repeatable security audit process tied to those exact endpoints.
- We have a portable, host-agnostic way to manage local development secrets for multiple .NET apps.

## Artifact links

- API sequence template: [api-call-waterfall-template.md](api-call-waterfall-template.md)
- Security audit spec: [api-security-audit-spec.md](api-security-audit-spec.md)
- Dotnet user-secrets spec: [dotnet-user-secrets-machine-spec.md](dotnet-user-secrets-machine-spec.md)

## Suggested execution order

1. Fill endpoint details in the API sequence template.
2. Run security audit pipeline against the finalized endpoint inventory.
3. Apply machine bootstrap for dotnet user-secrets on this machine and target host.
4. Validate login, redirect, form submit, and logout smoke tests.

## Decisions needed

- Final endpoint list and environments in scope.
- Security gate thresholds (what blocks release).
- Secret ownership and rotation cadence by app.

Thanks.
