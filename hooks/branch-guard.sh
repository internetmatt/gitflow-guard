#!/usr/bin/env bash
# branch-guard — Validates branch name against GitFlow naming conventions
# Part of @internetmatt/gitflow-guard
#
# Sparse-checkout aware: when running inside a worktree with a sparse cone,
# custom checks (typecheck, lint) only run against files within the cone.

set -euo pipefail

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

err() { printf "${RED}[branch-guard]${NC} ❌ %s\n" "$1" >&2; }
ok()  { printf "${GREEN}[branch-guard]${NC} ✓ %s\n" "$1" >&2; }

REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

is_sparse_checkout() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local sparse
  sparse=$(git config --get core.sparseCheckout 2>/dev/null || echo "false")
  [[ "$sparse" == "true" ]]
}

get_sparse_cone_dirs() {
  if is_sparse_checkout; then
    git sparse-checkout list 2>/dev/null || true
  fi
}

staged_files_in_cone() {
  if is_sparse_checkout; then
    local cone_dirs
    cone_dirs=$(get_sparse_cone_dirs)
    if [[ -n "$cone_dirs" ]]; then
      git diff --cached --name-only 2>/dev/null | while IFS= read -r file; do
        for dir in $cone_dirs; do
          if [[ "$file" == "$dir"* || "$file" == "$dir/"* || "$dir" == "." ]]; then
            echo "$file"
            break
          fi
        done
      done
      return
    fi
  fi
  git diff --cached --name-only 2>/dev/null
}

run_custom_pre_commit_checks() {
  local config_file="${REPO_ROOT}/.gitflow-guard.json"
  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  local sparse_info=""
  if is_sparse_checkout; then
    sparse_info="sparse-checkout"
    local cone
    cone=$(get_sparse_cone_dirs | tr '\n' ',' | sed 's/,$//')
    ok "Sparse checkout detected, cone: ${cone:-<root>}"
  fi

  eval "$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${config_file}', 'utf8'));
    const tc = c?.preCommit?.typecheck;
    if (tc?.enabled && tc?.command) {
      console.log('export TYPECHECK_CMD=\"' + tc.command.replace(/\"/g, '\\\\\"') + '\"');
    }
    const lt = c?.preCommit?.lint;
    if (lt?.enabled && lt?.command) {
      console.log('export LINT_CMD=\"' + lt.command.replace(/\"/g, '\\\\\"') + '\"');
      if (lt.stagedOnly) console.log('export LINT_STAGED=1');
      if (lt.extensions) console.log('export LINT_EXTENSIONS=\"' + lt.extensions.join(',') + '\"');
    }
    const sql = c?.preCommit?.sqlBoundaryCheck;
    if (sql?.enabled) console.log('export SQL_BOUNDARY=1');
  " 2>/dev/null || true)"

  if [[ -n "${TYPECHECK_CMD:-}" ]]; then
    ok "Running typecheck..."
    if ! eval "$TYPECHECK_CMD" 2>&1 | tail -10; then
      err "Type checking failed"
      return 1
    fi
  fi

  if [[ -n "${LINT_CMD:-}" ]]; then
    local staged_files
    if [[ "${LINT_STAGED:-0}" == "1" ]]; then
      local exts="${LINT_EXTENSIONS:-.ts,.tsx,.js,.jsx}"
      local ext_pattern
      ext_pattern=$(echo "$exts" | sed 's/,/|/g' | sed 's/\./\\./g')
      staged_files=$(staged_files_in_cone | grep -E "(${ext_pattern})$" || true)
      if [[ -n "$staged_files" ]]; then
        ok "Linting staged files (${sparse_info:-full checkout})..."
        echo "$staged_files" | xargs $LINT_CMD || {
          err "Linting failed"
          return 1
        }
      fi
    else
      ok "Running lint..."
      eval "$LINT_CMD" || {
        err "Linting failed"
        return 1
      }
    fi
  fi

  if [[ "${SQL_BOUNDARY:-0}" == "1" ]]; then
    if [[ -x "$REPO_ROOT/tools/scripts/check-sql-migration-boundaries.mjs" ]]; then
      local sql_files
      sql_files=$(staged_files_in_cone | grep -E '\.sql$' || true)
      if [[ -n "$sql_files" ]]; then
        ok "Running SQL boundary check"
        SQL_BOUNDARY_STRICT_DUPLICATES="${SQL_BOUNDARY_STRICT_DUPLICATES:-true}" \
          node "$REPO_ROOT/tools/scripts/check-sql-migration-boundaries.mjs" || true
      fi
    fi
  fi
}

if [[ -z "$BRANCH" ]]; then
  exit 0
fi

VALID=false

case "$BRANCH" in
  main|master|dev|develop)
    VALID=true
    ;;
  feature/*)
    if [[ "$BRANCH" =~ ^feature/[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
      VALID=true
    else
      err "Feature branch name must match: feature/<area>-<slug>"
      err "  Example: feature/portal-federation-loader"
      err "  Got: $BRANCH"
    fi
    ;;
  story/*)
    if [[ "$BRANCH" =~ ^story/[a-z0-9-]+/[a-z0-9-]+$ ]]; then
      VALID=true
    else
      err "Story branch name must match: story/<feature>/<story-id>"
      err "  Example: story/portal-federation-loader/123"
      err "  Got: $BRANCH"
    fi
    ;;
  release/*)
    if [[ "$BRANCH" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]; then
      VALID=true
    else
      err "Release branch name must match: release/<semver>"
      err "  Example: release/1.0.0 or release/1.0.0-rc.1"
      err "  Got: $BRANCH"
    fi
    ;;
  hotfix/*)
    if [[ "$BRANCH" =~ ^hotfix/[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
      VALID=true
    else
      err "Hotfix branch name must match: hotfix/<slug>"
      err "  Example: hotfix/auth-token-expiry"
      err "  Got: $BRANCH"
    fi
    ;;
  claude/*|copilot/*|codex/*)
    VALID=true
    ;;
  *)
    err "Branch name '$BRANCH' doesn't match GitFlow convention."
    err ""
    err "Allowed patterns:"
    err "  main, dev"
    err "  feature/<area>-<slug>"
    err "  story/<feature>/<story-id>"
    err "  release/<semver>"
    err "  hotfix/<slug>"
    err "  claude/*, copilot/*, codex/*"
    ;;
esac

if [[ "$VALID" == false ]]; then
  if [[ "${GITFLOW_STRICT:-0}" == "1" ]]; then
    exit 1
  else
    err "(Warning only — set GITFLOW_STRICT=1 to enforce)"
  fi
fi

run_custom_pre_commit_checks

exit 0
