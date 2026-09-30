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

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# start.sh handles correct startup order: restore db -> oneapi -> samcommand -> backup loop
CMD ["/bin/bash", "/app/start.sh"]
