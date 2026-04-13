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
