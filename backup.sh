#!/bin/bash
# OneAPI database backup/restore via GitHub API
# Uses env: GITHUB_TOKEN (repo write scope), GITHUB_REPO (e.g. "user/oneapi-backup"),
#        DB_FILE (default ./oneapi.db), BACKUP_INTERVAL (default 5min)
set -euo pipefail

DB_FILE="${DB_FILE:-/app/oneapi.db}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-300}"  # 5min in seconds
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
  if [[ -n "$resp" ]] && [[ "$resp" == *'"download_url"'* ]]; then
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

# Create a consistent snapshot including WAL data.
# Returns snapshot path in $SNAP or exits 1 if the db is empty/invalid.
snapshot() {
  local tmp=/tmp/oneapi-backup.db
  # 1) checkpoint WAL into main db (helps fallback paths capture data)
  sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(FULL);" >/dev/null 2>&1 || true
  # 2) online backup to tmp (handles WAL correctly)
  rm -f "$tmp"
  if ! sqlite3 "$DB_FILE" ".backup $tmp" >/dev/null 2>&1; then
    # fallback: VACUUM INTO produces a consistent snapshot too
    if ! sqlite3 "$DB_FILE" "VACUUM INTO '$tmp';" >/dev/null 2>&1; then
      # last resort: raw copy (may miss WAL data if not check-pointed)
      cp "$DB_FILE" "$tmp" || return 1
    fi
  fi
  # 3) validate: must have at least one table and reasonable size
  local tbls
  tbls="$(sqlite3 "$tmp" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo 0)"
  if [[ "${tbls:-0}" == "0" ]]; then
    echo "[backup] WARN: snapshot has 0 tables - skipping push (db not initialized?)"
    return 1
  fi
  SNAP="$tmp"
  return 0
}

backup() {
  echo "[backup] backing up $DB_FILE ..."
  local SNAP=""
  if ! snapshot; then
    echo "[backup] skip: no valid snapshot (db empty / oneapi not ready)"
    return 0
  fi
  local content_b64
  content_b64="$(base64 -w0 "$SNAP" 2>/dev/null || base64 "$SNAP" | tr -d '\n')"

  local sha="" resp
  resp="$(curl -fsSL --max-time 30 -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/contents/$REMOTE_PATH?ref=$BRANCH" || true)"
  if [[ -n "$resp" ]] && [[ "$resp" == *'"sha"'* ]]; then
    sha="$(echo "$resp" | sed -n 's/.*"sha": *"\([^"]*\)".*/\1/p')"
  fi

  local payload
  payload="$(SHA="$sha" SNAP="$SNAP" python3 - <<'PYEOF'
import json, base64, os
with open(os.environ['SNAP'], 'rb') as f:
    b64 = base64.b64encode(f.read()).decode()
sha = os.environ.get('SHA', '') or None
print(json.dumps({"message": "oneapi.db backup", "content": b64, "branch": "main", "sha": sha}))
PYEOF
)"

  if curl -fsSL --max-time 60 -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$payload" \
    "https://api.github.com/repos/$GITHUB_REPO/contents/$REMOTE_PATH" >/dev/null 2>&1; then
    echo "[backup] pushed to $GITHUB_REPO ($(stat -c%s "$SNAP") bytes)"
  else
    echo "[backup] push failed"
  fi
}

if [[ "${1:-}" == "--restore" ]]; then
  restore
  exit 0
fi

while true; do
  backup
  sleep "$BACKUP_INTERVAL"
done

