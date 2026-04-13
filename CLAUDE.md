# GitFlow Guard

This is `@internetmatt/gitflow-guard` — a CLI for GitFlow branch enforcement, hook orchestration, and commit journaling.

When asked to set up git hooks or branch policies, use the `gitflow-guard` CLI. Read `SKILL.md` for full details.

Key commands: `gitflow-guard init`, `gitflow-guard setup-worktree`, `gitflow-guard status`.

Agent branches (`claude/*`, `copilot/*`, `codex/*`) are always allowed by branch-guard.

For sparse checkout isolation: `gitflow-guard setup-worktree /tmp/task --cone apps,libs --preset standard`
