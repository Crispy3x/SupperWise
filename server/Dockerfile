# Untested: written without Docker available. Build from the server folder: docker build -t ridgeline-routing .
FROM node:22-alpine
WORKDIR /app
COPY package.json server.mjs index.mjs ./
ENV PORT=8080 NODE_ENV=production
USER node
EXPOSE 8080
# Secrets (GOOGLE_MAPS_API_KEY, API_TOKENS) are set on the host, never baked into the image.
CMD ["node", "index.mjs"]
