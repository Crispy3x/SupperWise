import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createApp, loadConfig, blocks, buildBody, parseUpstream, validatePoints, FIELD_MASK } from '../server.mjs';

// A stand-in for Google: duration = (|dlat| + |dlon|) * 10000 seconds. Origin at latitude 0 has no routes.
function startUpstream({ fail = false } = {}) {
  const calls = [];
  const server = http.createServer((req, res) => {
    let data = '';
    req.on('data', (c) => (data += c));
    req.on('end', () => {
      const body = JSON.parse(data);
      calls.push({ headers: req.headers, body });
      if (fail) { res.writeHead(500); res.end('boom SECRET-KEY-VALUE'); return; }
      const out = [];
      body.origins.forEach((o, oi) => body.destinations.forEach((d, di) => {
        const a = o.waypoint.location.latLng, b = d.waypoint.location.latLng;
        if (a.latitude === 0) out.push({ originIndex: oi, destinationIndex: di, condition: 'ROUTE_NOT_FOUND' });
        else out.push({ originIndex: oi, destinationIndex: di, duration: `${Math.round((Math.abs(a.latitude - b.latitude) + Math.abs(a.longitude - b.longitude)) * 10000)}s`, condition: 'ROUTE_EXISTS' });
      }));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(out));
    });
  });
  return new Promise((resolve) => server.listen(0, () => resolve({ server, calls, url: `http://127.0.0.1:${server.address().port}/` })));
}

async function boot(overrides = {}, upstreamOpts = {}, deps = {}) {
  const up = await startUpstream(upstreamOpts);
  const config = { ...loadConfig({}), googleKey: 'SECRET-KEY-VALUE', tokens: ['good-token'], upstreamUrl: up.url, ...overrides };
  const logs = [];
  const app = createApp(config, { log: (l) => logs.push(l), ...deps });
  await new Promise((r) => app.listen(0, r));
  const base = `http://127.0.0.1:${app.address().port}`;
  const post = (points, token = 'good-token', extra = {}) =>
    fetch(`${base}/v1/matrix`, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ points, ...extra }) });
  const close = () => { app.closeAllConnections(); app.close(); up.server.closeAllConnections(); up.server.close(); };
  return { base, post, up, logs, close };
}

const pts = (n, lat0 = 45) => Array.from({ length: n }, (_, i) => ({ latitude: lat0 + i * 0.01, longitude: -93 }));

test('blocks cover every pair once within the limit', () => {
  const seen = new Set();
  for (const b of blocks(60, 625)) {
    assert.ok((b.o1 - b.o0) * (b.d1 - b.d0) <= 625);
    for (let o = b.o0; o < b.o1; o++) for (let d = b.d0; d < b.d1; d++) { assert.ok(!seen.has(`${o},${d}`)); seen.add(`${o},${d}`); }
  }
  assert.equal(seen.size, 3600);
  assert.deepEqual(blocks(0, 10), []);
});

test('parseUpstream reads durations and missing routes', () => {
  const m = parseUpstream([
    { originIndex: 0, destinationIndex: 1, duration: '185s' },
    { originIndex: 1, destinationIndex: 0, condition: 'ROUTE_NOT_FOUND' },
    { destinationIndex: 1, duration: '0s' },   // originIndex omitted means 0 in proto3 JSON
  ], 2, 2);
  assert.equal(m[0][1], 0);                    // overwritten by the later element (same cell)
  assert.equal(m[1][0], null);
  assert.throws(() => parseUpstream({}, 2, 2));
  assert.throws(() => parseUpstream([{ originIndex: 5, destinationIndex: 0 }], 2, 2));
});

test('buildBody matches the Google request shape', () => {
  const b = buildBody(pts(2), pts(3), '2030-01-01T00:00:00Z');
  assert.equal(b.travelMode, 'DRIVE');
  assert.equal(b.routingPreference, 'TRAFFIC_AWARE');
  assert.equal(b.origins.length, 2);
  assert.equal(b.destinations.length, 3);
  assert.equal(b.departureTime, '2030-01-01T00:00:00Z');
  assert.equal(buildBody(pts(1), pts(1)).departureTime, undefined);
});

test('validatePoints rejects bad input', () => {
  assert.ok(validatePoints('x', 50));
  assert.ok(validatePoints([pts(1)[0]], 50));
  assert.ok(validatePoints(pts(51), 50));
  assert.ok(validatePoints([{ latitude: 100, longitude: 0 }, pts(1)[0]], 50));
  assert.ok(validatePoints([{ latitude: 'a', longitude: 0 }, pts(1)[0]], 50));
  assert.equal(validatePoints(pts(5), 50), null);
});

test('rejects missing and wrong tokens, health needs none', async (t) => {
  const s = await boot();
  t.after(() => s.close());
  assert.equal((await s.post(pts(3), null)).status, 401);
  assert.equal((await s.post(pts(3), 'nope')).status, 401);
  assert.equal((await fetch(`${s.base}/health`)).status, 200);
  assert.equal((await fetch(`${s.base}/other`)).status, 404);
  assert.equal(s.up.calls.length, 0);
});

test('returns a full matrix, sends the key and field mask upstream, never logs the key', async (t) => {
  const s = await boot();
  t.after(() => s.close());
  const res = await s.post(pts(3));
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.seconds.length, 3);
  assert.equal(json.seconds[0][0], 0);
  assert.equal(json.seconds[0][1], 100);       // 0.01 degree latitude * 10000
  assert.equal(json.cached, false);
  assert.equal(json.elements, 9);
  assert.equal(s.up.calls[0].headers['x-goog-api-key'], 'SECRET-KEY-VALUE');
  assert.equal(s.up.calls[0].headers['x-goog-fieldmask'], FIELD_MASK);
  assert.ok(!s.logs.join('\n').includes('SECRET-KEY-VALUE'));
});

test('splits large matrices into allowed-size upstream requests', async (t) => {
  const s = await boot({ maxElementsPerRequest: 100 });
  t.after(() => s.close());
  const json = await (await s.post(pts(30))).json();
  assert.equal(s.up.calls.length, 9);          // side 10 -> 3 x 3 blocks
  for (const c of s.up.calls) assert.ok(c.body.origins.length * c.body.destinations.length <= 100);
  assert.equal(json.seconds.length, 30);
  assert.equal(json.seconds[29][0], Math.round(29 * 0.01 * 10000));
});

test('missing routes come back as null for the app to fill', async (t) => {
  const s = await boot();
  t.after(() => s.close());
  const json = await (await s.post([{ latitude: 0, longitude: 0 }, { latitude: 45, longitude: -93 }])).json();
  assert.equal(json.seconds[0][1], null);
  assert.equal(json.seconds[1][0] > 0, true);
  assert.equal(json.seconds[0][0], 0);
});

test('cache avoids a second upstream call and does not count toward the daily cap', async (t) => {
  const s = await boot({ dailyElementCap: 9 });
  t.after(() => s.close());
  const first = await (await s.post(pts(3))).json();
  const second = await s.post(pts(3));
  assert.equal(second.status, 200);
  const j2 = await second.json();
  assert.equal(j2.cached, true);
  assert.deepEqual(j2.seconds, first.seconds);
  assert.equal(s.up.calls.length, 1);
});

test('cache entries expire', async (ctx) => {
  let t = 1_700_000_000_000;
  const s = await boot({ cacheTtlSeconds: 60 }, {}, { now: () => t });
  ctx.after(() => s.close());
  await s.post(pts(3));
  t += 61_000;
  const j = await (await s.post(pts(3))).json();
  assert.equal(j.cached, false);
  assert.equal(s.up.calls.length, 2);
});

test('daily element cap blocks further spend, and resets the next day', async (ctx) => {
  let t = Date.UTC(2030, 0, 1, 12);
  const s = await boot({ dailyElementCap: 20, rateLimitPerMinute: 1000 }, {}, { now: () => t });
  ctx.after(() => s.close());
  assert.equal((await s.post(pts(4, 45))).status, 200);    // 16 elements
  assert.equal((await s.post(pts(3, 46))).status, 429);    // 9 more would pass 20
  t += 24 * 3600 * 1000;
  assert.equal((await s.post(pts(3, 46))).status, 200);
});

test('rate limit per token per minute', async (ctx) => {
  let t = 1_700_000_000_000;
  const s = await boot({ rateLimitPerMinute: 2 }, {}, { now: () => t });
  ctx.after(() => s.close());
  assert.equal((await s.post(pts(2, 45))).status, 200);
  assert.equal((await s.post(pts(2, 46))).status, 200);
  assert.equal((await s.post(pts(2, 47))).status, 429);
  t += 61_000;
  assert.equal((await s.post(pts(2, 48))).status, 200);
});

test('bad input gets 400 and costs nothing upstream', async (t) => {
  const s = await boot();
  t.after(() => s.close());
  assert.equal((await s.post(pts(1))).status, 400);
  assert.equal((await s.post(pts(51))).status, 400);
  const bad = await fetch(`${s.base}/v1/matrix`, { method: 'POST', headers: { authorization: 'Bearer good-token' }, body: 'not json' });
  assert.equal(bad.status, 400);
  assert.equal(s.up.calls.length, 0);
});

test('upstream failure returns 502 without leaking upstream text or the key', async (t) => {
  const s = await boot({}, { fail: true });
  t.after(() => s.close());
  const res = await s.post(pts(3));
  assert.equal(res.status, 502);
  const text = await res.text();
  assert.ok(!text.includes('SECRET-KEY-VALUE'));
  assert.ok(!s.logs.join('\n').includes('SECRET-KEY-VALUE'));
});

test('no key configured returns 503 instead of calling out', async (t) => {
  const s = await boot({ googleKey: '' });
  t.after(() => s.close());
  assert.equal((await s.post(pts(3))).status, 503);
  assert.equal(s.up.calls.length, 0);
});

test('oversized body is rejected', async (t) => {
  const s = await boot({ maxBodyBytes: 100 });
  t.after(() => s.close());
  const res = await fetch(`${s.base}/v1/matrix`, { method: 'POST', headers: { authorization: 'Bearer good-token' }, body: JSON.stringify({ points: pts(20) }) });
  assert.equal(res.status, 413);
});
