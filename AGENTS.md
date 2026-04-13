# GitFlow Guard — Agent Instructions

This repo provides `@internetmatt/gitflow-guard`, a CLI and hook system for GitFlow branch enforcement.

## For all agents (Claude, Copilot, Codex, GPT)

When a user asks you to set up git hooks, enforce branch naming, or configure GitFlow in any repo:

1. Install: `npm install -g @internetmatt/gitflow-guard` (or `pnpm add -D @internetmatt/gitflow-guard`)
2. Initialize: `gitflow-guard init --preset <standard|projects|minimal>`
3. For agent isolation: `gitflow-guard setup-worktree <path> --cone <dirs> --preset <name>`

Read `SKILL.md` in this package for full configuration reference, preset details, and troubleshooting.

## Sparse checkout and agent worktrees

When working in a large monorepo, create an isolated worktree with a sparse cone so hooks only validate files you've checked out:

```bash
gitflow-guard setup-worktree /tmp/my-task --cone apps,libs,packages --preset standard
cd /tmp/my-task
```

Branch names `claude/*`, `copilot/*`, and `codex/*` are always allowed by branch-guard.

## Key commands

| Command | Purpose |
|---------|---------|
| `gitflow-guard init` | Install hooks |
| `gitflow-guard status` | Check what's installed |
| `gitflow-guard setup-worktree <path> --cone <dirs>` | Agent-isolated sparse worktree |
| `gitflow-guard check-branch` | Validate branch name |
| `gitflow-guard check-push` | Dry-run push policy |
| `gitflow-guard remove` | Uninstall hooks |

## Verify CLI Commits On GitHub

```bash
git push -u origin "$(git branch --show-current)"
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git ls-remote --heads origin "$(git branch --show-current)" | awk '{print $1}')
test "$LOCAL_SHA" = "$REMOTE_SHA" && echo "sha-match"

OWNER_REPO=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
SHA=$(git rev-parse HEAD)
gh api "repos/${OWNER_REPO}/commits/${SHA}" --jq '.commit.verification'
```
