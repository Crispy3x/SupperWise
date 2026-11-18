import http from 'node:http';
import { createHandler, loadConfig } from './server.mjs';
import { createPortal, loadPortalConfig } from './portal.mjs';

/** One server: client pages and owner portal API from portal.mjs, drive times from server.mjs. */
export function createFullServer(routingConfig, portalConfig, deps = {}) {
  const routing = createHandler(routingConfig, deps.routing || {});
  const portal = createPortal(portalConfig, deps.portal || {});
  const server = http.createServer((req, res) => {
    if (portal.matches(req.url)) { portal.handle(req, res); return; }
    routing(req, res);
  });
  server.portal = portal;
  return server;
}

export { loadConfig, loadPortalConfig };
