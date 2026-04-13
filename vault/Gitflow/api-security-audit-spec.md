# API Security Audit Spec

## Purpose

Define a repeatable security audit process for Angular -> Backend API flows, focused on boot, login, redirect navigation, form navigation + submission, and logout.

## Scope

- Frontend: Angular app routes and HTTP clients.
- Backend: Authentication, authorization, validation, API handlers, data persistence, session/token management.
- Endpoints in scope:
  - `GET /api/config`
  - `GET /api/session`
  - `POST /api/auth/login`
  - `GET /api/me`
  - `GET /api/dashboard`
  - `GET /api/forms/{id}`
  - `GET /api/forms/{id}/options`
  - `POST /api/forms/{id}/submissions`
  - `POST /api/auth/logout`

## Audit Objectives

1. Verify no high-severity issues are present before release.
2. Validate authn/authz boundaries for each API step.
3. Ensure input validation and output encoding across login and form submission flows.
4. Confirm secure session lifecycle: create, refresh, revoke, logout.
5. Produce evidence artifacts suitable for review and handoff.

## Threat Model Baseline

- Actors: anonymous user, authenticated user, admin user, malicious actor.
- Assets: credentials, tokens/cookies, PII in forms, audit logs.
- Trust boundaries:
  - Browser <-> API
  - API <-> Database
  - API <-> External identity provider (if used)
- Primary risks:
  - Broken auth (OWASP A01)
  - Crypto failures (OWASP A02)
  - Injection (OWASP A03)
  - Security misconfiguration (OWASP A05)
  - Identification and auth failures (OWASP A07)
  - Logging/monitoring failures (OWASP A09)

## Security Controls Checklist By Flow

### Boot + Session Check

- `GET /api/config` returns no secrets.
- `GET /api/session` exposes only minimal session metadata.
- Cache headers are safe for auth-related responses.
- CORS policy is restricted to approved origins.

### Login + Redirect

- Rate limiting present on `POST /api/auth/login`.
- Credential validation is server-side and constant-time where feasible.
- Session cookie flags: `HttpOnly`, `Secure`, `SameSite`.
- Token expiry and refresh strategy documented.
- Open redirect protections on redirect targets.

### Form Navigation + Submit

- Form schema endpoints are authorization-guarded.
- Submission payload is schema-validated server-side.
- Input sanitization and parameterized queries are enforced.
- Business-rule validation failures map to safe error payloads.
- Idempotency/replay strategy defined where needed.

### Logout

- Logout endpoint invalidates session/token server-side.
- Client clears local state reliably.
- Protected routes fail closed after logout.

## Audit Pipeline Spec

### Stage 1: Static Analysis (SAST + Dependency)

Run on every PR and nightly:

```bash
# JavaScript/TypeScript dependency audit
pnpm audit --prod

# .NET dependency audit (if backend is .NET)
dotnet list package --vulnerable --include-transitive

# Optional SAST hooks (choose stack tooling)
# snyk code test
# semgrep --config auto
```

Pass criteria:

- No new critical/high vulnerabilities.
- No unresolved auth/session misconfiguration findings.

### Stage 2: API Security Tests (DAST/Negative Tests)

Execute against a non-production environment:

1. Invalid credential brute-force behavior (lockout/rate-limit).
2. Token/cookie tampering and replay attempts.
3. IDOR checks on forms and submission endpoints.
4. Input fuzzing for injection and over-posting.
5. Logout then access protected resource (must return `401/403`).

Suggested tooling:

- OWASP ZAP baseline scan for API endpoints.
- Postman/Newman or integration test suite with negative test cases.

### Stage 3: Manual Review

1. Review auth middleware order.
2. Review CORS and HTTPS enforcement.
3. Review secret usage (no hardcoded secrets).
4. Review logging for PII/token leakage.

## Evidence Artifacts (Required)

- Sequence diagram snapshot used for audit scope.
- Endpoint inventory with auth requirements.
- SAST/dependency scan outputs.
- DAST/negative test report.
- Risk register with severity, owner, ETA.
- Sign-off checklist.

## Sign-Off Checklist

- [ ] Critical findings resolved.
- [ ] High findings resolved or approved exception with expiry.
- [ ] Session/login/logout tests pass.
- [ ] Form submit validation and authorization tests pass.
- [ ] Evidence artifacts attached to release ticket.

## Exception Process

For unresolved high-risk issues:

- Document risk and exploitability.
- Add temporary compensating controls.
- Set explicit expiration date and owner.
- Obtain security owner approval.

## Deliverable Template

### Audit Summary

- System:
- Environment:
- Date:
- Reviewer(s):
- Result: Pass / Conditional Pass / Fail

### Findings

| ID | Severity | Endpoint/Area | Description | Owner | Target Date | Status |
|---|---|---|---|---|---|---|
| SEC-001 | High | /api/auth/login | Example finding | Team A | 2026-04-20 | Open |

### Decision

- Release recommendation:
- Conditions (if any):
- Next review date:
