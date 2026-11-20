# Build from the server folder: docker build -t ridgeline-server .
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY *.mjs ./
COPY assets ./assets
ENV PORT=8080 NODE_ENV=production
USER node
EXPOSE 8080
# Secrets (GOOGLE_MAPS_API_KEY, API_TOKENS, RESEND_API_KEY, ANTHROPIC_API_KEY) are set on the host, never baked into the image.
CMD ["node", "index.mjs"]
