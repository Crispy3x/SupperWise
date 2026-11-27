import { createFullServer, loadConfig, loadPortalConfig, loadAiConfig } from './app.mjs';

const config = loadConfig();
const portalConfig = loadPortalConfig();
const aiConfig = loadAiConfig();
if (config.tokens.length === 0) {
  console.error('API_TOKENS is empty: set at least one token, or nobody can call this server.');
  process.exit(1);
}
if (!config.googleKey) console.warn('GOOGLE_MAPS_API_KEY is not set: drive-time requests return 503 (the app can use Apple Maps instead).');
if (!portalConfig.resendKey || !portalConfig.fromEmail) console.warn('RESEND_API_KEY or FROM_EMAIL is not set: sending email returns 503.');
if (!portalConfig.dataFile) console.warn('PORTAL_DATA_FILE is not set: client requests are kept in memory and lost on restart.');
if (portalConfig.embedOriginsInvalid.length) console.warn(`EMBED_ORIGINS has entries that are not website origins (like https://example.com), ignored: ${portalConfig.embedOriginsInvalid.join(' ')}`);
if (portalConfig.embedOrigins === null) console.warn('EMBED_ORIGINS is not set: any website may show the /embed widget in a frame. Set it to your own site, for example https://ridgeplow.com https://www.ridgeplow.com');
if (!aiConfig.apiKey) console.warn('ANTHROPIC_API_KEY is not set: the in-app assistant is off (the app shows it as not set up).');
else if (aiConfig.maxTokens < 8000) console.warn(`AI_MAX_TOKENS is ${aiConfig.maxTokens}: answers that need thinking plus a tool call are often cut off below 8000. Remove the setting or use 16000.`);
createFullServer(config, portalConfig, {}, aiConfig).listen(config.port, () => console.log(`Ridgeline server listening on ${config.port}`));
