#!/bin/bash
# OneAPI database backup/restore via GitHub API
# Uses env: GITHUB_TOKEN (repo write scope), GITHUB_REPO (e.g. "user/oneapi-backup"),
#        DB_FILE (default ./oneapi.db), BACKUP_INTERVAL (default 6h)
set -euo pipefail

DB_FILE="${DB_FILE:-/app/oneapi.db}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"  # 6h in seconds
BRANCH="main"
REMOTE_PATH="oneapi.db"

if [[ -z "$GITHUB_TOKEN" || -z "$GITHUB_REPO" ]]; then
  echo "[backup] GITHUB_TOKEN/GITHUB_REPO not set - persistence disabled (will lose data on restart)"
  if [[ "${1:-}" == "--restore" ]]; then exit 0; fi
  while true; do sleep 3600; done
fi

restore() {
  echo "[backup] attempting restore from $GITHUB_REPO/$REMOTE_PATH ..."
  local resp dl
  resp="$(curl -fsSL --max-time 30 -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/contents/$REMOTE_PATH?ref=$BRANCH" || true)"
  if [[ -n "$resp" ]] && echo "$resp" | grep -q '"download_url"'; then
    dl="$(echo "$resp" | sed -n 's/.*"download_url": *"\([^"]*\)".*/\1/p')"
    curl -fsSL --max-time 60 -o "$DB_FILE.restored" "$dl" || true
    if [[ -s "$DB_FILE.restored" ]]; then
      mv "$DB_FILE.restored" "$DB_FILE"
      echo "[backup] restored $(stat -c%s "$DB_FILE") bytes from GitHub"
    else
      echo "[backup] no valid db in repo, starting fresh"
      rm -f "$DB_FILE.restored"
    fi
  else
    echo "[backup] repo has no db yet, starting fresh"
  fi
}

backup() {
  echo "[backup] backing up $DB_FILE ..."
  local tmp=/tmp/oneapi-backup.db
  sqlite3 "$DB_FILE" ".backup '$tmp'" 2>/dev/null || cp "$DB_FILE" "$tmp"
  local content_b64
  content_b64="$(base64 -w0 "$tmp" 2>/dev/null || base64 "$tmp" | tr -d '\n')"

  local sha="" resp
  resp="$(curl -fsSL --max-time 30 -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/contents/$REMOTE_PATH?ref=$BRANCH" || true)"
  if [[ -n "$resp" ]] && echo "$resp" | grep -q '"sha"'; then
    sha="$(echo "$resp" | sed -n 's/.*"sha": *"\([^"]*\)".*/\1/p')"
  fi

  # Build JSON payload with python3 (always emits valid JSON, null sha on create)
  local payload
  payload="$(SHA="$sha" python3 - <<'PYEOF'
import json, base64, os
with open('/tmp/oneapi-backup.db', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()
sha = os.environ.get('SHA', '') or None
print(json.dumps({"message": "oneapi.db backup", "content": b64, "branch": "main", "sha": sha}))
PYEOF
)"

  curl -fsSL --max-time 60 -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$payload" \
    "https://api.github.com/repos/$GITHUB_REPO/contents/$REMOTE_PATH" >/dev/null 2>&1 \
    && echo "[backup] pushed to $GITHUB_REPO" || echo "[backup] push failed"
}

if [[ "${1:-}" == "--restore" ]]; then
  restore
  exit 0
fi

while true; do
  backup
  sleep "$BACKUP_INTERVAL"
done
