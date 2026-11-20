import http from 'node:http';
import { createHandler, loadConfig } from './server.mjs';
import { createPortal, loadPortalConfig } from './portal.mjs';
import { createAi, loadAiConfig } from './ai.mjs';

/** One server: client pages and owner portal API from portal.mjs, drive times from server.mjs. */
export function createFullServer(routingConfig, portalConfig, deps = {}, aiConfig = loadAiConfig()) {
  const routing = createHandler(routingConfig, deps.routing || {});
  const portal = createPortal(portalConfig, deps.portal || {});
  const ai = createAi(aiConfig, deps.ai || {});
  const server = http.createServer((req, res) => {
    if (portal.matches(req.url)) { portal.handle(req, res); return; }
    if (ai.matches(req.url)) { ai.handle(req, res); return; }
    routing(req, res);
  });
  server.portal = portal;
  server.ai = ai;
  return server;
}

export { loadConfig, loadPortalConfig, loadAiConfig };
