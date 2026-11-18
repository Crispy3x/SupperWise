// Ridgeline Ops routing proxy. Zero dependencies.
// Holds the Google Maps key (never ship it in the app), checks who is calling, caps cost, caches, and
// returns a drive-time matrix. See README.md in this folder.
import http from 'node:http';
import crypto from 'node:crypto';

export const GOOGLE_ENDPOINT = 'https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix';
export const FIELD_MASK = 'originIndex,destinationIndex,duration,condition';

export function loadConfig(env = process.env) {
  const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
  return {
    port: num(env.PORT, 8080),
    googleKey: env.GOOGLE_MAPS_API_KEY || '',
    upstreamUrl: env.UPSTREAM_URL || GOOGLE_ENDPOINT,
    tokens: (env.API_TOKENS || '').split(',').map((t) => t.trim()).filter(Boolean),
    maxPoints: num(env.MAX_POINTS, 30),
    maxElementsPerRequest: num(env.MAX_ELEMENTS_PER_REQUEST, 100),
    cacheTtlSeconds: num(env.CACHE_TTL_SECONDS, 300),
    rateLimitPerMinute: num(env.RATE_LIMIT_PER_MIN, 30),
    dailyElementCap: num(env.DAILY_ELEMENT_CAP, 3000),
    maxBodyBytes: num(env.MAX_BODY_BYTES, 1_000_000),
  };
}

/** Same block splitting as the Swift MatrixChunker: square blocks that fit the per-request element limit. */
export function blocks(count, maxElements) {
  if (count <= 0 || maxElements <= 0) return [];
  const side = Math.max(1, Math.floor(Math.sqrt(maxElements)));
  const out = [];
  for (let o = 0; o < count; o += side) {
    for (let d = 0; d < count; d += side) {
      out.push({ o0: o, o1: Math.min(o + side, count), d0: d, d1: Math.min(d + side, count) });
    }
  }
  return out;
}

const waypoint = (p) => ({ waypoint: { location: { latLng: { latitude: p.latitude, longitude: p.longitude } } } });

export function buildBody(origins, destinations, departureTime) {
  const body = {
    origins: origins.map(waypoint),
    destinations: destinations.map(waypoint),
    travelMode: 'DRIVE',
    routingPreference: 'TRAFFIC_AWARE',
  };
  if (departureTime) body.departureTime = departureTime;
  return body;
}

/** Returns seconds[origin][destination], null where no route was found. */
export function parseUpstream(items, originCount, destinationCount) {
  if (!Array.isArray(items)) throw new Error('Upstream response was not an array');
  const out = Array.from({ length: originCount }, () => Array(destinationCount).fill(null));
  for (const item of items) {
    const o = item?.originIndex ?? 0; // the API omits zero-valued fields in some responses
    const d = item?.destinationIndex ?? 0;
    if (!Number.isInteger(o) || !Number.isInteger(d) || o < 0 || d < 0 || o >= originCount || d >= destinationCount) {
      throw new Error('Upstream element index out of range');
    }
    if (item.condition === 'ROUTE_NOT_FOUND') continue;
    if (typeof item.duration === 'string' && item.duration.endsWith('s')) {
      const secs = Number(item.duration.slice(0, -1));
      if (Number.isFinite(secs) && secs >= 0) out[o][d] = secs;
    }
  }
  return out;
}

export function validatePoints(points, maxPoints) {
  if (!Array.isArray(points)) return 'points must be an array';
  if (points.length < 2) return 'at least 2 points are required';
  if (points.length > maxPoints) return `at most ${maxPoints} points are allowed`;
  for (const p of points) {
    const ok = p && Number.isFinite(p.latitude) && Number.isFinite(p.longitude) &&
      p.latitude >= -90 && p.latitude <= 90 && p.longitude >= -180 && p.longitude <= 180;
    if (!ok) return 'every point needs numeric latitude (-90..90) and longitude (-180..180)';
  }
  return null;
}

const digest = (s) => crypto.createHash('sha256').update(s).digest();

export function createHandler(config, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const now = deps.now ?? (() => Date.now());
  const log = deps.log ?? ((line) => console.log(line));
  const tokenDigests = config.tokens.map(digest);
  const cache = new Map();         // key -> { value, expires }
  const rate = new Map();          // token digest hex -> timestamps
  const daily = new Map();         // `${tokenHex}:${yyyy-mm-dd}` -> elements used
  const MAX_CACHE_ENTRIES = 500;

  const authorized = (req) => {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return null;
    const d = digest(header.slice(7));
    let match = false;
    for (const t of tokenDigests) if (crypto.timingSafeEqual(t, d)) match = true; // no early exit
    return match ? d.toString('hex') : null;
  };

  const send = (res, status, obj, extraHeaders = {}) => {
    const body = JSON.stringify(obj);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body), ...extraHeaders });
    res.end(body);
  };

  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0;
    let tooLarge = false;
    const chunks = [];
    req.on('data', (c) => {
      if (tooLarge) return;                       // keep discarding; the connection is closed after the reply
      size += c.length;
      if (size > config.maxBodyBytes) { tooLarge = true; chunks.length = 0; reject(Object.assign(new Error('too large'), { status: 413 })); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });

  const cacheKey = (points) => points.map((p) => `${p.latitude.toFixed(5)},${p.longitude.toFixed(5)}`).join(';');

  async function computeMatrix(points, departureTime) {
    const n = points.length;
    const seconds = Array.from({ length: n }, () => Array(n).fill(null));
    for (const b of blocks(n, config.maxElementsPerRequest)) {
      const origins = points.slice(b.o0, b.o1);
      const destinations = points.slice(b.d0, b.d1);
      const res = await fetchImpl(config.upstreamUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-Goog-Api-Key': config.googleKey, 'X-Goog-FieldMask': FIELD_MASK },
        body: JSON.stringify(buildBody(origins, destinations, departureTime)),
      });
      if (!res.ok) throw new Error(`Upstream returned ${res.status}`);
      const part = parseUpstream(await res.json(), origins.length, destinations.length);
      part.forEach((row, oi) => row.forEach((v, di) => { seconds[b.o0 + oi][b.d0 + di] = v; }));
    }
    for (let i = 0; i < n; i++) seconds[i][i] = 0;
    return seconds;
  }

  async function handleMatrix(req, res) {
    const who = authorized(req);
    if (!who) return send(res, 401, { error: 'Missing or invalid token' });

    const t = now();
    const recent = (rate.get(who) ?? []).filter((x) => t - x < 60_000);
    if (recent.length >= config.rateLimitPerMinute) return send(res, 429, { error: 'Too many requests, slow down' });
    recent.push(t);
    rate.set(who, recent);

    let payload;
    try { payload = JSON.parse(await readBody(req)); }
    catch (e) {
      if (e.status === 413) {
        res.on('finish', () => req.destroy());   // close only after the reply has been sent
        return send(res, 413, { error: 'Request too large' }, { connection: 'close' });
      }
      return send(res, 400, { error: 'Body must be JSON' });
    }

    const problem = validatePoints(payload?.points, config.maxPoints);
    if (problem) return send(res, 400, { error: problem });
    const points = payload.points;
    const elements = points.length * points.length;

    const key = cacheKey(points);
    const hit = cache.get(key);
    if (hit && hit.expires > t) {
      log(`matrix cached points=${points.length}`);
      return send(res, 200, { seconds: hit.value, cached: true, elements: 0 });
    }

    const day = new Date(t).toISOString().slice(0, 10);
    const dayKey = `${who}:${day}`;
    const used = daily.get(dayKey) ?? 0;
    if (used + elements > config.dailyElementCap) return send(res, 429, { error: 'Daily routing limit reached' });

    if (!config.googleKey) return send(res, 503, { error: 'Routing service is not configured' });

    try {
      const seconds = await computeMatrix(points, typeof payload.departureTime === 'string' ? payload.departureTime : undefined);
      daily.set(dayKey, used + elements);
      if (cache.size >= MAX_CACHE_ENTRIES) cache.delete(cache.keys().next().value);
      cache.set(key, { value: seconds, expires: t + config.cacheTtlSeconds * 1000 });
      log(`matrix computed points=${points.length} elements=${elements}`);
      return send(res, 200, { seconds, cached: false, elements });
    } catch (e) {
      log(`matrix upstream failure: ${e.message}`); // message never contains the key
      return send(res, 502, { error: 'Routing provider failed' });
    }
  }

  return (req, res) => {
    const url = (req.url || '').split('?')[0];
    if (req.method === 'GET' && url === '/health') return send(res, 200, { ok: true });
    if (req.method === 'POST' && url === '/v1/matrix') {
      handleMatrix(req, res).catch(() => send(res, 500, { error: 'Internal error' }));
      return;
    }
    send(res, 404, { error: 'Not found' });
  };
}

export function createApp(config, deps = {}) {
  return http.createServer(createHandler(config, deps));
}
