# Dotnet User Secrets Machine Spec (Abstract)

## Purpose

Standardize how machine-local secrets are managed using `dotnet user-secrets` for multiple .NET apps, including:

- App A on this machine (example: signal-router)
- App B on another host (example: app host)

This spec is environment-agnostic and can be reused across developer machines and non-production hosts.

## Important Boundary

`dotnet user-secrets` is a development/non-production secret store. For production, use a managed vault (for example Azure Key Vault, AWS Secrets Manager, HashiCorp Vault).

## Architecture Pattern

- One `UserSecretsId` per app/project.
- Shared secret key naming convention across apps.
- Machine bootstrap script applies required keys for each app.
- App configuration reads secrets via `AddUserSecrets` (development only).

## Secret Naming Convention

Use hierarchical keys:

- `ConnectionStrings:MainDb`
- `Auth:Jwt:Issuer`
- `Auth:Jwt:Audience`
- `Auth:Jwt:SigningKey`
- `SignalRouter:UpstreamBaseUrl`
- `SignalRouter:ApiKey`
- `Observability:Otlp:Endpoint`
- `Observability:Otlp:ApiKey`

## Prerequisites

1. .NET SDK installed (`dotnet --info`).
2. Repository cloned on host.
3. Each app has a `.csproj` file.

## Step 1: Enable User Secrets Per App

Run in each app project directory:

```bash
dotnet user-secrets init
```

Result: `UserSecretsId` is added to the project file.

Example project file snippet:

```xml
<PropertyGroup>
  <TargetFramework>net8.0</TargetFramework>
  <UserSecretsId>signal-router-local</UserSecretsId>
</PropertyGroup>
```

## Step 2: Define App Secret Contracts

Create a per-app contract table in docs:

| App | Required Key | Purpose | Example |
|---|---|---|---|
| signal-router | `SignalRouter:UpstreamBaseUrl` | upstream URL | `https://api.internal.local` |
| signal-router | `SignalRouter:ApiKey` | auth to upstream | `***` |
| app-host | `ConnectionStrings:MainDb` | DB connection | `Server=...` |
| app-host | `Auth:Jwt:SigningKey` | token signing | `***` |

## Step 3: Set Secrets On This Machine

Signal-router example (this machine):

```bash
cd /path/to/signal-router

dotnet user-secrets set "SignalRouter:UpstreamBaseUrl" "https://example.local"
dotnet user-secrets set "SignalRouter:ApiKey" "replace-me"
dotnet user-secrets list
```

App-host example (this machine, optional):

```bash
cd /path/to/app-host

dotnet user-secrets set "ConnectionStrings:MainDb" "Server=localhost;Database=app;User Id=app;Password=replace-me;"
dotnet user-secrets set "Auth:Jwt:SigningKey" "replace-me"
dotnet user-secrets list
```

## Step 4: Configure App Startup (Abstract)

In app startup, load user secrets only in development:

```csharp
var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>(optional: true);
}
```

Bind to options classes and validate on startup:

```csharp
builder.Services
    .AddOptions<SignalRouterOptions>()
    .Bind(builder.Configuration.GetSection("SignalRouter"))
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

## Step 5: Bootstrap Another Host (App B There)

On the other machine/host:

1. Install .NET SDK.
2. Clone repo.
3. Navigate to target app project.
4. Run `dotnet user-secrets init` (if not already initialized in project).
5. Apply the same contract keys with host-specific values.
6. Run `dotnet user-secrets list` to verify.
7. Start app and validate configuration binding.

## Optional: Scripted Bootstrap Template

Use a shell script per app:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${1:?project path required}"

cd "$PROJECT_PATH"
dotnet user-secrets set "SignalRouter:UpstreamBaseUrl" "${SIGNAL_ROUTER_UPSTREAM_BASE_URL:?missing}"
dotnet user-secrets set "SignalRouter:ApiKey" "${SIGNAL_ROUTER_API_KEY:?missing}"
dotnet user-secrets set "Observability:Otlp:Endpoint" "${OTLP_ENDPOINT:-}"
dotnet user-secrets set "Observability:Otlp:ApiKey" "${OTLP_API_KEY:-}"
dotnet user-secrets list
```

## Validation Checklist

- [ ] App project contains `UserSecretsId`.
- [ ] Required keys exist in `dotnet user-secrets list`.
- [ ] App starts without missing-config exceptions.
- [ ] Secrets are not present in source files.
- [ ] Logs do not print secret values.

## Rotation Procedure

1. Generate replacement secret value.
2. Update using `dotnet user-secrets set`.
3. Restart app process.
4. Run smoke tests for login, form submit, and logout.
5. Revoke old credential upstream.

## Incident Procedure

If secret leak is suspected:

1. Rotate all affected keys immediately.
2. Invalidate sessions/tokens if auth keys were exposed.
3. Audit recent logs and commits for leakage.
4. Document incident timeline and remediation.

## Quick Commands Reference

```bash
# Initialize
dotnet user-secrets init

# Set value
dotnet user-secrets set "Section:Key" "value"

# List all
dotnet user-secrets list

# Remove one
dotnet user-secrets remove "Section:Key"

# Clear all for project
dotnet user-secrets clear
```
