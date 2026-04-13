---
name: gitflow-guard
description: "Set up and manage GitFlow branch enforcement, hook orchestration, commit journaling, and declarative automation profile integration for any repo."
---

# GitFlow Guard — Agent Skill

Set up and manage GitFlow branch enforcement, commit journaling, and hook orchestration using `@internetmatt/gitflow-guard`.

Compatible with: **Cursor, Claude Code, GitHub Copilot, OpenAI Codex, any agent that reads AGENTS.md/CLAUDE.md/copilot-instructions.md**.

## When to use

- Setting up git hooks, branch naming rules, or GitFlow enforcement in a repo
- Creating an isolated agent worktree with sparse checkout and scoped hooks
- Configuring pre-commit checks (typecheck, lint) scoped to a sparse cone
- Adding commit journaling or automation integration
- Troubleshooting blocked pushes or branch name rejections

## Install

```bash
npm install -g @internetmatt/gitflow-guard
# or per-project
pnpm add -D @internetmatt/gitflow-guard
```

## Basic setup

```bash
cd <repo-root>
gitflow-guard init                      # Default preset (standard)
gitflow-guard init --preset projects    # NX monorepo with typecheck/lint
gitflow-guard init --preset minimal     # Branch guard + push policy only
```

## Agent worktree with sparse checkout

When an agent needs an isolated workspace scoped to specific directories:

```bash
# Create a worktree with sparse cone — hooks only check files in the cone
gitflow-guard setup-worktree /tmp/agent-work \
  --cone apps,libs,packages \
  --preset standard

# Or enable sparse checkout on an existing repo
gitflow-guard init --sparse apps,libs,scripts --preset projects
```

The hooks are **cone-aware**: when running inside a sparse checkout, lint and typecheck only process staged files that fall within the sparse cone. This prevents agents from failing on files they haven't checked out.

### Agent workflow pattern

```bash
# 1. Agent creates its own isolated worktree
gitflow-guard setup-worktree /tmp/copilot-task-123 \
  --cone apps/api,libs/declarative-ui,packages/shared \
  --preset standard

# 2. Agent works in the worktree
cd /tmp/copilot-task-123
git checkout -b feature/agent-fix-auth

# 3. Hooks enforce branch naming and scoped checks automatically
git add -A
git commit -m "fix(auth): resolve token expiry"   # branch-guard runs
git push origin feature/agent-fix-auth              # push policy enforced

# 4. Clean up
git worktree remove /tmp/copilot-task-123
```

## Presets

### `standard`
Full suite: branch guard, push policy, commit journaling to `Vault/Gitflow/`, automation events, SQL boundary checks, conventional commit prefixing.

### `project` (compat alias)
Alias of `standard` for migrating existing repositories.

### `projects`
NX monorepo: everything in standard plus NX typecheck and ESLint as pre-commit gates and container dual-mode support.

### `minimal`
Just branch-guard (pre-commit) and push policy (pre-push). No post-commit hooks, no journaling.

## Configuration

Edit `.gitflow-guard.json` in the repo root. Key options:

```json
{
  "preset": "standard",
  "strict": false,
  "journal": { "enabled": true, "dir": "Vault/Gitflow" },
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
  "preCommit": {
    "typecheck": { "enabled": true, "command": "pnpm exec nx run-many --targets=typecheck" },
    "lint": { "enabled": true, "command": "pnpm exec eslint --max-warnings 0", "stagedOnly": true }
  },
  "prePush": {
    "driftCheck": { "enabled": true, "script": "pnpm run drift:check" }
  }
}
```

## Branch naming rules

| Pattern | Example |
|---------|---------|
| `main` / `dev` | Protected branches |
| `feature/<slug>` | `feature/portal-federation` |
| `story/<feature>/<id>` | `story/portal/123` |
| `release/<semver>` | `release/1.0.0-rc.1` |
| `hotfix/<slug>` | `hotfix/auth-token-expiry` |
| `claude/*` / `copilot/*` / `codex/*` | Agent branches (always allowed) |

## Push merge hierarchy

```
main      ← release/*, hotfix/*
dev       ← feature/*
feature/* ← story/*
release/* ← dev, hotfix/*
```

## Environment overrides

- `GITFLOW_STRICT=1` — block commits on invalid branch names (default: warn)
- `GITFLOW_GUARD_DRIFT_CHECK=0` — skip pre-push drift checks
- `GITFLOW_GUARD_CONFIG=<path>` — custom config file path

## Hooks reference

| Hook | What it does |
|------|-------------|
| `pre-commit` (branch-guard) | Validates branch name, runs typecheck/lint scoped to sparse cone |
| `pre-push` (gitflow-guard) | Enforces merge rules, runs drift checks if configured |
| `post-commit` | Journals commit to JSONL, notifies automation target |
| `post-merge` | Notifies automation target of merge events |
| `post-checkout` | Auto-pulls protected branches on checkout |
| `prepare-commit-msg` | Auto-prefixes with conventional commit format |

## Troubleshooting

- **Hook not running**: `gitflow-guard status`
- **Push blocked**: `gitflow-guard check-push`; bypass drift with `GITFLOW_GUARD_DRIFT_CHECK=0 git push`
- **Branch rejected**: `gitflow-guard check-branch`; bypass with `GITFLOW_STRICT=0`
- **Lint fails on unchecked-out files**: Ensure sparse checkout is set — hooks auto-detect the cone

## Verify CLI Commit In GitHub

Use these commands to confirm the commit you created locally is pushed and verified by GitHub.

```bash
# Push current branch
git push -u origin "$(git branch --show-current)"

# Confirm local HEAD equals remote branch HEAD
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote --heads origin "$(git branch --show-current)" | awk '{print $1}')"
test "$LOCAL_SHA" = "$REMOTE_SHA" && echo "sha-match"

# Check GitHub commit verification object
OWNER_REPO="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
SHA="$(git rev-parse HEAD)"
gh api "repos/$OWNER_REPO/commits/$SHA" --jq '.commit.verification'
```

Optional PR checks:

```bash
gh pr create --fill --head "$(git branch --show-current)"
gh pr checks --watch
```
