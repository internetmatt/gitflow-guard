# @internetmatt/gitflow-guard

GitFlow branch enforcement, hook orchestration, and commit journaling for monorepos.

## What it does

- **Branch naming enforcement** — validates branch names against GitFlow conventions (`feature/*`, `story/*`, `release/*`, `hotfix/*`)
- **Push policy** — blocks direct pushes to `main` (requires `release/*` or `hotfix/*` merges), warns on direct `dev` commits
- **Commit journaling** — logs every commit as JSONL to a configurable vault directory for audit trails
- **Auto-pull on checkout** — fast-forwards protected branches (`main`, `dev`, `release/*`) on checkout
- **Conventional commit prefixing** — auto-detects commit type and scope from staged files
- **Automation integration** — fires commit/merge events to any automation endpoint or local skill command
- **Configurable presets** — ships with `standard`, `projects`, and `minimal` presets 

## Install

```bash
npm install -g @internetmatt/gitflow-guard
# or
pnpm add -g @internetmatt/gitflow-guard
```

## Quick start

```bash
cd your-repo
gitflow-guard init                      # Install with default (standard) preset
gitflow-guard init --preset projects    # Install with NX typecheck/lint pre-commit
gitflow-guard init --preset minimal     # Just branch guard + push policy
```

## Priority chaining with existing repo hooks

gitflow-guard installs as the first block in each hook and then chains to whatever hook logic already exists in the repository.

- `pre-commit` and `pre-push` are blocking gates (non-zero exits stop commit/push)
- `post-*` and `prepare-commit-msg` remain non-blocking (`|| true` behavior)
- Re-running `gitflow-guard init` reorders existing managed blocks to the top if needed

Recommended rollout order for mixed environments (`Projects`, `Prd`, `Vault`):

1. Install gitflow-guard first in each repo.
2. Reinstall/refresh your repo-local hook installers after that.
3. Verify with `gitflow-guard status` and by inspecting `.git/hooks/pre-commit` + `.git/hooks/pre-push`.

Example:

```bash
# Projects repo
cd ~/Projects
gitflow-guard init --preset projects

# Vault repo
cd /path/to/vault
gitflow-guard init --preset minimal
```

If your repo has its own installer (for example `.projects/hooks/install-gitflow-hooks.sh`), run it after `gitflow-guard init` so custom runners/automation hooks remain chained behind gitflow-guard policy checks.

## Commands

| Command | Description |
|---------|-------------|
| `gitflow-guard init [--preset <name>]` | Install hooks |
| `gitflow-guard remove` | Uninstall hooks |
| `gitflow-guard status` | Show installation status |
| `gitflow-guard check-branch` | Validate current branch name |
| `gitflow-guard check-push` | Validate push against policy |
| `gitflow-guard run-hook <name>` | Execute a hook directly |

## Configuration

Create `.gitflow-guard.json` in your repo root (auto-created by `init`):

```json
{
  "preset": "standard",
  "strict": false,
  "hooks": {
    "pre-commit": { "enabled": true },
    "pre-push": { "enabled": true },
    "post-commit": { "enabled": true },
    "post-merge": { "enabled": true },
    "post-checkout": { "enabled": true },
    "prepare-commit-msg": { "enabled": true }
  },
  "journal": {
    "enabled": true,
    "dir": "Vault/Gitflow",
    "logFile": ".commit-log.jsonl"
  },
  "automation": {
    "enabled": true,
    "url": "http://localhost:9000/api/automation",
    "eventPath": "/events",
    "triggerPath": "/triage",
    "profile": "local-skill-runner",
    "profiles": {
      "local-skill-runner": {
        "enabled": true,
        "url": "http://localhost:9000/api/automation",
        "eventPath": "/events",
        "triggerPath": "/triage",
        "skillCommand": "pnpm run skills:execute gitflow-events --json-params"
      },
      "project": {
        "enabled": true,
        "url": "http://localhost:4715/api/orchestrator",
        "eventPath": "/events",
        "triggerPath": "/triage",
        "skillCommand": "pnpm run skills:execute project-runtime-gitflow-orchestrator --json-params"
      }
    }
  },
  "prePush": {
    "driftCheck": {
      "enabled": false,
      "script": "pnpm run drift:check",
      "strict": false
    }
  },
  "preCommit": {
    "typecheck": {
      "enabled": true,
      "command": "NX_DAEMON=false pnpm exec nx run-many --targets=typecheck --parallel=1"
    },
    "lint": {
      "enabled": true,
      "command": "pnpm exec eslint --max-warnings 0",
      "stagedOnly": true,
      "extensions": [".ts", ".tsx", ".js", ".jsx"]
    }
  }
}
```

## Presets

### `standard` (default)
Full hook suite with commit journaling to `Vault/Gitflow`, generic automation integration, SQL boundary checks, and conventional commit prefixing.

### `project` (compat alias)
Alias of `standard`. Use this only when migrating existing repositories.

### `projects`
NX monorepo preset — adds typecheck and ESLint as pre-commit gates, automation on port 9000, container dual-mode support.

### `minimal`
Branch guard + push policy only. No journaling, no automation, no post-commit hooks.

## Branch naming rules

| Pattern | Example | Rule |
|---------|---------|------|
| `main` / `dev` | — | Protected; direct commits warned |
| `feature/<slug>` | `feature/portal-federation` | Lowercase alphanumeric + hyphens |
| `story/<feature>/<id>` | `story/portal/123` | Nested under feature |
| `release/<semver>` | `release/1.0.0-rc.1` | Semantic version |
| `hotfix/<slug>` | `hotfix/auth-token-expiry` | Lowercase alphanumeric + hyphens |

## Push merge rules

```
main      ← release/*, hotfix/*  only
dev       ← feature/*            only (direct commits warned)
feature/* ← story/*              only
release/* ← dev, hotfix/*        only
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GITFLOW_STRICT` | `0` | Set to `1` to block commits on invalid branch names |
| `GITFLOW_GUARD_CONFIG` | `.gitflow-guard.json` | Path to config file |
| `GITFLOW_GUARD_DRIFT_CHECK` | `1` | Set to `0` to skip pre-push drift checks |
| `GITFLOW_GUARD_ROOT` | auto-detected | Repo root override |

## Hooks installed

| Git hook | Script | Behavior |
|----------|--------|----------|
| `pre-commit` | `branch-guard.sh` | Validates branch name, runs custom checks |
| `pre-push` | `pre-push-gitflow.sh` | Enforces merge rules, optional drift checks |
| `post-commit` | `post-commit-gitflow.sh` | Journals commit metadata, notifies automation target |
| `post-merge` | `post-merge-gitflow.sh` | Notifies automation target of merge events |
| `post-checkout` | `post-checkout-autopull.sh` | Auto-pulls protected branches |
| `prepare-commit-msg` | `prepare-commit-msg-gitflow.sh` | Auto-prefixes conventional commits |

## CI parity template (Azure Pipelines)

Use the same order in CI that you enforce locally:

1. Gitflow policy checks (`check-branch`, `check-push`)
2. Repo test runners (Nx, unit/integration)
3. Playwright workspace E2E
4. Publish artifacts to Azure Storage

Minimal stage example:

```yaml
stages:
  - stage: ValidateAndTest
    jobs:
      - job: sdlc
        pool:
          vmImage: ubuntu-latest
        steps:
          - checkout: self
            fetchDepth: 0

          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'

          - script: corepack enable
            displayName: Enable package managers

          - script: pnpm install --frozen-lockfile
            displayName: Install dependencies

          - script: |
              pnpm dlx @internetmatt/gitflow-guard check-branch
              pnpm dlx @internetmatt/gitflow-guard check-push
            displayName: Gitflow policy gates

          - script: NX_DAEMON=false pnpm exec nx affected -t test --base main
            displayName: Affected tests

          - checkout: git://yourProject/playwright-workspace
            path: playwright-workspace

          - script: |
              cd $(Build.SourcesDirectory)/playwright-workspace
              pnpm install --frozen-lockfile
              pnpm exec playwright test
            displayName: Playwright E2E

          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(Build.SourcesDirectory)/playwright-workspace/playwright-report'
              artifact: 'playwright-report'

          - task: AzureCLI@2
            inputs:
              azureSubscription: 'YOUR-SERVICE-CONNECTION'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                az storage blob upload-batch \
                  --account-name "$AZURE_STORAGE_ACCOUNT" \
                  --destination "playwright-evidence/$(Build.BuildNumber)" \
                  --source "$(Build.SourcesDirectory)/playwright-workspace/test-results"
            env:
              AZURE_STORAGE_ACCOUNT: $(AZURE_STORAGE_ACCOUNT)
```

## Programmatic API

```javascript
import { installHooks, statusHooks, loadConfig } from "@internetmatt/gitflow-guard";

const root = process.cwd();
const config = loadConfig(root);
installHooks(root, "standard", config);
```

## Verify CLI Commits On GitHub

1. Push the branch:

```bash
git push -u origin "$(git branch --show-current)"
```

2. Confirm the latest commit exists remotely:

```bash
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git ls-remote --heads origin "$(git branch --show-current)" | awk '{print $1}')
test "$LOCAL_SHA" = "$REMOTE_SHA" && echo "sha-match"
```

3. Verify GitHub recorded commit verification status (requires gh auth):

```bash
OWNER_REPO=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
SHA=$(git rev-parse HEAD)
gh api "repos/${OWNER_REPO}/commits/${SHA}" --jq '.commit.verification'
```

4. Optional PR-level verification:

```bash
gh pr create --fill --head "$(git branch --show-current)"
gh pr checks --watch
```
