#!/usr/bin/env bash
# post-commit-gitflow — Commit logger and automation notifier
# Part of @internetmatt/gitflow-guard
#
# Appends one JSON-lines entry per commit to a staging log.
# Never blocks a commit — all errors are silently swallowed.

set -euo pipefail

REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
CONFIG_FILE="${REPO_ROOT}/.gitflow-guard.json"

JOURNAL_DIR="${REPO_ROOT}/Vault/Gitflow"
LOG_FILE="${JOURNAL_DIR}/.commit-log.jsonl"
PENDING_FILE="${JOURNAL_DIR}/.pending-queue.jsonl"
LOCK_FILE="${JOURNAL_DIR}/.commit-log.lock"
AUTOMATION_URL=""
AUTOMATION_EVENT_PATH="/events"
AUTOMATION_TRIGGER_PATH="/triage"
AUTOMATION_SKILL_COMMAND=""

if [[ -f "$CONFIG_FILE" ]] && command -v node >/dev/null 2>&1; then
  eval "$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}','utf8'));
    const j = c?.journal || {};
    if (j.enabled === false) { console.log('exit 0'); process.exit(); }
    if (j.dir) console.log('JOURNAL_DIR=\"${REPO_ROOT}/' + j.dir + '\"');
    if (j.logFile) console.log('LOG_FILE=\"\${JOURNAL_DIR}/' + j.logFile + '\"');
    const a = c?.automation || {};
    const profileName = a?.profile;
    const profile = profileName && a?.profiles && typeof a.profiles === 'object'
      ? a.profiles[profileName]
      : null;
    const legacy = c?.orchestrator || {};
    const target = profile || a;
    const enabled = target?.enabled || legacy?.enabled;
    const url = target?.url || legacy?.url;
    if (enabled && url) {
      console.log('AUTOMATION_URL=\"' + String(url).replace(/\"/g, '\\\\"') + '\"');
      console.log('AUTOMATION_EVENT_PATH=\"' + String(target?.eventPath || '/events').replace(/\"/g, '\\\\"') + '\"');
      console.log('AUTOMATION_TRIGGER_PATH=\"' + String(target?.triggerPath || '/triage').replace(/\"/g, '\\\\"') + '\"');
    }
    if (target?.skillCommand) {
      console.log('AUTOMATION_SKILL_COMMAND=\"' + String(target.skillCommand).replace(/\"/g, '\\\\"') + '\"');
    }
  " 2>/dev/null || true)"
fi

log_pending() {
  local entry="$1" reason="$2"
  printf '{"entry":%s,"error":"%s","queued_at":"%s"}\n' \
    "$entry" "$reason" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PENDING_FILE" 2>/dev/null || true
}

cleanup_lock() { rm -f "$LOCK_FILE" 2>/dev/null || true; }

(
  trap cleanup_lock EXIT

  if [ ! -d "$JOURNAL_DIR" ]; then
    mkdir -p "$JOURNAL_DIR" 2>/dev/null || exit 0
  fi

  if [ -f "$LOCK_FILE" ]; then
    if [ "$(find "$LOCK_FILE" -mmin +0.17 2>/dev/null)" ]; then
      rm -f "$LOCK_FILE"
    else
      exit 0
    fi
  fi
  echo $$ > "$LOCK_FILE"

  COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null)
  COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null)
  COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null | head -c 200)
  COMMIT_AUTHOR=$(git log -1 --format='%an' 2>/dev/null)
  COMMIT_EMAIL=$(git log -1 --format='%ae' 2>/dev/null)
  COMMIT_DATE=$(git log -1 --format='%aI' 2>/dev/null)
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  REPO_NAME=$(basename "$REPO_ROOT")
  FILES_CHANGED=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | wc -l | tr -d ' ')

  STORY_REF=""
  if echo "$BRANCH" | grep -qoE 'story-[0-9]+' 2>/dev/null; then
    STORY_REF=$(echo "$BRANCH" | grep -oE 'story-[0-9]+' | head -1)
  fi
  if [ -z "$STORY_REF" ]; then
    STORY_REF=$(echo "$COMMIT_MSG" | grep -oE '(story-[0-9]+|closes #[0-9]+|phase-[a-z])' | head -1 || true)
  fi

  SCOPE=""
  if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|chore|docs|test|ci)\(' 2>/dev/null; then
    SCOPE=$(echo "$COMMIT_MSG" | grep -oE '^\w+\(([^)]+)\)' | sed 's/.*(\(.*\))/\1/' || true)
  fi

  ENTRY=$(printf '{"hash":"%s","short":"%s","message":"%s","author":"%s","email":"%s","date":"%s","branch":"%s","repo":"%s","files_changed":%d,"story_ref":"%s","scope":"%s","logged_at":"%s"}' \
    "$COMMIT_HASH" "$COMMIT_SHORT" \
    "$(echo "$COMMIT_MSG" | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")" \
    "$COMMIT_AUTHOR" "$COMMIT_EMAIL" "$COMMIT_DATE" \
    "$BRANCH" "$REPO_NAME" "$FILES_CHANGED" \
    "$STORY_REF" "$SCOPE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")

  if ! echo "$ENTRY" >> "$LOG_FILE" 2>/dev/null; then
    log_pending "$ENTRY" "write_failed"
  fi

  if [[ -n "$AUTOMATION_URL" ]]; then
    curl -s -X POST "${AUTOMATION_URL}${AUTOMATION_EVENT_PATH}" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"git.post-commit\",\"source\":\"gitflow-guard\",\"payload\":${ENTRY}}" \
      --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true

    curl -s -X POST "${AUTOMATION_URL}${AUTOMATION_TRIGGER_PATH}" \
      -H "Content-Type: application/json" \
      -d "{\"agentIds\":\"*\",\"events\":[{\"type\":\"git.post-commit\",\"source\":\"gitflow-guard\",\"payload\":${ENTRY}}],\"blueGreenSafe\":true}" \
      --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true
  fi

  if [[ -n "$AUTOMATION_SKILL_COMMAND" ]]; then
    eval "$AUTOMATION_SKILL_COMMAND '$ENTRY'" >/dev/null 2>&1 || true
  fi
) 2>/dev/null || true

exit 0
