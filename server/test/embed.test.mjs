import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { createFullServer } from '../app.mjs';
import { loadConfig } from '../server.mjs';
import { loadPortalConfig } from '../portal.mjs';
import { parseEmbedOrigins, extractCode } from '../embed.mjs';

const TOKEN = 'AbCdEfGhIjKlMnOpQrStUv01';
const TOKEN2 = 'ZyXwVuTsRqPoNmLkJiHgFe99';
const UNKNOWN = 'QqQqQqQqQqQqQqQqQqQqQq00';
const TIPS = { venmoURL: 'https://venmo.com/ridgeplow', paypalURL: 'https://paypal.me/ridgeplow', cashappURL: 'https://cash.app/$ridgeplow' };

async function boot(env = {}, over = {}) {
  let t = 1_800_000_000_000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const pc = { ...loadPortalConfig(env), ownerTokens: ['owner-token'], ...over };
  const server = createFullServer({ ...loadConfig({}), tokens: ['owner-token'], googleKey: 'k' }, pc, { portal: { now: clock.now, log: () => {} } });
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const publish = (sites, extra = {}) => fetch(`${base}/v1/portal/snapshot`, {
    method: 'PUT', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ company: 'Ridge Plow', storm: { id: 'storm-1', name: 'Nov 18 storm', expected: 'around 3 to 5 inches' }, sites, ...extra }),
  });
  const close = () => { server.closeAllConnections(); server.close(); };
  return { base, publish, close, clock };
}

const site = (token, label, status, more = {}) => ({ token, label, status, canRequest: status !== 'done', ...more });
const mapped = site(TOKEN, '14 Elm Ave', 'planned', { stopsAhead: 3, eta: 'Expected between 7:15 AM and 8:45 AM.', siteLocation: { latitude: 44.978, longitude: -93.265 } });
const weather = { summary: 'Snow, 28 F. About 4 inches by noon.', alerts: ['Winter Storm Warning until 6 PM'] };

test('embed.js is JavaScript, knows the server origin, and needs no third party', async (t) => {
  const s = await boot(); t.after(s.close);
  const res = await fetch(`${s.base}/embed.js`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /^text\/javascript/);
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  const js = await res.text();
  assert.ok(js.includes(`var ORIGIN_GUESS = "${s.base}";`), 'origin from the Host header');
  assert.ok(js.includes('data-ridgeline') && js.includes("'/embed/' + mode") && js.includes('code='));
  assert.ok(js.includes('e.origin === f.__ridgelineOrigin') && js.includes("d.ridgeline !== 'height'"));
  assert.ok(js.includes("'loading', 'lazy'") && js.includes('width:100%'));
  // No address anywhere but this server's (the comment shows the paste snippet with it).
  for (const u of js.match(/https?:\/\/[^\s"'<)]+/g) || []) assert.ok(u.startsWith(s.base), u);
  assert.doesNotThrow(() => new vm.Script(js));

  // PUBLIC_URL wins over the Host header, and a forged Host cannot put code into the script.
  const p = await boot({ PUBLIC_URL: 'https://plow.example.com/anything' }); t.after(p.close);
  assert.ok((await (await fetch(`${p.base}/embed.js`)).text()).includes('var ORIGIN_SET = "https://plow.example.com";'));
});

test('embed.js puts an iframe in the host page, passes ?code= through, and resizes only on messages from its own frame', async (t) => {
  const s = await boot(); t.after(s.close);
  const js = await (await fetch(`${s.base}/embed.js`)).text();
  const made = []; let listener = null;
  const host = (mode) => { const attrs = { 'data-ridgeline': '', ...(mode ? { 'data-mode': mode } : {}) }; return {
    getAttribute: (k) => (k in attrs ? attrs[k] : null), setAttribute: (k, v) => { attrs[k] = v; }, appendChild: (f) => made.push(f) }; };
  const hosts = [host(), host('tips')];
  const document = {
    currentScript: { src: `${s.base}/embed.js` }, readyState: 'complete', querySelectorAll: () => hosts,
    createElement: () => { const a = {}; return { style: {}, contentWindow: {}, setAttribute: (k, v) => { a[k] = v; }, attrs: a }; },
    addEventListener: () => {},
  };
  const window = { addEventListener: (type, fn) => { if (type === 'message') listener = fn; } };
  vm.runInNewContext(js, { window, document, location: { href: 'https://ridgeplow.com/track?code=' + TOKEN, search: '?code=' + TOKEN }, URL, URLSearchParams });
  assert.equal(made.length, 2);
  assert.equal(made[0].attrs.src, `${s.base}/embed/tracker?code=${TOKEN}`);
  assert.equal(made[1].attrs.src, `${s.base}/embed/tips`);                      // the tips widget never gets the code
  assert.equal(made[0].attrs.loading, 'lazy');
  listener({ origin: 'https://evil.example.com', source: made[0].contentWindow, data: { ridgeline: 'height', height: 900 } });
  assert.notEqual(made[0].style.height, '900px');
  listener({ origin: s.base, source: {}, data: { ridgeline: 'height', height: 900 } });
  assert.notEqual(made[0].style.height, '900px');
  listener({ origin: s.base, source: made[0].contentWindow, data: { ridgeline: 'height', height: 'x' } });
  listener({ origin: s.base, source: made[0].contentWindow, data: { ridgeline: 'height', height: 640.2 } });
  assert.equal(made[0].style.height, '641px');
  // A code that is not code-shaped is not passed on.
  made.length = 0; hosts.splice(0, 2, host());
  vm.runInNewContext(js, { window: { addEventListener: () => {} }, document, location: { href: 'https://x.com/?code=<script>', search: '?code=<script>' }, URL, URLSearchParams });
  assert.equal(made[0].attrs.src, `${s.base}/embed/tracker`);
});

test('the tracker without a code shows only the form, and no client data', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish([mapped], { weather, tips: TIPS });
  for (const q of ['', '?code=', '?code=%20']) {
    const res = await fetch(`${s.base}/embed/tracker${q}`);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.ok(html.includes('Track your service') && html.includes('Your property code') && html.includes('>Show<'));
    for (const x of ['14 Elm Ave', 'Ridge Plow', TOKEN, 'Planned for this storm', 'venmo', 'id="live"']) assert.ok(!html.includes(x), x);
    assert.ok(html.includes('src="/assets/frame.js"'));
  }
});

test('the tracker with a valid code shows status, arrival, stops ahead, the map and tip links that open in a new tab', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish([mapped, site(TOKEN2, '9 Oak St', 'done')], { weather, tips: TIPS });
  const res = await fetch(`${s.base}/embed/tracker?code=${TOKEN}`);
  assert.equal(res.status, 200);
  const html = await res.text();
  for (const x of ['14 Elm Ave', 'Planned for this storm', 'Estimated arrival', 'Expected between 7:15 AM and 8:45 AM.', '3 stops before yours.',
    'Snow, 28 F.', 'Winter Storm Warning until 6 PM', 'id="map"']) assert.ok(html.includes(x), x);
  assert.ok(html.includes(`href="/c/${TOKEN}/pay?for=tip" target="_blank" rel="noopener"`));
  assert.ok(html.includes(`href="/c/${TOKEN}/pay?for=coffee" target="_blank" rel="noopener"`));
  assert.ok(html.includes(`href="/c/${TOKEN}#ask" target="_blank" rel="noopener">Request service`));
  assert.ok(html.includes(`data-token="${TOKEN}"`) && html.includes('src="/assets/portal.js"') && html.includes('src="/assets/leaflet.js"'));
  assert.ok(!html.includes('9 Oak St'));                                               // only this client's page
  for (const tag of html.match(/<script[^>]*>/gi) || []) assert.ok(/src="\/assets\/[a-z.]+"/.test(tag) || /type="application\/json"/.test(tag), tag);
  // A whole season link pasted into the field works too.
  assert.ok((await (await fetch(`${s.base}/embed/tracker?code=${encodeURIComponent(`https://srv.example.com/c/${TOKEN}`)}`)).text()).includes('14 Elm Ave'));
  // The frame script and the live data it polls are served.
  assert.equal((await fetch(`${s.base}/assets/frame.js`)).status, 200);
  assert.equal((await fetch(`${s.base}/c/${TOKEN}/live.json`)).status, 200);
});

test('unknown and malformed codes get the same answer, and the tracker is rate limited like client pages', async (t) => {
  const s = await boot({}, { ipLimitPerMinute: 6 }); t.after(s.close);
  await s.publish([mapped]);
  const answers = [];
  for (const c of [UNKNOWN, 'short', '<script>alert(1)</script>', 'x'.repeat(400)]) {
    const res = await fetch(`${s.base}/embed/tracker?code=${encodeURIComponent(c)}`);
    answers.push([res.status, await res.text()]);
  }
  for (const [status, html] of answers) {
    assert.equal(status, 404);
    assert.equal(html, answers[0][1]);
    assert.ok(html.includes('We could not find that code'));
    assert.ok(!html.includes('<script>alert') && !html.includes('14 Elm Ave'));
  }
  let limited = false;
  for (let i = 0; i < 4; i++) if ((await fetch(`${s.base}/embed/tracker?code=${UNKNOWN}`)).status === 429) limited = true;
  assert.ok(limited);
});

test('only /embed pages may be framed: EMBED_ORIGINS or *, and client pages keep frame-ancestors none', async (t) => {
  const open = await boot(); t.after(open.close);
  await open.publish([mapped]);
  for (const p of ['/embed/tracker', `/embed/tracker?code=${TOKEN}`, `/embed/tracker?code=${UNKNOWN}`, '/embed/tips']) {
    const res = await fetch(open.base + p);
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /frame-ancestors \*(;|$)/, p);
    assert.match(csp, /default-src 'none'/);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(res.headers.get('set-cookie'), null);
    assert.equal(res.headers.get('x-frame-options'), null);
  }
  for (const p of [`/c/${TOKEN}`, `/c/${TOKEN}/pay`, '/privacy', `/c/${UNKNOWN}`]) {
    assert.match((await fetch(open.base + p)).headers.get('content-security-policy'), /frame-ancestors 'none'/, p);
  }

  const env = { EMBED_ORIGINS: 'https://ridgeplow.com https://www.ridgeplow.com/ bad;value' };
  const locked = await boot(env); t.after(locked.close);
  const csp = (await fetch(`${locked.base}/embed/tracker`)).headers.get('content-security-policy');
  assert.match(csp, /frame-ancestors https:\/\/ridgeplow\.com https:\/\/www\.ridgeplow\.com(;|$)/);
  assert.ok(!csp.includes('bad'));
  assert.match((await fetch(`${locked.base}/c/${TOKEN}`)).headers.get('content-security-policy'), /frame-ancestors 'none'/);

  assert.deepEqual(parseEmbedOrigins(undefined), { origins: null, invalid: [] });
  assert.deepEqual(parseEmbedOrigins('https://a.com,https://*.b.com').origins, ['https://a.com', 'https://*.b.com']);
  assert.deepEqual(parseEmbedOrigins("'unsafe-inline' javascript:x").origins, []);
  assert.equal(extractCode(` https://s.example.com/c/${TOKEN} `), TOKEN);
  assert.equal(extractCode(`https://ridgeplow.com/track?code=${TOKEN}`), TOKEN);
});

test('the tips widget shows the company, the pay apps and storm progress as counts, and never an address', async (t) => {
  const s = await boot(); t.after(s.close);
  assert.ok((await (await fetch(`${s.base}/embed/tips`)).text()).includes('not set up yet'));
  const sites = [mapped, site(TOKEN2, '9 Oak St', 'done'), site('Third3Third3Third3Third3', '1 Pine Rd', 'planned'),
    site('Fourth4Fourth4Fourth4Fo', '2 Birch Ln', 'notExpected')];
  await s.publish(sites, { tips: TIPS, weather });
  const html = await (await fetch(`${s.base}/embed/tips`)).text();
  assert.ok(html.includes('Ridge Plow'));
  assert.ok(html.includes('Crews are out: 1 of 3 stops done'));
  assert.ok(html.includes('href="/embed/tips/pay?for=tip" target="_blank" rel="noopener"') && html.includes('Send a coffee'));
  for (const x of ['14 Elm Ave', '9 Oak St', '1 Pine Rd', '2 Birch Ln', TOKEN, TOKEN2, 'Expected between', 'Snow, 28 F']) assert.ok(!html.includes(x), x);
  const pay = await (await fetch(`${s.base}/embed/tips/pay?for=coffee`)).text();
  for (const x of ['Send a coffee', 'https://venmo.com/ridgeplow', 'https://paypal.me/ridgeplow', 'https://cash.app/$ridgeplow']) assert.ok(pay.includes(x), x);
  for (const x of ['14 Elm Ave', '9 Oak St', TOKEN]) assert.ok(!pay.includes(x), x);

  // Everyone done: a finished line; a day later, nothing.
  await s.publish(sites.map((x) => ({ ...x, status: x.status === 'planned' ? 'done' : x.status })), { tips: TIPS });
  assert.ok((await (await fetch(`${s.base}/embed/tips`)).text()).includes('All 3 stops are done for this storm'));
  s.clock.advance(13 * 3_600_000);
  const later = await (await fetch(`${s.base}/embed/tips`)).text();
  assert.ok(!later.includes('stops are done') && !later.includes('Crews are out'));
  // No storm work at all: no progress line.
  await s.publish([site(TOKEN, '14 Elm Ave', 'notExpected')]);
  const quiet = await (await fetch(`${s.base}/embed/tips`)).text();
  assert.ok(!quiet.includes('Crews are out') && !quiet.includes('class="tipbtn"') && quiet.includes('Thank you for choosing us'));
});

test('the company name is escaped in every widget', async (t) => {
  const s = await boot(); t.after(s.close);
  const evil = '<img src=x onerror=alert(1)>"Plow\'s';
  await fetch(`${s.base}/v1/portal/snapshot`, {
    method: 'PUT', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ company: evil, storm: { id: 's', name: '<b>storm</b>' }, sites: [mapped], tips: TIPS }),
  });
  for (const p of ['/embed/tips', '/embed/tips/pay?for=tip', `/embed/tracker?code=${TOKEN}`]) {
    const html = await (await fetch(s.base + p)).text();
    assert.ok(!html.includes('<img') && !html.includes('<b>storm'), p);
    assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;&quot;Plow&#39;s') || p.includes('tracker'), p);
  }
  assert.ok((await (await fetch(`${s.base}/embed/tracker?code=${TOKEN}`)).text()).includes('&lt;img src=x'));
});

test('embed pages answer only GET and HEAD', async (t) => {
  const s = await boot(); t.after(s.close);
  assert.equal((await fetch(`${s.base}/embed/tracker`, { method: 'POST' })).status, 405);
  assert.equal((await fetch(`${s.base}/embed.js`, { method: 'HEAD' })).status, 200);
  assert.equal((await fetch(`${s.base}/embed/nothing`)).status, 404);
});
