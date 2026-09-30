FROM ubuntu:24.04


WORKDIR /app


# Install curl + sqlite3 + python3
RUN apt-get update && apt-get install -y --no-install-recommends curl sqlite3 ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*


COPY oneapi /app/oneapi
RUN chmod +x /app/oneapi


# Persistence via GitHub backup
ENV PORT=3000
ENV DATABASE_URL=sqlite+aiosqlite:///./oneapi.db
EXPOSE 3000


COPY backup.sh /app/backup.sh
RUN chmod +x /app/backup.sh


CMD ["/bin/bash", "-c", "/app/backup.sh --restore && /app/oneapi & exec /app/backup.sh --loop"]
