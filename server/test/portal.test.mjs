import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createFullServer } from '../app.mjs';
import { loadConfig } from '../server.mjs';
import { loadPortalConfig, escapeHtml, cleanText, isValidEmail } from '../portal.mjs';

const TOKEN = 'AbCdEfGhIjKlMnOpQrStUv01';        // 24 well-formed characters
const TOKEN2 = 'ZyXwVuTsRqPoNmLkJiHgFe99';

async function boot(over = {}, deps = {}) {
  let t = 1_800_000_000_000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const emailCalls = [];
  const fakeFetch = deps.fetch ?? (async (url, init) => { emailCalls.push({ url, init, body: JSON.parse(init.body) }); return { ok: true, status: 200 }; });
  const logs = [];
  const pc = { ...loadPortalConfig({}), ownerTokens: ['owner-token'], resendKey: 'RESEND-SECRET', fromEmail: 'storm@example.com', replyTo: 'help@example.com', ...over };
  const server = createFullServer({ ...loadConfig({}), tokens: ['owner-token'], googleKey: 'k' }, pc,
    { portal: { now: clock.now, fetch: fakeFetch, log: (l) => logs.push(l) } });
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const owner = (method, p, body) => fetch(base + p, { method, headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const publish = (sites, extra = {}) => owner('PUT', '/v1/portal/snapshot', {
    company: 'Ridge Plow', storm: { id: 'storm-1', name: 'Nov 18 storm', expected: 'around 3 to 5 inches' },
    sites: sites ?? [{ token: TOKEN, label: '14 Elm Ave', status: 'planned', detail: 'We expect to come this morning.', canRequest: true }], ...extra });
  const form = (token, fields) => fetch(`${base}/c/${token}/request`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields).toString() });
  const close = () => { server.closeAllConnections(); server.close(); };
  return { base, owner, publish, form, close, clock, emailCalls, logs, server, pc };
}

test('helpers', () => {
  assert.equal(escapeHtml(`<a href="x">'&`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;');
  assert.equal(cleanText('a\r\nb\u0000c   d', 50), 'a b c d');
  assert.equal(cleanText('x'.repeat(500), 10).length, 10);
  assert.equal(cleanText(42, 10), '');
  assert.ok(isValidEmail('a@b.co')); assert.ok(!isValidEmail('a@b')); assert.ok(!isValidEmail('a@b.co\nBcc: x@y.co')); assert.ok(!isValidEmail('a b@c.co'));
});

test('owner API needs the owner token; routing health still works on the same server', async (t) => {
  const s = await boot(); t.after(s.close);
  assert.equal((await fetch(`${s.base}/v1/portal/requests`)).status, 401);
  assert.equal((await fetch(`${s.base}/v1/portal/snapshot`, { method: 'PUT', headers: { authorization: 'Bearer wrong' } })).status, 401);
  assert.equal((await fetch(`${s.base}/v1/send/email`, { method: 'POST' })).status, 401);
  assert.equal((await fetch(`${s.base}/health`)).status, 200);
});

test('snapshot validation', async (t) => {
  const s = await boot(); t.after(s.close);
  assert.equal((await s.owner('PUT', '/v1/portal/snapshot', { company: 'x' })).status, 400);
  assert.equal((await s.publish([{ token: 'short', label: 'x', status: 'planned' }])).status, 400);
  assert.equal((await s.publish([{ token: TOKEN, label: 'x', status: 'hacked' }])).status, 400);
  assert.equal((await s.owner('PUT', '/v1/portal/snapshot', { company: 'x', storm: { name: 'no id' }, sites: [] })).status, 400);
  const big = Array.from({ length: 501 }, (_, i) => ({ token: String(i).padStart(24, 'a'), label: 'x', status: 'planned' }));
  assert.equal((await s.publish(big)).status, 400);
  const ok = await s.publish();
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { stored: 1 });
  assert.equal((await fetch(`${s.base}/v1/portal/snapshot`, { method: 'PUT', headers: { authorization: 'Bearer owner-token' }, body: 'not json' })).status, 400);
});

test('client page shows the status and has strict security headers', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const res = await fetch(`${s.base}/c/${TOKEN}`);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes('14 Elm Ave')); assert.ok(html.includes('Ridge Plow')); assert.ok(html.includes('around 3 to 5 inches')); assert.ok(html.includes('Planned for this storm'));
  assert.ok(html.includes('Forecasts can change'));
  assert.equal(res.headers.get('cache-control'), 'no-store');
  assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
  assert.match(res.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  // No inline code: every script tag is either our own file or inert data.
  for (const tag of html.match(/<script[^>]*>/gi) || []) assert.ok(/src="\/assets\/[a-z.]+"/.test(tag) || /type="application\/json"/.test(tag), tag);
  assert.match(res.headers.get('content-security-policy'), /script-src 'self'/);
  assert.match(res.headers.get('content-security-policy'), /img-src https:\/\/tile\.openstreetmap\.org/);
});

test('wrong, old and malformed links all get the same plain page', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const a = await fetch(`${s.base}/c/${TOKEN2}`);
  const b = await fetch(`${s.base}/c/short`);
  const c = await fetch(`${s.base}/c/${TOKEN}%00`);
  assert.deepEqual([a.status, b.status, c.status], [404, 404, 404]);
  assert.equal(await a.text(), await b.text());
});

test('hostile text from the owner app cannot inject markup into the client page', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish([{ token: TOKEN, label: '<img src=x onerror=alert(1)>', status: 'done', detail: '"><script>alert(1)</script>', canRequest: false }], { company: '<b>Evil</b>' });
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(!html.includes('<img src=x')); assert.ok(!html.includes('<script>alert')); assert.ok(!html.includes('<b>Evil'));
  assert.ok(html.includes('&lt;img'));
});

test('full request flow: client asks, owner polls, owner decides, client sees the answer', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const sent = await s.form(TOKEN, { kind: 'urgent', reason: 'leavingSoon', note: 'Need to leave by 7 <b>am</b>' });
  assert.equal(sent.status, 303);
  assert.equal(sent.headers.get('location'), `/c/${TOKEN}?sent=1`);
  const page = await (await fetch(`${s.base}/c/${TOKEN}?sent=1`)).text();
  assert.ok(page.includes('Request sent')); assert.ok(page.includes('Waiting for an answer'));

  const polled = await (await s.owner('GET', '/v1/portal/requests')).json();
  assert.equal(polled.requests.length, 1);
  const r = polled.requests[0];
  assert.deepEqual([r.token, r.kind, r.reason, r.stormId], [TOKEN, 'urgent', 'leavingSoon', 'storm-1']);
  assert.equal(r.note, 'Need to leave by 7 <b>am</b>');               // stored as text; escaped when shown
  assert.ok(!(await (await fetch(`${s.base}/c/${TOKEN}`)).text()).includes('<b>am</b>'));
  assert.equal((await (await s.owner('GET', `/v1/portal/requests?since=${encodeURIComponent(r.createdAt)}`)).json()).requests.length, 0);   // only newer ones
  assert.equal((await s.owner('GET', '/v1/portal/requests?since=garbage')).status, 400);

  assert.equal((await s.owner('POST', '/v1/portal/decisions', { id: r.id, status: 'accepted', message: 'You are first on our list' })).status, 200);
  const after = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(after.includes('Accepted')); assert.ok(after.includes('You are first on our list'));
  assert.equal((await s.owner('POST', '/v1/portal/decisions', { id: r.id, status: 'declined' })).status, 409);       // decided once
  assert.equal((await s.owner('POST', '/v1/portal/decisions', { id: 'nope', status: 'declined' })).status, 404);
  assert.equal((await s.owner('POST', '/v1/portal/decisions', { id: r.id, status: 'maybe' })).status, 400);
});

test('the page shows the arrival window, the winter summary and the bills, with amounts only if the app sent them', async (t) => {
  const s = await boot(); t.after(s.close);
  const bills = [
    { number: 'INV-0003', label: 'Storm Nov 18', total: '$60.00', status: 'Due', due: 'Due Dec 2, 2026' },
    { number: 'INV-0002', label: 'Storm Nov 3', total: '$60.00', status: 'Paid', due: '' },
    { number: 'INV-0001', label: '2 items', total: '', status: 'Overdue', due: 'Due Nov 1, 2026' },
  ];
  assert.equal((await s.publish([{ token: TOKEN, label: '14 Elm Ave', status: 'planned', detail: 'We expect to come.', canRequest: true,
    eta: 'Expected between 7:15 AM and 8:45 AM.', summary: '3 storms serviced so far this winter.', bills }])).status, 200);
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(html.includes('Estimated arrival')); assert.ok(html.includes('Expected between 7:15 AM and 8:45 AM.'));
  assert.ok(html.includes('3 storms serviced so far this winter.'));
  assert.ok(html.includes('Your bills this winter')); assert.ok(html.includes('INV-0003')); assert.ok(html.includes('$60.00'));
  assert.ok(html.includes('pill paid')); assert.ok(html.includes('pill overdue')); assert.ok(html.includes('Due Dec 2, 2026'));
  assert.ok(html.includes('We never see your card.'));
  assert.ok(!html.includes('Pay now'));                                  // no link sent, no button
});

test('a Pay now button appears only for unpaid bills and only for safe payment links', async (t) => {
  const s = await boot(); t.after(s.close);
  const bills = [
    { number: 'A', label: 'x', total: '$1.00', status: 'Due', due: 'Due soon', payURL: 'https://buy.stripe.com/abc123' },
    { number: 'B', label: 'x', total: '$1.00', status: 'Paid', due: '', payURL: 'https://buy.stripe.com/paid-one' },
    { number: 'C', label: 'x', total: '$1.00', status: 'Overdue', due: 'Due before', payURL: 'https://evil.example.com/pay' },
    { number: 'D', label: 'x', total: '$1.00', status: 'Due', due: 'Due soon', payURL: 'http://paypal.me/plow' },
    { number: 'E', label: 'x', total: '$1.00', status: 'Due', due: 'Due soon', payURL: 'https://paypal.com@evil.example.com/x' },
    { number: 'F', label: 'x', total: '$1.00', status: 'Due', due: 'Due soon', payURL: 'https://notstripe.com/x' },
    { number: 'G', label: 'x', total: '$1.00', status: 'Due', due: 'Due soon', payURL: 'javascript:alert(1)' },
  ];
  assert.equal((await s.publish([{ token: TOKEN, label: '14 Elm Ave', status: 'planned', detail: '', canRequest: false, bills }])).status, 200);
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.equal(html.split('Pay now').length - 1, 1);
  assert.ok(html.includes('https://buy.stripe.com/abc123'));
  assert.ok(!html.includes('paid-one')); assert.ok(!html.includes('evil.example.com')); assert.ok(!html.includes('javascript:'));
});

test('a page with no bills or estimate shows neither section', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(!html.includes('Your bills this winter')); assert.ok(!html.includes('Estimated arrival'));
});

test('bills are validated and hostile text in them is escaped', async (t) => {
  const s = await boot(); t.after(s.close);
  const site = (bills) => [{ token: TOKEN, label: 'x', status: 'planned', canRequest: true, bills }];
  assert.equal((await s.publish(site([{ number: 'x', status: 'Free money' }]))).status, 400);
  assert.equal((await s.publish(site('nope'))).status, 400);
  assert.equal((await s.publish(site(Array.from({ length: 31 }, () => ({ number: 'x', status: 'Due' }))))).status, 400);
  assert.equal((await s.publish(site(Array.from({ length: 30 }, () => ({ number: 'x', status: 'Due' }))))).status, 200);
  await s.publish([{ token: TOKEN, label: 'x', status: 'planned', canRequest: false, eta: '<script>alert(1)</script>', summary: '"><img src=x>',
    bills: [{ number: '<b>1</b>', label: '<i>l</i>', total: '$<u>1</u>', status: 'Due', due: '<s>d</s>' }] }]);
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  for (const bad of ['<script>alert', '<img src=x>', '<b>1</b>', '<i>l</i>', '<u>1</u>', '<s>d</s>']) assert.ok(!html.includes(bad), bad);
});

test('request validation', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  assert.equal((await s.form(TOKEN, { kind: 'hack' })).status, 400);
  assert.equal((await s.form(TOKEN, { kind: 'urgent' })).status, 400);                         // urgent needs a reason
  assert.equal((await s.form(TOKEN, { kind: 'urgent', reason: 'because' })).status, 400);
  assert.equal((await s.form(TOKEN, { kind: 'service', note: 'x'.repeat(2000) })).status, 303);
  const [r] = (await (await s.owner('GET', '/v1/portal/requests')).json()).requests;
  assert.equal(r.note.length, 500);
  assert.equal(r.reason, null);                                                                // a reason is kept only for urgent
  assert.equal((await s.form(TOKEN2, { kind: 'service' })).status, 404);                       // unknown page
});

test('pages that cannot request refuse requests', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish([{ token: TOKEN, label: 'x', status: 'done', canRequest: false }]);
  assert.equal((await s.form(TOKEN, { kind: 'service' })).status, 403);
  assert.ok(!(await (await fetch(`${s.base}/c/${TOKEN}`)).text()).includes(`action="/c/${TOKEN}/request"`));      // no request form (the thank-you message box stays)
});

test('limits: per page per hour, pending cap, per connection, and body size', async (t) => {
  const s = await boot({ requestsPerTokenPerHour: 3, maxPendingPerToken: 10 }); t.after(s.close);
  await s.publish();
  for (let i = 0; i < 3; i++) assert.equal((await s.form(TOKEN, { kind: 'service' })).status, 303);
  assert.equal((await s.form(TOKEN, { kind: 'service' })).status, 429);
  s.clock.advance(3_700_000);
  assert.equal((await s.form(TOKEN, { kind: 'service' })).status, 303);                        // an hour later it works again

  const p = await boot({ requestsPerTokenPerHour: 100, maxPendingPerToken: 2 }); t.after(p.close);
  await p.publish();
  assert.equal((await p.form(TOKEN, { kind: 'service' })).status, 303);
  assert.equal((await p.form(TOKEN, { kind: 'service' })).status, 303);
  assert.equal((await p.form(TOKEN, { kind: 'service' })).status, 429);

  const ip = await boot({ ipLimitPerMinute: 3 }); t.after(ip.close);
  await ip.publish();
  const codes = [];
  for (let i = 0; i < 5; i++) codes.push((await fetch(`${ip.base}/c/${TOKEN}`)).status);
  assert.deepEqual(codes, [200, 200, 200, 429, 429]);

  const sm = await boot({ maxBodyBytes: 200 }); t.after(sm.close);
  assert.equal((await fetch(`${sm.base}/v1/portal/snapshot`, { method: 'PUT', headers: { authorization: 'Bearer owner-token' }, body: 'x'.repeat(5000) })).status, 413);
});

test('old data is deleted: snapshots after their limit (14 days here), requests after 30', async (t) => {
  const s = await boot({ snapshotTtlDays: 14 }); t.after(s.close);
  await s.publish();
  await s.form(TOKEN, { kind: 'service' });
  s.clock.advance(15 * 86_400_000);
  await s.publish([{ token: TOKEN2, label: 'other', status: 'planned', canRequest: true }]);          // any write purges
  assert.equal((await fetch(`${s.base}/c/${TOKEN}`)).status, 404);
  assert.equal((await fetch(`${s.base}/c/${TOKEN2}`)).status, 200);
  assert.equal(s.server.portal._state().requests.length, 1);
  s.clock.advance(20 * 86_400_000);
  await s.publish([{ token: TOKEN2, label: 'other', status: 'planned', canRequest: true }]);
  assert.equal(s.server.portal._state().requests.length, 0);
});

test('requests survive a restart, and an unreadable data file is kept, not overwritten', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'portal-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'portal.json');
  const a = await boot({ dataFile: file });
  await a.publish(); await a.form(TOKEN, { kind: 'service' });
  a.close();
  const b = await boot({ dataFile: file }); t.after(b.close);
  assert.equal((await (await b.owner('GET', '/v1/portal/requests')).json()).requests.length, 1);
  assert.equal((await fetch(`${b.base}/c/${TOKEN}`)).status, 200);
  b.close();
  fs.writeFileSync(file, '{ broken');
  const c = await boot({ dataFile: file }); t.after(c.close);
  assert.equal((await fetch(`${c.base}/c/${TOKEN}`)).status, 404);                              // started empty, no crash
  assert.ok(fs.readdirSync(dir).some((f) => f.startsWith('portal.json.unreadable-')));          // the bad file was kept
});

test('email: needs configuration, validates, sends only what is safe, and never logs addresses or text', async (t) => {
  const none = await boot({ resendKey: '' }); t.after(none.close);
  assert.equal((await none.owner('POST', '/v1/send/email', { messages: [] })).status, 503);

  const s = await boot(); t.after(s.close);
  assert.equal((await s.owner('POST', '/v1/send/email', { messages: [] })).status, 400);
  assert.equal((await s.owner('POST', '/v1/send/email', { messages: Array(101).fill({}) })).status, 400);
  const res = await s.owner('POST', '/v1/send/email', { messages: [
    { to: 'pat@example.com', subject: 'Snow\r\nBcc: attacker@example.com', text: 'Hello Pat' },
    { to: 'not-an-email', subject: 'x', text: 'y' },
    { to: 'a@b.com, c@d.com', subject: 'x', text: 'y' },
    { to: 'sam@example.com', subject: '', text: 'no subject' },
  ] });
  const { results } = await res.json();
  assert.deepEqual(results.map((r) => r.ok), [true, false, false, false]);
  assert.equal(s.emailCalls.length, 1);
  const call = s.emailCalls[0];
  assert.equal(call.init.headers.authorization, 'Bearer RESEND-SECRET');
  assert.deepEqual(call.body.to, ['pat@example.com']);
  assert.equal(call.body.from, 'storm@example.com');
  assert.equal(call.body.reply_to, 'help@example.com');
  assert.ok(!/[\r\n]/.test(call.body.subject));
  assert.ok(!call.body.subject.includes('\n'));
  const logged = s.logs.join('\n');
  assert.ok(!logged.includes('pat@example.com')); assert.ok(!logged.includes('Hello Pat')); assert.ok(!logged.includes('RESEND-SECRET'));
});

test('email: provider failures are reported generically; daily cap stops sending', async (t) => {
  const failing = await boot({}, { fetch: async () => ({ ok: false, status: 422 }) }); t.after(failing.close);
  const r = await (await failing.owner('POST', '/v1/send/email', { messages: [{ to: 'a@b.co', subject: 's', text: 't' }] })).json();
  assert.deepEqual(r.results, [{ index: 0, ok: false, error: 'provider_rejected' }]);

  const down = await boot({}, { fetch: async () => { throw new Error('boom RESEND-SECRET'); } }); t.after(down.close);
  const d = await (await down.owner('POST', '/v1/send/email', { messages: [{ to: 'a@b.co', subject: 's', text: 't' }] })).json();
  assert.deepEqual(d.results, [{ index: 0, ok: false, error: 'provider_unreachable' }]);
  assert.ok(!JSON.stringify(d).includes('RESEND-SECRET'));

  const capped = await boot({ emailDailyCap: 2 }); t.after(capped.close);
  const msg = (n) => ({ to: `p${n}@example.com`, subject: 's', text: 't' });
  assert.equal((await capped.owner('POST', '/v1/send/email', { messages: [msg(1), msg(2)] })).status, 200);
  assert.equal((await capped.owner('POST', '/v1/send/email', { messages: [msg(3)] })).status, 429);
  capped.clock.advance(86_400_000);
  assert.equal((await capped.owner('POST', '/v1/send/email', { messages: [msg(3)] })).status, 200);
});

// ---- live map, weather, tips, home-screen manifest

const withMap = (extra = {}) => ({
  weather: { summary: 'Snow, 28 F. About 4 inches by noon.', alerts: ['Winter Storm Warning until 6 PM', 'b', 'c', 'd'] },
  tips: { venmoURL: 'https://venmo.com/ridgeplow', paypalURL: 'https://paypal.me/ridgeplow', cashappURL: 'https://cash.app/$ridgeplow' },
  sites: [{ token: TOKEN, label: '14 Elm Ave', status: 'planned', canRequest: true, stopsAhead: 3, eta: 'Expected between 7:15 AM and 8:45 AM.',
    siteLocation: { latitude: 44.97812345, longitude: -93.26512345 } }], ...extra });

test('the page shows the map, weather, tip buttons and stops ahead; the map data is inert JSON', async (t) => {
  const s = await boot(); t.after(s.close);
  assert.equal((await s.publish(withMap().sites, { weather: withMap().weather, tips: withMap().tips })).status, 200);
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(html.includes('Where is the truck?')); assert.ok(html.includes('id="map"'));
  assert.ok(html.includes('Snow, 28 F. About 4 inches by noon.'));
  assert.ok(html.includes('Winter Storm Warning until 6 PM'));
  assert.ok(!html.includes('>d<') || html.split('·').length <= 3);                 // at most three alerts
  assert.ok(html.includes('Tip the crew') && html.includes('Send a coffee'));
  assert.ok(html.includes(`/c/${TOKEN}/pay?for=tip`) && html.includes(`/c/${TOKEN}/pay?for=coffee`));
  assert.ok(!html.includes('donut') && !html.includes('Buy lunch'));
  assert.ok(!html.includes('https://venmo.com/ridgeplow'));                           // the links are on the pay page, not here
  for (const kind of ['tip', 'coffee']) {
    const pay = await (await fetch(`${s.base}/c/${TOKEN}/pay?for=${kind}`)).text();
    for (const x of ['Venmo', 'PayPal', 'Cash App', 'https://venmo.com/ridgeplow', 'https://paypal.me/ridgeplow', 'https://cash.app/$ridgeplow']) assert.ok(pay.includes(x), x);
  }
  assert.equal((await fetch(`${s.base}/c/short/pay`)).status, 404);
  assert.ok(html.includes('Request service') && html.includes('Send a kind message to your driver'));
  assert.ok(html.includes('src="/assets/leaflet.js"') && html.includes('src="/assets/portal.js"'));
  const live = JSON.parse(html.match(/<script type="application\/json" id="live">(.*?)<\/script>/s)[1]);
  assert.equal(live.stopsAhead, 3);
  assert.deepEqual(live.site, { latitude: 44.978, longitude: -93.265 });          // rounded to about 100 m
  assert.ok(html.includes('rel="manifest"'));
});

test('tip and coffee links must be safe payment links', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish(withMap().sites, { tips: { venmoURL: 'https://evil.example.com/tip', paypalURL: 'javascript:alert(1)' } });
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(!html.includes('Tip the crew')); assert.ok(!html.includes('Send a coffee')); assert.ok(!html.includes('evil.example.com'));
  assert.ok(html.includes('Send a kind message to your driver'));                      // the message box does not need any payment link
});

test('trucks show only for a property waiting for service, only while fresh, and positions are rounded', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish(withMap().sites);
  const live = async () => (await (await fetch(`${s.base}/c/${TOKEN}/live.json`)).json());
  assert.deepEqual((await live()).trucks, []);                                      // nothing shared yet
  const put = (body, auth = 'Bearer owner-token') => fetch(`${s.base}/v1/portal/trucks`, { method: 'PUT', headers: { authorization: auth, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  assert.equal((await put({ trucks: [] }, 'Bearer wrong')).status, 401);
  assert.equal((await put({ trucks: [{ label: 'Truck <b>1</b>', latitude: 44.98012345, longitude: -93.27012345 }] })).status, 200);
  const l = await live();
  assert.equal(l.trucks.length, 1);
  assert.deepEqual([l.trucks[0].latitude, l.trucks[0].longitude], [44.9801, -93.2701]);
  assert.equal(l.trucks[0].label, 'Truck <b>1</b>');                                // stored as text; the page uses textContent
  assert.equal(l.stopsAhead, 3); assert.equal(l.statusText, 'Planned for this storm');
  s.clock.advance(11 * 60_000);
  assert.deepEqual((await live()).trucks, []);                                      // stale positions disappear
  await put({ trucks: [{ label: 'T', latitude: 44.98, longitude: -93.27 }] });
  assert.equal((await live()).trucks.length, 1);                                    // the stale one is gone; this one is fresh
  await s.publish([{ token: TOKEN, label: '14 Elm Ave', status: 'done', canRequest: true, siteLocation: { latitude: 44.97, longitude: -93.26 } }]);
  assert.deepEqual((await live()).trucks, []);                                      // once served, no more trucks
  // Two trucks share at once: each is added by its label, and `remove` takes one off the map.
  await s.publish(withMap().sites);
  await put({ trucks: [], remove: ['T'] });
  await put({ trucks: [{ label: 'Truck 1', latitude: 44.98, longitude: -93.27 }] });
  await put({ trucks: [{ label: 'Truck 2', latitude: 44.99, longitude: -93.28 }] });
  assert.deepEqual((await live()).trucks.map((x) => x.label).sort(), ['Truck 1', 'Truck 2']);
  await put({ trucks: [{ label: 'Truck 1', latitude: 44.981, longitude: -93.271 }] });
  const moved = (await live()).trucks;
  assert.equal(moved.length, 2); assert.equal(moved.find((x) => x.label === 'Truck 1').latitude, 44.981);   // updated, not duplicated
  await put({ trucks: [], remove: ['Truck 1'] });
  assert.deepEqual((await live()).trucks.map((x) => x.label), ['Truck 2']);
  assert.equal((await put({ trucks: [], remove: 'x' })).status, 400);
  for (const bad of [{}, { trucks: 'x' }, { trucks: [{ latitude: 91, longitude: 0 }] }, { trucks: [{ latitude: 'a', longitude: 1 }] },
    { trucks: [{ latitude: 0, longitude: 0 }] }, { trucks: Array.from({ length: 11 }, () => ({ latitude: 1, longitude: 1 })) }]) {
    assert.equal((await put(bad)).status, 400, JSON.stringify(bad).slice(0, 50));
  }
});

test('live.json follows the same rules as the page: wrong links look alike and no contact details are in it', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish(withMap().sites, { weather: withMap().weather });
  assert.equal((await fetch(`${s.base}/c/${TOKEN}/live.json`)).status, 200);
  assert.equal((await fetch(`${s.base}/c/${'z'.repeat(30)}/live.json`)).status, 404);
  assert.equal((await fetch(`${s.base}/c/short/live.json`)).status, 404);
  assert.equal((await fetch(`${s.base}/c/${TOKEN}/live.json`, { method: 'POST' })).status, 405);
  const text = await (await fetch(`${s.base}/c/${TOKEN}/live.json`)).text();
  for (const secret of ['owner-token', 'RESEND', '@', 'company', 'Ridge Plow']) assert.ok(!text.includes(secret), secret);
});

test('the home-screen manifest is per page and the map files are served from this server', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish(withMap().sites);
  const m = await (await fetch(`${s.base}/c/${TOKEN}/manifest.webmanifest`)).json();
  assert.equal(m.start_url, `/c/${TOKEN}`); assert.equal(m.display, 'standalone'); assert.ok(m.name.includes('Ridge Plow'));
  assert.equal((await fetch(`${s.base}/c/${'z'.repeat(30)}/manifest.webmanifest`)).status, 404);
  for (const [file, type] of [['leaflet.js', /javascript/], ['leaflet.css', /css/], ['portal.js', /javascript/]]) {
    const r = await fetch(`${s.base}/assets/${file}`);
    assert.equal(r.status, 200); assert.match(r.headers.get('content-type'), type);
  }
  assert.equal((await fetch(`${s.base}/assets/..%2Fportal.mjs`)).status, 404);        // only the listed files, no path tricks
  assert.equal((await fetch(`${s.base}/assets/portal.mjs`)).status, 404);
  assert.equal((await fetch(`${s.base}/assets/secret.js`)).status, 404);
});

test('without a property location there is no map', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const html = await (await fetch(`${s.base}/c/${TOKEN}`)).text();
  assert.ok(!html.includes('Where is the truck?')); assert.ok(!html.includes('leaflet.js'));
});

// ---- kind messages for the driver, season-long links, invoice PDFs by email

test('a client can send a kind message to the driver, and the owner sees it as a message, not a request', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish([{ token: TOKEN, label: '14 Elm Ave', status: 'done', canRequest: false }]);         // even after the visit is done
  const post = (fields) => fetch(`${s.base}/c/${TOKEN}/thanks`, { method: 'POST', redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields).toString() });
  const r = await post({ message: 'Thank you for clearing the drive so early! <b>x</b>', from: 'Pat' });
  assert.equal(r.status, 303); assert.equal(r.headers.get('location'), `/c/${TOKEN}?sent=thanks`);
  const page = await (await fetch(`${s.base}/c/${TOKEN}?sent=thanks`)).text();
  assert.ok(page.includes('Message sent')); assert.ok(page.includes('Message to your driver')); assert.ok(page.includes('Sent'));
  assert.ok(!page.includes('<b>x</b>'));                                                               // shown as text
  const polled = await (await s.owner('GET', '/v1/portal/requests')).json();
  assert.equal(polled.requests.length, 1);
  assert.equal(polled.requests[0].kind, 'thanks');
  assert.equal(polled.requests[0].note, 'From Pat: Thank you for clearing the drive so early! <b>x</b>');
  assert.equal((await post({ message: '   ' })).status, 400);
  assert.equal((await post({ message: 'x'.repeat(5000) })).status, 303);
  const long = (await (await s.owner('GET', '/v1/portal/requests')).json()).requests.find((x) => x.note.length > 100 && x.note.length < 300);
  assert.ok(long.note.length <= 200);                                                                   // cut to 200 characters
  assert.equal((await post({ message: 'third' })).status, 303);
  assert.equal((await post({ message: 'fourth' })).status, 429);                                       // three an hour per page
  assert.equal((await fetch(`${s.base}/c/${'z'.repeat(30)}/thanks`, { method: 'POST' })).status, 404);
});

test('a client page link lasts the whole season', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  s.clock.advance(100 * 86_400_000);
  assert.equal((await fetch(`${s.base}/c/${TOKEN}`)).status, 200);                                     // 100 days later
  s.clock.advance(200 * 86_400_000);
  await s.publish([{ token: 'B'.repeat(24), label: 'x', status: 'planned', canRequest: true }]);        // saving purges anything older than the limit
  assert.equal((await fetch(`${s.base}/c/${TOKEN}`)).status, 404);                                     // 300 days with no update
  assert.equal(loadPortalConfig({}).snapshotTtlDays, 240);
});

const PDF = Buffer.from('%PDF-1.4\n1 0 obj\n<< >>\nendobj\n%%EOF\n').toString('base64');
const msg = (extra = {}) => ({ to: 'pat@example.com', subject: 'Invoice INV-7', text: 'Here is your invoice.', ...extra });

test('an invoice PDF can be attached to an email, and only a real PDF of reasonable size', async (t) => {
  const s = await boot(); t.after(s.close);
  const send = (messages) => s.owner('POST', '/v1/send/email', { messages });
  const r = await (await send([msg({ attachments: [{ filename: 'Invoice-INV-7.pdf', content: PDF }] })])).json();
  assert.deepEqual(r.results, [{ index: 0, ok: true }]);
  const sent = s.emailCalls[0].body;
  assert.deepEqual(sent.attachments, [{ filename: 'Invoice-INV-7.pdf', content: PDF }]);
  assert.deepEqual(sent.to, ['pat@example.com']);
  const bad = [
    [{ filename: '../x.pdf', content: PDF }], [{ filename: 'x.exe', content: PDF }], [{ filename: 'x.pdf', content: Buffer.from('MZ not a pdf').toString('base64') }],
    [{ filename: 'x.pdf', content: 'not base64!!' }], [{ filename: 'x.pdf', content: PDF.slice(0, -1) }],
    [{ filename: 'x.pdf', content: 'JVBERi0' + 'A'.repeat(1_600_000) }],
    [], [{ filename: 'a.pdf', content: PDF }, { filename: 'b.pdf', content: PDF }], 'nope',
  ];
  for (const attachments of bad) {
    const out = await (await send([msg({ attachments })])).json();
    assert.deepEqual(out.results, [{ index: 0, ok: false, error: 'invalid_attachment' }], JSON.stringify(attachments).slice(0, 60));
  }
  assert.equal(s.emailCalls.length, 1);                                                                // none of the bad ones were sent
});

test('the email endpoint takes a larger body than the public pages do', async (t) => {
  const s = await boot({ maxEmailBodyBytes: 3_000_000, maxBodyBytes: 500_000 }); t.after(s.close);
  const big = 'JVBERi0' + 'A'.repeat(1_000_000 - 7 - (1_000_000 % 4) + 1 - 1);
  const content = big.slice(0, big.length - (big.length % 4));
  const ok = await s.owner('POST', '/v1/send/email', { messages: [msg({ attachments: [{ filename: 'big.pdf', content }] })] });
  assert.equal(ok.status, 200);
  const publish = await s.owner('PUT', '/v1/portal/snapshot', { company: 'x', storm: { id: 's', name: 'n' }, sites: [], pad: 'x'.repeat(600_000) });
  assert.equal(publish.status, 413);                                                                   // the normal limit still applies elsewhere
});
