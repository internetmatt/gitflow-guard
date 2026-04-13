#!/usr/bin/env bash
# prepare-commit-msg-gitflow — Auto-prefix commits with conventional commit format
# Part of @internetmatt/gitflow-guard

set -euo pipefail

COMMIT_MSG_FILE="${1:-}"
COMMIT_SOURCE="${2:-}"
REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"

if [[ -z "$COMMIT_MSG_FILE" || "$COMMIT_SOURCE" == "commit" ]]; then
  exit 0
fi

current_msg=$(head -1 "$COMMIT_MSG_FILE" 2>/dev/null || echo "")
if [[ "$current_msg" =~ ^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)\(.*\):\  ]]; then
  exit 0
fi

scope=""
type=""

# Detect type from staged files
if git diff --cached --name-only | grep -qE '\.(test|spec)\.(ts|tsx|js|jsx)$' 2>/dev/null; then
  type="test"
elif git diff --cached --name-only | grep -qE '^\.(internetmatt|gitflow-guard)/' 2>/dev/null; then
  type="chore"
elif git diff --cached --name-only | grep -qE '^(docs/|README)' 2>/dev/null; then
  type="docs"
elif git diff --cached --name-only --diff-filter=A | grep -q . 2>/dev/null; then
  type="feat"
else
  type="fix"
fi

# Detect scope from changed directories
if [[ -z "$scope" ]]; then
  changed_dirs=$(git diff --cached --name-only | cut -d/ -f1,2 | sort -u | head -3)
  case "$changed_dirs" in
    *infra*|*infrastructure*) scope="infrastructure" ;;
    *api*) scope="api" ;;
    *) scope=$(echo "$changed_dirs" | head -1 | tr '/' '-' | tr -d ' ') ;;
  esac
fi

if [[ -z "$scope" ]]; then
  scope="repo"
fi

description="${current_msg:-update context and dependencies}"
if [[ "$description" =~ ^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)\(.*\):\  ]]; then
  exit 0
fi

{
  echo "${type}(${scope}): ${description}"
  echo ""
  tail -n +2 "$COMMIT_MSG_FILE" 2>/dev/null || true
} > "${COMMIT_MSG_FILE}.tmp"
mv "${COMMIT_MSG_FILE}.tmp" "$COMMIT_MSG_FILE"

exit 0
