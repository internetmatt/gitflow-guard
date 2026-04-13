This repo provides `@internetmatt/gitflow-guard`, a CLI for GitFlow branch enforcement and git hook orchestration.

When setting up git hooks or branch policies in any repo, use:

```bash
gitflow-guard init --preset <standard|projects|minimal>
```

For agent-isolated sparse-checkout worktrees:

```bash
gitflow-guard setup-worktree /tmp/task-dir --cone apps,libs,packages --preset standard
```

Agent branches (`copilot/*`, `claude/*`, `codex/*`) are always allowed by branch-guard.

Hooks are sparse-checkout aware — lint and typecheck only run against files within the checkout cone.

See `SKILL.md` for full preset details, configuration options, and troubleshooting.
