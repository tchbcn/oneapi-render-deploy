FROM ubuntu:24.04

WORKDIR /app

# Install curl + sqlite3 + python3
RUN apt-get update && apt-get install -y --no-install-recommends curl sqlite3 ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

COPY oneapi /app/oneapi
RUN chmod +x /app/oneapi

# Install samcommand (includes aitun tunnel client) from ModelScope mirror
RUN curl -fsSL 'https://modelscope.cn/api/v1/models/luoyunlan168/samcommand/repo?Revision=master&FilePath=install.sh' | bash \
    && ls -la /usr/local/bin/samcommand ~/.samcommand/ 2>/dev/null || true

# Persistence via GitHub backup
ENV PORT=3000
ENV DATABASE_URL=sqlite+aiosqlite:///./oneapi.db
EXPOSE 3000

COPY backup.sh /app/backup.sh
RUN chmod +x /app/backup.sh

# Start oneapi, run samcommand tunnel in background, keep backup loop
CMD ["/bin/bash", "-c", "/app/backup.sh --restore && /app/oneapi & /usr/local/bin/samcommand --no-p2p --verbose 2>&1 | tee /tmp/samcommand.log & exec /app/backup.sh --loop"]
