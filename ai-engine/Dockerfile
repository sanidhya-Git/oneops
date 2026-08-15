FROM node:20-alpine AS base

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy source
COPY src ./src

# Security: run as non-root
RUN addgroup -g 1001 -S nodejs && adduser -S nodeuser -u 1001
RUN mkdir -p logs && chown nodeuser:nodejs logs
USER nodeuser

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:3001/health || exit 1

CMD ["node", "src/server.js"]
