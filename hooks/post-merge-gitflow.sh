#!/usr/bin/env bash
# post-merge-gitflow — Merge event logger and automation notifier
# Part of @internetmatt/gitflow-guard

set -euo pipefail

REPO_ROOT="${GITFLOW_GUARD_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
CONFIG_FILE="${REPO_ROOT}/.gitflow-guard.json"
AUTOMATION_URL=""
AUTOMATION_EVENT_PATH="/events"
AUTOMATION_TRIGGER_PATH="/triage"
AUTOMATION_SKILL_COMMAND=""

if [[ -f "$CONFIG_FILE" ]] && command -v node >/dev/null 2>&1; then
  eval "$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}','utf8'));
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

(
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null)
  COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null | head -c 200 | sed 's/"/\\"/g')
  FILES_CHANGED=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | wc -l | tr -d ' ')
  MERGE_ENTRY=$(printf '{"hash":"%s","branch":"%s","message":"%s","files_changed":%d,"event":"post-merge","timestamp":"%s"}' \
    "$COMMIT_HASH" "$BRANCH" "$COMMIT_MSG" "$FILES_CHANGED" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")

  if [[ -n "$AUTOMATION_URL" ]]; then
    curl -s -X POST "${AUTOMATION_URL}${AUTOMATION_EVENT_PATH}" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"git.post-merge\",\"source\":\"gitflow-guard\",\"payload\":${MERGE_ENTRY}}" \
      --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true

    curl -s -X POST "${AUTOMATION_URL}${AUTOMATION_TRIGGER_PATH}" \
      -H "Content-Type: application/json" \
      -d "{\"agentIds\":\"*\",\"events\":[{\"type\":\"git.post-merge\",\"source\":\"gitflow-guard\",\"payload\":${MERGE_ENTRY}}],\"blueGreenSafe\":true}" \
      --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true
  fi

  if [[ -n "$AUTOMATION_SKILL_COMMAND" ]]; then
    eval "$AUTOMATION_SKILL_COMMAND '$MERGE_ENTRY'" >/dev/null 2>&1 || true
  fi
) 2>/dev/null || true

exit 0
