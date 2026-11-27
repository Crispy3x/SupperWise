// The website tracker sign-in: last name and house number instead of a property code (lookup.mjs, embed.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { createFullServer } from '../app.mjs';
import { loadConfig } from '../server.mjs';
import { loadPortalConfig } from '../portal.mjs';
import { normalizeName, nameCandidates, houseNumberOf, lookupHash, cleanReviewUrl, LOOKUP_FAIL } from '../lookup.mjs';

const SALT = '0123456789abcdef0123456789abcdef';
// The same vector as PortalLookupTests.swift: sha256("0123456789abcdef0123456789abcdef|oneil|14").
const VECTOR_FULL = '43443a09da5ad7258ff6eea3c740d9ce55bb9f79b573f98a966883a8fa9ef554';
const VECTOR_NAME = '3e000e0bfeec41d7b5bb938ab2d4469bc826ee8fd62d1fb88aa4b7f3563f087b';
const T = { oneil: 'AbCdEfGhIjKlMnOpQrStUv01', garcia: 'ZyXwVuTsRqPoNmLkJiHgFe99', smith1: 'Third3Third3Third3Third3', smith2: 'Fourth4Fourth4Fourth4Fo' };
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const ids = (name, number) => ({ lookup: sha(`${SALT}|${name}|${number}`), lookupName: sha(`${SALT}|${name}`) });

const SITES = [
  { token: T.oneil, label: '14B Elm Ave', status: 'planned', canRequest: true, stopsAhead: 2, ...ids('oneil', '14') },
  { token: T.garcia, label: '9 Oak St', status: 'planned', canRequest: true, ...ids('garcia', '9') },
  { token: T.smith1, label: '22 Pine Rd', status: 'notExpected', canRequest: true, ...ids('smith', '22') },
  { token: T.smith2, label: '5 Birch Ln', status: 'done', canRequest: false, ...ids('smith', '5') },
];

async function boot(env = {}, over = {}) {
  let t = 1_800_000_000_000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const logs = [];
  const pc = { ...loadPortalConfig(env), ownerTokens: ['owner-token'], lookupMinMs: 0, ...over };
  const server = createFullServer({ ...loadConfig({}), tokens: ['owner-token'], googleKey: 'k' }, pc, { portal: { now: clock.now, log: (l) => logs.push(l) } });
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const publish = (sites = SITES, extra = {}) => fetch(`${base}/v1/portal/snapshot`, {
    method: 'PUT', headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ company: 'Ridge Plow', storm: { id: 'storm-1', name: 'Nov 18 storm' }, sites, lookupSalt: SALT, ...extra }),
  });
  const lookup = (lastName, houseNumber) => {
    const form = new URLSearchParams({ lastName });
    if (houseNumber !== undefined) form.set('houseNumber', houseNumber);
    return fetch(`${base}/embed/tracker`, { method: 'POST', body: form, redirect: 'manual', headers: { 'content-type': 'application/x-www-form-urlencoded' } });
  };
  const close = () => { server.closeAllConnections(); server.close(); };
  return { base, publish, lookup, close, clock, logs, server };
}

test('normalizing and hashing match the app: the known vector, apostrophes, accents, hyphens, house numbers', () => {
  assert.equal(lookupHash(SALT, 'oneil', '14').toString('hex'), VECTOR_FULL);
  assert.equal(lookupHash(SALT, 'oneil').toString('hex'), VECTOR_NAME);
  assert.equal(normalizeName("O'Neil"), 'oneil');
  assert.equal(normalizeName('O’NEIL'), 'oneil');
  assert.equal(normalizeName('García'), 'garcia');
  assert.equal(normalizeName('Smith-Jones'), 'smithjones');
  assert.deepEqual(nameCandidates('José García'), ['josegarcia', 'garcia']);
  assert.deepEqual(nameCandidates('  smith '), ['smith']);
  assert.deepEqual(nameCandidates('123 !!'), []);
  assert.equal(houseNumberOf('14B'), '14');
  assert.equal(houseNumberOf(' 14 Elm Ave'), '14');
  assert.equal(houseNumberOf('Elm'), '');
});

test('last name and house number find the property, ignoring case, spaces and apostrophes, and redirect to ?code=', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  for (const [name, num, token] of [["O'Neil", '14', T.oneil], ['  oneil ', '14B', T.oneil], ['O’NEIL', ' 14', T.oneil],
    ['Garcia', '9', T.garcia], ['José García', '9', T.garcia], ['smith', '22', T.smith1]]) {
    const res = await s.lookup(name, num);
    assert.equal(res.status, 303, `${name} ${num}`);
    assert.equal(res.headers.get('location'), `/embed/tracker?code=${token}`);
    assert.ok(!res.headers.get('location').toLowerCase().includes(normalizeName(name)));          // the name never goes into a URL
    assert.match(res.headers.get('content-security-policy'), /frame-ancestors \*/);
  }
  const html = await (await fetch(`${s.base}/embed/tracker?code=${T.oneil}`)).text();
  for (const x of ['<h1 class="biz">Ridge Plow</h1>', '14B Elm Ave', '2 stops before your house.', 'Leave a note for the driver', 'Powered by Ridgeline Ops']) assert.ok(html.includes(x), x);
  assert.ok(html.includes(`href="/c/${T.oneil}#ask" target="_blank" rel="noopener">Request service`));
  assert.ok(!html.includes('9 Oak St'));
});

test('every failure gets the same page and status: wrong number, unknown name, missing fields, garbage', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const answers = [];
  for (const [name, num] of [["O'Neil", '15'], ['Oneill', '14'], ['Nobody', '1'], ['', '14'], ['Oneil', ''], ['Oneil', undefined],
    ['<script>alert(1)</script>', '14'], ['x'.repeat(5000), '9'.repeat(50)], ['Smith', '59']]) {
    const res = await s.lookup(name, num);
    answers.push([res.status, await res.text()]);
  }
  for (const [status, html] of answers) {
    assert.equal(status, 404);
    assert.equal(html, answers[0][1]);
  }
  const page = answers[0][1];
  assert.ok(page.includes("We couldn&#39;t find your service. Check the spelling of your last name and your house number."));
  assert.equal(LOOKUP_FAIL, "We couldn't find your service. Check the spelling of your last name and your house number.");
  for (const x of ['14B Elm Ave', T.oneil, 'oneil', '<script>alert']) assert.ok(!page.includes(x), x);
  // A body that is too large fails the same way.
  const big = await fetch(`${s.base}/embed/tracker`, { method: 'POST', body: 'lastName=' + 'a'.repeat(10_000) });
  assert.equal(big.status, 404);
});

test('PORTAL_LOOKUP=lastname: one match signs in with the last name alone; two matches ask for the house number', async (t) => {
  const s = await boot({ PORTAL_LOOKUP: 'lastname' }); t.after(s.close);
  await s.publish();
  const form = await (await fetch(`${s.base}/embed/tracker`)).text();
  assert.ok(form.includes('name="lastName"') && !form.includes('name="houseNumber"') && form.includes('Use the last name on your account.'));
  let res = await s.lookup('garcia');
  assert.equal(res.status, 303);
  assert.equal(res.headers.get('location'), `/embed/tracker?code=${T.garcia}`);
  res = await s.lookup('Smith');
  assert.equal(res.status, 200);
  const ask = await res.text();
  assert.ok(ask.includes('More than one property matches that name') && ask.includes('name="houseNumber"') && ask.includes('value="Smith"'));
  for (const x of ['22 Pine Rd', '5 Birch Ln', T.smith1, T.smith2]) assert.ok(!ask.includes(x), x);
  res = await s.lookup('Smith', '5');
  assert.equal(res.headers.get('location'), `/embed/tracker?code=${T.smith2}`);
  assert.equal((await s.lookup('Smith', '7')).status, 404);
  assert.equal((await s.lookup('Jones')).status, 404);
  // The default mode never signs in with a last name alone, even when it is unique.
  const strict = await boot(); t.after(strict.close);
  await strict.publish();
  assert.equal((await strict.lookup('garcia')).status, 404);
});

test('lookups are rate limited per connection and for the whole server, and the limit lifts after the window', async (t) => {
  const s = await boot({}, { lookupPerIp: 3 }); t.after(s.close);
  await s.publish();
  for (let i = 0; i < 3; i++) assert.equal((await s.lookup('Nobody', String(i))).status, 404);
  const limited = await s.lookup("O'Neil", '14');                  // even the right answer is refused once over the limit
  assert.equal(limited.status, 429);
  assert.ok((await limited.text()).includes('Too many tries'));
  s.clock.advance(11 * 60_000);
  assert.equal((await s.lookup("O'Neil", '14')).status, 303);

  const g = await boot({ PORTAL_LOOKUP_GLOBAL: '2', PORTAL_LOOKUP_PER_IP: '50' }); t.after(g.close);
  await g.publish();
  await g.lookup('a', '1'); await g.lookup('b', '2');
  assert.equal((await g.lookup("O'Neil", '14')).status, 429);
});

test('names and house numbers typed are never stored or logged; only hashes are kept', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  await s.lookup("O'Neil", '14'); await s.lookup('Zebrowski', '77'); await s.lookup('Smith', '5');
  const state = JSON.stringify(s.server.portal._state());
  for (const x of ['oneil', "O'Neil", 'zebrowski', 'Zebrowski', 'smith', 'garcia']) assert.ok(!state.toLowerCase().includes(x.toLowerCase()), x);
  assert.ok(state.includes(SITES[0].lookup) && state.includes(SALT));
  for (const l of s.logs) assert.ok(!/oneil|zebrowski|smith/i.test(l), l);
});

test('hashes are kept only with a valid salt and in the right shape; a stale page from an earlier publish is not found', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish(SITES, { lookupSalt: 'not-a-salt' });
  assert.equal((await s.lookup("O'Neil", '14')).status, 404);
  await s.publish([{ ...SITES[0], lookup: 'ABC' }, SITES[1]]);
  assert.equal((await s.lookup("O'Neil", '14')).status, 404);
  assert.equal((await s.lookup('Garcia', '9')).status, 303);
  // The next publish leaves Garcia out (client deleted or asked to stop): the old page is no longer found by name.
  await s.publish([SITES[0]]);
  assert.equal((await s.lookup('Garcia', '9')).status, 404);
  assert.equal((await s.lookup("O'Neil", '14')).status, 303);
  assert.equal((await fetch(`${s.base}/embed/tracker?code=${T.garcia}`)).status, 200);            // a season link still works
});

test('the review button shows only with a valid review link, and opens in a new tab', async (t) => {
  const s = await boot(); t.after(s.close);
  const view = async () => (await fetch(`${s.base}/embed/tracker?code=${T.oneil}`)).text();
  await s.publish(SITES, { reviewURL: 'https://g.page/r/ridgeplow/review' });
  const html = await view();
  assert.ok(html.includes('href="https://g.page/r/ridgeplow/review" target="_blank" rel="noopener noreferrer">Leave us a review'));
  for (const bad of ['http://g.page/r/x', 'https://evil.example.com/g.page', 'javascript:alert(1)', 'https://user:pw@yelp.com/x', 'https://yelp.com/x#y', 'https://g.page.evil.com/x', 42]) {
    await s.publish(SITES, { reviewURL: bad });
    assert.ok(!(await view()).includes('Leave us a review'), String(bad));
  }
  await s.publish(SITES);
  assert.ok(!(await view()).includes('Leave us a review'));
  assert.equal(cleanReviewUrl('https://www.yelp.com/biz/ridge-plow'), 'https://www.yelp.com/biz/ridge-plow');
  assert.equal(cleanReviewUrl('https://maps.app.goo.gl/abc'), 'https://maps.app.goo.gl/abc');
});

test('the note for the driver works from inside the frame and comes back to the tracker', async (t) => {
  const s = await boot(); t.after(s.close);
  await s.publish();
  const html = await (await fetch(`${s.base}/embed/tracker?code=${T.oneil}`)).text();
  assert.ok(html.includes(`<form method="post" action="/c/${T.oneil}/thanks"><input type="hidden" name="back" value="embed">`));
  const note = (message) => fetch(`${s.base}/c/${T.oneil}/thanks`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ message, from: 'Ann', back: 'embed' }) });
  let res = await note('Thanks for the early start!');
  assert.equal(res.status, 303);
  assert.equal(res.headers.get('location'), `/embed/tracker?code=${T.oneil}&sent=thanks`);
  assert.ok((await (await fetch(s.base + res.headers.get('location'))).text()).includes('Note sent. Thank you! Your driver will see it.'));
  const reqs = await (await fetch(`${s.base}/v1/portal/requests`, { headers: { authorization: 'Bearer owner-token' } })).json();
  assert.equal(reqs.requests[0].kind, 'thanks');
  assert.equal(reqs.requests[0].note, 'From Ann: Thanks for the early start!');
  assert.equal((await note('   ')).headers.get('location'), `/embed/tracker?code=${T.oneil}&sent=empty`);
  await note('two'); await note('three');
  assert.equal((await note('four')).headers.get('location'), `/embed/tracker?code=${T.oneil}&sent=limit`);
  assert.ok((await (await fetch(`${s.base}/embed/tracker?code=${T.oneil}&sent=limit`)).text()).includes('You have sent a few notes already'));
  // The client page's own form still goes back to the client page.
  const own = await fetch(`${s.base}/c/${T.garcia}/thanks`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ message: 'hi' }) });
  assert.equal(own.headers.get('location'), `/c/${T.garcia}?sent=thanks`);
});
