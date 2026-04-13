#!/usr/bin/env bash
# post-checkout-autopull — Auto-pull on protected branch checkout
# Part of @internetmatt/gitflow-guard

set -euo pipefail

PREV_HEAD="${1:-}"
NEW_HEAD="${2:-}"
IS_BRANCH_CHECKOUT="${3:-0}"

if [[ "$IS_BRANCH_CHECKOUT" != "1" ]]; then
  exit 0
fi

REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${GREEN}[auto-pull]${NC} %s\n" "$1" >&2; }
warn()  { printf "${YELLOW}[auto-pull]${NC} %s\n" "$1" >&2; }
status(){ printf "${CYAN}[auto-pull]${NC} %s\n" "$1" >&2; }

AUTO_PULL=false

case "$BRANCH" in
  main|master|dev|develop) AUTO_PULL=true ;;
  release/*) AUTO_PULL=true ;;
esac

if [[ "$AUTO_PULL" == true ]]; then
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || echo "")

  if [[ -n "$UPSTREAM" ]]; then
    status "Auto-pulling '$BRANCH' to stay in sync..."

    git fetch origin "$BRANCH" --quiet 2>/dev/null || {
      warn "Fetch failed (offline?). Continuing with local state."
      exit 0
    }

    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "")

    if [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]; then
      if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        if git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null; then
          git merge --ff-only "origin/$BRANCH" --quiet 2>/dev/null && {
            info "✓ Fast-forwarded '$BRANCH'"
          } || {
            warn "Cannot fast-forward. Run 'git pull --rebase' manually."
          }
        elif git merge-base --is-ancestor "origin/$BRANCH" HEAD 2>/dev/null; then
          AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
          info "✓ '$BRANCH' is $AHEAD commits ahead. Nothing to pull."
        else
          warn "'$BRANCH' has diverged from origin. Manual merge/rebase required."
        fi
      else
        warn "Working tree is dirty. Skipping auto-pull on '$BRANCH'."
      fi
    else
      info "✓ '$BRANCH' is up to date with origin."
    fi
  fi
fi

exit 0
