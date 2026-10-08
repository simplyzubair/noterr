# Noterr sync server for Contabo, deployed by Coolify. Node's built-in SQLite,
# no npm dependencies. Mount a volume at /data to keep the database.
FROM node:24-alpine
WORKDIR /app
COPY server.mjs ./
ENV PORT=8080 DATA_DIR=/data
# Owned by the unprivileged user, so a fresh named volume is writable.
RUN mkdir -p /data && chown node:node /data
VOLUME /data
EXPOSE 8080
USER node
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "server.mjs"]
