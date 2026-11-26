// The public pages for the App Store listing (/privacy, /support, /terms) and the client-page fixes from the pre-launch sweep.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createFullServer } from '../app.mjs';
import { loadConfig } from '../server.mjs';
import { loadPortalConfig } from '../portal.mjs';
import { loadAiConfig } from '../ai.mjs';
import { PRIVACY, TERMS_URL, cleanSupportEmail, privacySections, supportSections } from '../legal.mjs';

const TOKEN = 'AbCdEfGhIjKlMnOpQrStUv01';

async function boot(env = {}, over = {}) {
  let t = 1_800_000_000_000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const pc = { ...loadPortalConfig(env), ownerTokens: ['owner-token'], ...over };
  const server = createFullServer({ ...loadConfig({}), tokens: ['owner-token'] }, pc, { portal: { now: clock.now, log: () => {} } }, loadAiConfig({ API_TOKENS: 'owner-token' }));
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const owner = (method, p, body) => fetch(base + p, { method, headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const publish = (site = {}) => owner('PUT', '/v1/portal/snapshot', { company: 'Ridge Plow', storm: { id: 'storm-1', name: 'Nov 18 storm' },
    sites: [{ token: TOKEN, label: '14 Elm Ave', status: 'planned', canRequest: true, siteLocation: { latitude: 44.97, longitude: -93.26 }, ...site }] });
  const form = (path, fields) => fetch(`${base}/c/${TOKEN}/${path}`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields).toString() });
  return { base, owner, publish, form, clock, server, close: () => { server.closeAllConnections(); server.close(); } };
}

test('the three public pages need no token, are real pages in the client-page style, and may be indexed', async (t) => {
  const s = await boot(); t.after(s.close);
  for (const [path, words] of [['/privacy', 'Privacy Policy for Ridgeline Ops'], ['/support', 'Restore a plan you already bought'], ['/terms', 'End User License Agreement']]) {
    const r = await fetch(s.base + path);                                               // no Authorization header at all
    assert.equal(r.status, 200, path);
    assert.match(r.headers.get('content-type'), /^text\/html/);
    const html = await r.text();
    assert.ok(html.includes(words), `${path} is missing "${words}"`);
    assert.ok(html.includes('class="card') && html.includes('--card:#2b2b2f'), `${path} uses the dark card style`);
    assert.ok(!html.includes('name="robots"'), `${path} must not ask search engines to skip it`);
    assert.equal(r.headers.get('x-robots-tag'), 'all');
    assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
    assert.match(r.headers.get('content-security-policy'), /default-src 'none'/);
    assert.match(r.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    for (const link of ['href="/privacy"', 'href="/support"', 'href="/terms"']) assert.ok(html.includes(link), `${path} links to ${link}`);
    assert.equal((await fetch(`${s.base}${path}/`)).status, 200, `${path}/ works too`);
    assert.equal((await fetch(`${s.base}${path}?utm=x`)).status, 200);
    assert.equal((await fetch(s.base + path, { method: 'HEAD' })).status, 200);
    assert.equal((await fetch(s.base + path, { method: 'POST' })).status, 405);
  }
  assert.equal((await fetch(`${s.base}/privacy`, { headers: { authorization: 'Bearer wrong' } })).status, 200);   // a bad token changes nothing
  assert.equal((await fetch(`${s.base}/privacy-policy`)).status, 404);                 // only the three exact pages
  assert.equal((await (await fetch(`${s.base}/health`)).json()).ok, true);             // the rest of the server is untouched
});

test('the terms page says the app is under Apple\'s standard EULA and links to it', async (t) => {
  const s = await boot(); t.after(s.close);
  const html = await (await fetch(`${s.base}/terms`)).text();
  assert.equal(TERMS_URL, 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
  assert.ok(html.includes(`href="${TERMS_URL}"`));
  assert.match(html, /licensed to you under Apple's standard/);
});

test('the support page covers help, cancelling, restoring and deleting; the contact line comes from SUPPORT_EMAIL and is left out when unset', async (t) => {
  const none = await boot(); t.after(none.close);
  const plain = await (await fetch(`${none.base}/support`)).text();
  for (const words of ['Get help', 'Cancel or change a plan', 'Subscriptions', 'Restore purchases', 'Delete my account and data', 'App Support link']) assert.ok(plain.includes(words), words);
  assert.ok(!plain.includes('mailto:') && !/[\w.-]+@[\w-]+\.[a-z]/i.test(plain), 'no contact line when SUPPORT_EMAIL is unset');
  assert.ok(!(await (await fetch(`${none.base}/privacy`)).text()).includes('mailto:'));
  const set = await boot({ SUPPORT_EMAIL: ' help@ridgeline.example ' }); t.after(set.close);
  const withMail = await (await fetch(`${set.base}/support`)).text();
  assert.ok(withMail.includes('href="mailto:help@ridgeline.example"'));
  assert.ok(withMail.includes('Email help@ridgeline.example'));
  assert.ok((await (await fetch(`${set.base}/privacy`)).text()).includes('mailto:help@ridgeline.example'));
  // Anything that is not a plain address is dropped, so the setting can never put markup or a second header on the page.
  for (const bad of ['<script>alert(1)</script>@x.io', 'a@b.c"><b>', 'not an address', 'a@b', 'x@y.z\nBcc: evil@x.io', '']) assert.equal(cleanSupportEmail(bad), '', bad);
  const hostile = await boot({ SUPPORT_EMAIL: '"><script>alert(1)</script>@x.io' }); t.after(hostile.close);
  const safe = await (await fetch(`${hostile.base}/support`)).text();
  assert.ok(!safe.includes('<script>alert') && !safe.includes('mailto:'));
  assert.equal(supportSections('').length, supportSections('help@ridgeline.example').length);
});

test('the privacy page shows every line of the policy, and the policy is word for word the one inside the app', async (t) => {
  const s = await boot(); t.after(s.close);
  const html = await (await fetch(`${s.base}/privacy`)).text();
  const unescape = (x) => x.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const shown = unescape(html);
  for (const line of PRIVACY.split('\n').map((l) => l.replace(/^- /, '').trim()).filter(Boolean)) assert.ok(shown.includes(line), `not on the page: ${line.slice(0, 70)}`);
  const { sections } = privacySections();
  assert.deepEqual(sections.map((x) => x.heading), ['What stays on your device', 'What leaves your device, and why', 'What we do not do', 'Your choices and deleting your data', 'Children', 'Changes']);
  // What the app really does today must be in it.
  for (const fact of ['your own Anthropic key', 'Ridgeline Ops assistant server', 'does not store it', 'Contacts you pick', 'notifications made on your device',
    'expenses and receipt photos', 'Client phone numbers and email addresses are not sent', 'We do not sell your data', 'Delete my account and data']) assert.ok(PRIVACY.includes(fact), fact);

  const file = new URL('../../Sources/RidgelineCore/LegalText.swift', import.meta.url);
  if (!fs.existsSync(file)) return;                                                     // the server folder deployed on its own
  const swift = fs.readFileSync(file, 'utf8');
  const literal = swift.split('public static let privacy = """\n')[1].split('\n    """')[0];
  const inApp = literal.split('\n').map((l) => l.replace(/^ {4}/, '')).join('\n');
  assert.equal(inApp, PRIVACY, 'server/legal.mjs PRIVACY and LegalText.privacy have drifted apart: change both together');
  assert.ok(!PRIVACY.includes('\\') && !PRIVACY.includes('`'));                         // nothing that reads differently in Swift and JavaScript
  // The support text in the app names the same places in the app as the support page.
  for (const words of ['Restore purchases', 'Delete my account and data', 'Subscriptions']) assert.ok(swift.includes(words), words);
});

// ---- client page fixes

test('thank-you messages do not use up the request limit, so an urgent request still goes through', async (t) => {
  const s = await boot({}, { requestsPerTokenPerHour: 3, maxPendingPerToken: 3 }); t.after(s.close);
  await s.publish();
  for (const m of ['one', 'two', 'three']) assert.equal((await s.form('thanks', { message: m })).status, 303);
  assert.equal((await s.form('thanks', { message: 'four' })).status, 429);             // messages keep their own limit
  assert.equal((await s.form('request', { kind: 'urgent', reason: 'medical' })).status, 303);
  assert.equal((await s.form('request', { kind: 'service' })).status, 303);
  assert.equal((await s.form('request', { kind: 'skip' })).status, 303);
  assert.equal((await s.form('request', { kind: 'service' })).status, 429);            // and so do requests
});

test('checking for requests returns the newest ones with their status, so a long list never hides what just arrived', async (t) => {
  const s = await boot({}, { requestsPerTokenPerHour: 1000, maxPendingPerToken: 1000, ipLimitPerMinute: 100000 }); t.after(s.close);
  await s.publish();
  for (let i = 0; i < 205; i++) { s.clock.advance(1000); assert.equal((await s.form('request', { kind: 'service', note: `n${i}` })).status, 303); }
  const all = (await (await s.owner('GET', '/v1/portal/requests')).json()).requests;
  assert.equal(all.length, 200);
  assert.equal(all[all.length - 1].note, 'n204');                                      // the latest is always there
  assert.equal(all[0].note, 'n5');
  assert.ok(all.every((r, i) => i === 0 || r.createdAt >= all[i - 1].createdAt));      // still oldest first
  assert.equal(all[0].status, 'pending');
  assert.equal((await s.owner('POST', '/v1/portal/decisions', { id: all[0].id, status: 'accepted', message: 'ok' })).status, 200);
  const again = (await (await s.owner('GET', '/v1/portal/requests')).json()).requests;
  assert.equal(again.find((r) => r.id === all[0].id).status, 'accepted');
  const paged = (await (await s.owner('GET', `/v1/portal/requests?since=${encodeURIComponent(all[9].createdAt)}`)).json()).requests;
  assert.equal(paged[0].note, 'n15');                                                  // with since, it pages forward from there
});

test('a mistyped client link gets the plain page, never the owner API\'s token error; a trailing slash is the same page', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  assert.equal((await fetch(`${s.base}/c/${TOKEN}/`)).status, 200);
  for (const path of [`/c/${TOKEN}/nothing`, `/c/${TOKEN}/pay/extra`, '/c/']) {
    const r = await fetch(s.base + path);
    assert.equal(r.status, 404, path);
    assert.match(r.headers.get('content-type'), /^text\/html/, path);
    assert.ok(!(await r.text()).includes('token'), path);
  }
  assert.equal((await fetch(`${s.base}/v1/portal/requests`)).status, 401);             // the owner API still needs its token
  const page = await fetch(`${s.base}/c/${TOKEN}`);
  assert.equal(page.headers.get('strict-transport-security'), 'max-age=31536000');
  assert.equal(page.headers.get('x-robots-tag'), 'noindex');                           // client pages stay out of search
  assert.ok((await page.text()).includes('id="updated"'));
  assert.equal((await fetch(`${s.base}/c/${TOKEN}/live.json`)).headers.get('x-content-type-options'), 'nosniff');
});

test('a truck that stopped reporting leaves the map after four minutes, and the page is told how old each position is', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const live = async () => (await (await fetch(`${s.base}/c/${TOKEN}/live.json`)).json());
  await s.owner('PUT', '/v1/portal/trucks', { trucks: [{ label: 'Truck 1', latitude: 44.98, longitude: -93.27 }] });
  assert.equal((await live()).trucks[0].ageSeconds, 0);
  s.clock.advance(150_000);
  assert.equal((await live()).trucks[0].ageSeconds, 150);                              // still shown, and said to be 2.5 minutes old
  s.clock.advance(95_000);
  assert.deepEqual((await live()).trucks, []);                                         // 4 minutes 5 seconds: gone
  // The app sends the same place again every minute while parked, which keeps a standing truck on the map.
  for (let i = 0; i < 8; i++) { await s.owner('PUT', '/v1/portal/trucks', { trucks: [{ label: 'Truck 1', latitude: 44.98, longitude: -93.27 }] }); s.clock.advance(60_000); }
  assert.equal((await live()).trucks.length, 1);
  // Removing a truck that was shared without a name takes off the default name.
  await s.owner('PUT', '/v1/portal/trucks', { trucks: [{ latitude: 44.99, longitude: -93.28 }] });
  assert.equal((await live()).trucks.length, 2);
  await s.owner('PUT', '/v1/portal/trucks', { trucks: [], remove: [''] });
  assert.deepEqual((await live()).trucks.map((x) => x.label), ['Truck 1']);
  const js = fs.readFileSync(new URL('../assets/portal.js', import.meta.url), 'utf8');
  assert.ok(js.includes('Last seen about') && js.includes("'status' + (d.status === 'done'"));   // the page says so, and recolours the status
});
