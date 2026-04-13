#!/usr/bin/env bash
# pre-push-gitflow — Enforce GitFlow branch merge rules before push
# Part of @internetmatt/gitflow-guard
#
# Branch hierarchy:
#   main      ← release/*, hotfix/* only
#   dev       ← feature/* only
#   feature/* ← story/* only
#   release/* ← dev (cut), hotfix/* only

set -euo pipefail

REMOTE="${1:-origin}"
URL="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

err()  { printf "${RED}[gitflow-guard]${NC} ❌ %s\n" "$1" >&2; }
warn() { printf "${YELLOW}[gitflow-guard]${NC} ⚠️  %s\n" "$1" >&2; }
ok()   { printf "${GREEN}[gitflow-guard]${NC} ✓ %s\n" "$1" >&2; }

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [[ -z "$CURRENT_BRANCH" ]]; then
  exit 0
fi

REFS=()
while IFS= read -r line; do
  REFS+=("$line")
done

BLOCKED=0

for ref_line in "${REFS[@]}"; do
  read -r LOCAL_REF LOCAL_SHA REMOTE_REF REMOTE_SHA <<< "$ref_line"

  if [[ "$REMOTE_REF" == refs/tags/* ]]; then
    continue
  fi

  TARGET_BRANCH="${REMOTE_REF#refs/heads/}"

  SOURCE_BRANCH="$CURRENT_BRANCH"
  LOCAL_BRANCH="${LOCAL_REF#refs/heads/}"
  if [[ -n "$LOCAL_BRANCH" && "$LOCAL_BRANCH" != "$LOCAL_REF" && "$LOCAL_BRANCH" != "$CURRENT_BRANCH" ]]; then
    SOURCE_BRANCH="$LOCAL_BRANCH"
  fi

  # No direct push to main
  if [[ "$TARGET_BRANCH" == "main" || "$TARGET_BRANCH" == "master" ]]; then
    if [[ "$REMOTE_SHA" != "0000000000000000000000000000000000000000" ]]; then
      COMMITS=$(git log --format='%H %P' "${REMOTE_SHA}..${LOCAL_SHA}" 2>/dev/null || echo "")

      VALID_MERGE=false
      while IFS= read -r cline; do
        [[ -z "$cline" ]] && continue
        PARENT_COUNT=$(echo "$cline" | awk '{print NF - 1}')
        if (( PARENT_COUNT > 1 )); then
          COMMIT_HASH=$(echo "$cline" | awk '{print $1}')
          MERGE_MSG=$(git log -1 --format='%s' "$COMMIT_HASH" 2>/dev/null || echo "")
          if [[ "$MERGE_MSG" =~ (release/|hotfix/) ]]; then
            VALID_MERGE=true
          fi
        fi
      done <<< "$COMMITS"

      if [[ "$VALID_MERGE" == false ]]; then
        if [[ "$SOURCE_BRANCH" =~ ^release/ || "$SOURCE_BRANCH" =~ ^hotfix/ ]]; then
          VALID_MERGE=true
        fi
      fi

      if [[ "$VALID_MERGE" == false ]]; then
        err "Direct push to 'main' is BLOCKED."
        err "Only release/* and hotfix/* branches can merge into main."
        err "Source branch: $SOURCE_BRANCH"
        err ""
        err "Allowed workflows:"
        err "  git checkout release/1.0.0 && git merge dev"
        err "  # Then create a PR: release/1.0.0 → main"
        BLOCKED=1
      fi
    else
      err "Creating 'main' branch via push is not allowed."
      BLOCKED=1
    fi
  fi

  # No direct push to dev (warn only)
  if [[ "$TARGET_BRANCH" == "dev" || "$TARGET_BRANCH" == "develop" ]]; then
    if [[ "$SOURCE_BRANCH" =~ ^feature/ ]]; then
      ok "feature → dev merge allowed: $SOURCE_BRANCH → dev"
    elif [[ "$SOURCE_BRANCH" == "main" || "$SOURCE_BRANCH" == "master" ]]; then
      ok "main → dev back-merge allowed"
    elif [[ "$SOURCE_BRANCH" =~ ^release/ ]]; then
      ok "release → dev back-merge allowed: $SOURCE_BRANCH → dev"
    elif [[ "$SOURCE_BRANCH" =~ ^hotfix/ ]]; then
      ok "hotfix → dev back-merge allowed: $SOURCE_BRANCH → dev"
    elif [[ "$SOURCE_BRANCH" == "dev" || "$SOURCE_BRANCH" == "develop" ]]; then
      if [[ "$REMOTE_SHA" != "0000000000000000000000000000000000000000" ]]; then
        COMMITS=$(git log --format='%s' "${REMOTE_SHA}..${LOCAL_SHA}" 2>/dev/null || echo "")
        HAS_INVALID=false
        while IFS= read -r msg; do
          [[ -z "$msg" ]] && continue
          if ! [[ "$msg" =~ feature/ || "$msg" =~ Merge.*(feature/|release/|hotfix/|main) ]]; then
            HAS_INVALID=true
          fi
        done <<< "$COMMITS"

        if [[ "$HAS_INVALID" == true ]]; then
          warn "Direct commits on 'dev' detected. Prefer feature/* branches."
          warn "This push is allowed but will be blocked in stricter mode."
        fi
      fi
    else
      err "Push to 'dev' from '$SOURCE_BRANCH' is BLOCKED."
      err "Only feature/* branches can merge into dev."
      BLOCKED=1
    fi
  fi

  # feature/* only accepts story/* merges
  if [[ "$TARGET_BRANCH" =~ ^feature/ ]]; then
    if [[ "$SOURCE_BRANCH" =~ ^story/ ]]; then
      ok "story → feature merge allowed: $SOURCE_BRANCH → $TARGET_BRANCH"
    elif [[ "$SOURCE_BRANCH" == "$TARGET_BRANCH" ]]; then
      true
    elif [[ "$SOURCE_BRANCH" == "dev" || "$SOURCE_BRANCH" == "develop" ]]; then
      ok "dev → feature sync allowed"
    else
      warn "Push to feature branch from '$SOURCE_BRANCH'. Expected story/* branches."
    fi
  fi

  # release/* only from dev or hotfix/*
  if [[ "$TARGET_BRANCH" =~ ^release/ ]]; then
    if [[ "$SOURCE_BRANCH" == "dev" || "$SOURCE_BRANCH" == "develop" || "$SOURCE_BRANCH" =~ ^hotfix/ || "$SOURCE_BRANCH" == "$TARGET_BRANCH" ]]; then
      ok "Allowed push to release branch: $SOURCE_BRANCH → $TARGET_BRANCH"
    else
      err "Push to '$TARGET_BRANCH' from '$SOURCE_BRANCH' is BLOCKED."
      err "Release branches are cut from dev only."
      BLOCKED=1
    fi
  fi
done

if (( BLOCKED )); then
  err ""
  err "Push blocked by GitFlow policy."
  exit 1
fi

# Run custom pre-push checks from config
REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
CONFIG_FILE="${REPO_ROOT}/.gitflow-guard.json"

if [[ -f "$CONFIG_FILE" ]] && command -v node >/dev/null 2>&1; then
  DRIFT_ENABLED=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}','utf8'));
    console.log(c?.prePush?.driftCheck?.enabled ? '1' : '0');
  " 2>/dev/null || echo "0")

  if [[ "$DRIFT_ENABLED" == "1" ]]; then
    DRIFT_SCRIPT=$(node -e "
      const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}','utf8'));
      console.log(c?.prePush?.driftCheck?.script || '');
    " 2>/dev/null || echo "")

    if [[ -n "$DRIFT_SCRIPT" ]]; then
      RUN_DRIFT="${GITFLOW_GUARD_DRIFT_CHECK:-1}"
      if [[ "$RUN_DRIFT" == "1" ]]; then
        ok "Running pre-push drift checks..."
        if ! eval "$DRIFT_SCRIPT"; then
          err "Drift checks failed. Push blocked."
          err "Bypass: GITFLOW_GUARD_DRIFT_CHECK=0 git push"
          exit 1
        fi
        ok "Drift checks passed."
      fi
    fi
  fi
fi

exit 0
