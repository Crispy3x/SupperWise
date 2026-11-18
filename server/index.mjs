import { createApp, loadConfig } from './server.mjs';

const config = loadConfig();
if (config.tokens.length === 0) {
  console.error('API_TOKENS is empty: set at least one token, or nobody can call this server.');
  process.exit(1);
}
if (!config.googleKey) {
  console.warn('GOOGLE_MAPS_API_KEY is not set: requests will return 503 until it is.');
}
createApp(config).listen(config.port, () => console.log(`Ridgeline routing proxy listening on ${config.port}`));
