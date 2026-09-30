#!/bin/bash
# Start oneapi + samcommand + backup loop with correct ordering:
#  1) restore db from GitHub (if any)
#  2) start oneapi (initializes/writes db)
#  3) start samcommand tunnel
#  4) wait for db to be ready, then run backup loop (backs up REAL data)
set -euo pipefail

echo "[start] restoring database..."
/app/backup.sh --restore

echo "[start] starting oneapi..."
/app/oneapi &
ONEAPI_PID=$!

echo "[start] starting samcommand..."
/usr/local/bin/samcommand --no-p2p --verbose 2>&1 | tee /tmp/samcommand.log &
SAMCMD_PID=$!

# Wait for oneapi to create/init the database (up to 45s)
echo "[start] waiting for database init..."
for i in $(seq 1 45); do
  if [[ -s /app/oneapi.db ]] && sqlite3 /app/oneapi.db "SELECT count(*) FROM sqlite_master" >/dev/null 2>&1; then
    echo "[start] database ready after ${i}s ($(stat -c%s /app/oneapi.db 2>/dev/null || echo 0) bytes)"
    break
  fi
  sleep 1
done

# Verify processes alive
if ! kill -0 "$ONEAPI_PID" 2>/dev/null; then
  echo "[start] ERROR: oneapi exited!" >&2
fi
if ! kill -0 "$SAMCMD_PID" 2>/dev/null; then
  echo "[start] WARN: samcommand not running" >&2
fi

# Backup loop (foreground; keeps container alive)
echo "[start] starting backup loop..."
exec /app/backup.sh --loop
