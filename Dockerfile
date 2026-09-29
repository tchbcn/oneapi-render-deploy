FROM ubuntu:24.04

WORKDIR /app

# Install curl (for backup/restore via GitHub API) + sqlite3 (for safe backup)
RUN apt-get update && apt-get install -y --no-install-recommends curl sqlite3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY oneapi /app/oneapi
RUN chmod +x /app/oneapi

# ---- Persistence via GitHub backup ----
# GITHUB_TOKEN + GITHUB_REPO (e.g. tchbcn/oneapi-backup) must be provided in Render env.
# On start: pull oneapi.db from repo (if exists) before launching.
# While running: /app/backup.sh runs every 6h and pushes oneapi.db back.

ENV PORT=3000
ENV DATABASE_URL=sqlite+aiosqlite:///./oneapi.db
EXPOSE 3000

COPY backup.sh /app/backup.sh
RUN chmod +x /app/backup.sh

# Start oneapi in background, run backup loop, keep container alive
CMD ["/bin/bash", "-c", "/app/backup.sh --restore && /app/oneapi & exec /app/backup.sh --loop"]
