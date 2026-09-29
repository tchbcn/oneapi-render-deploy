FROM debian:bullseye-slim

WORKDIR /app
COPY oneapi /app/oneapi
RUN chmod +x /app/oneapi

# OneAPI Gateway listens on PORT env (default 3000)
ENV PORT=3000
EXPOSE 3000

CMD ["/app/oneapi"]
