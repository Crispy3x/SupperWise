// Ridgeline Ops client portal: the private page each client opens, the request inbox for the owner, and email sending.
// Zero dependencies. Stores no phone numbers or email addresses: only a page token, the address label, a status and requests.
import crypto from 'node:crypto';
import fs from 'node:fs';

const TOKEN_RE = /^[A-Za-z0-9_-]{22,64}$/;
const STATUSES = new Set(['planned', 'done', 'skipped', 'notExpected']);
const KINDS = new Set(['service', 'urgent', 'skip']);
// The crew's own Venmo, PayPal and Cash App links. Tip and coffee buttons lead to a page that lists them; nothing is paid through this server.
const PAY_APPS = [['venmoURL', 'venmoUrl', 'venmo', 'Venmo'], ['paypalURL', 'paypalUrl', 'paypal', 'PayPal'], ['cashappURL', 'cashAppUrl', 'cashapp', 'Cash App']];
const PAY_REASONS = { tip: ['Tip the crew', '\u{1F4B5}', 'Thank the crew for clearing your property.'], coffee: ['Send a coffee', '\u2615', 'Buy the crew a coffee on a cold morning.'] };
const MAX_THANKS_CHARS = 200;
const REASONS = new Set(['leavingSoon', 'medical', 'visitorOrDelivery', 'other']);
const KIND_TEXT = { thanks: 'Message to your driver', service: 'Please service my property', urgent: 'I need to get out soon (urgent)', skip: 'Skip my property this storm' };
const REASON_TEXT = { leavingSoon: 'I need to leave soon', medical: 'Medical or care visit', visitorOrDelivery: 'Visitor or delivery coming', other: 'Other (explain below)' };
const STATUS_TEXT = { planned: 'Planned for this storm', done: 'Done', skipped: 'Not serviced this visit', notExpected: 'No service expected yet' };
const BILL_STATUSES = new Set(['Paid', 'Due', 'Overdue']);
// Same list as the app's PayLink.allowedHosts. The server never trusts the app: https only, known payment sites only.
const PAY_HOSTS = ['stripe.com', 'square.link', 'square.site', 'squareup.com', 'paypal.com', 'paypal.me', 'venmo.com', 'cash.app', 'intuit.com', 'quickbooks.com', 'waveapps.com', 'zellepay.com'];
export function cleanPayUrl(v) {
  if (typeof v !== 'string' || v.length > 500 || /\s/.test(v)) return '';
  let u; try { u = new URL(v); } catch { return ''; }
  if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash) return '';
  const host = u.hostname.toLowerCase();
  return PAY_HOSTS.some((h) => host === h || host.endsWith('.' + h)) ? u.href : '';
}
const MAX_BILLS = 30;
const DAY = 86_400_000;

export function loadPortalConfig(env = process.env) {
  const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
  return {
    ownerTokens: (env.API_TOKENS || '').split(',').map((t) => t.trim()).filter(Boolean),
    dataFile: env.PORTAL_DATA_FILE || '',
    resendKey: env.RESEND_API_KEY || '',
    emailUrl: env.EMAIL_API_URL || 'https://api.resend.com/emails',
    fromEmail: env.FROM_EMAIL || '',
    replyTo: env.REPLY_TO_EMAIL || '',
    emailDailyCap: num(env.EMAIL_DAILY_CAP, 300),
    maxSites: num(env.PORTAL_MAX_SITES, 500),
    ipLimitPerMinute: num(env.PORTAL_IP_LIMIT_PER_MIN, 120),
    requestsPerTokenPerHour: num(env.PORTAL_REQUESTS_PER_HOUR, 3),
    maxPendingPerToken: num(env.PORTAL_MAX_PENDING, 5),
    snapshotTtlDays: num(env.PORTAL_SNAPSHOT_TTL_DAYS, 240),        // a client's link lasts the whole winter
    requestTtlDays: num(env.PORTAL_REQUEST_TTL_DAYS, 30),
    maxBodyBytes: num(env.PORTAL_MAX_BODY_BYTES, 500_000),
    maxEmailBodyBytes: num(env.PORTAL_MAX_EMAIL_BODY_BYTES, 3_000_000),     // owner only: an invoice PDF is attached
    trustProxy: env.TRUST_PROXY === '1',
  };
}

const digest = (s) => crypto.createHash('sha256').update(s).digest();

/** Text from outside is shown only after this: control characters removed, length limited. */
export function cleanText(v, max) {
  if (typeof v !== 'string') return '';
  return v.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

export function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

export function isValidEmail(t) {
  if (typeof t !== 'string' || t.length > 254 || t !== t.trim() || /[\s,;<>]/.test(t)) return false;
  const parts = t.split('@');
  if (parts.length !== 2 || !parts[0] || parts[0].length > 64) return false;
  const d = parts[1];
  return d.includes('.') && !d.startsWith('.') && !d.endsWith('.') && !d.includes('..');
}

const ASSET_TYPES = { 'leaflet.js': 'text/javascript; charset=utf-8', 'leaflet.css': 'text/css; charset=utf-8', 'portal.js': 'text/javascript; charset=utf-8' };
const TRUCK_FRESH_MS = 10 * 60_000;       // a truck position older than this is not shown
const MAX_TRUCKS = 10;

const SECURITY_HEADERS = {
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',            // the page address contains the token: never pass it on
  'X-Robots-Tag': 'noindex',
  // Scripts only from this server. Map tiles are the one outside request (OpenStreetMap), and only images.
  'Content-Security-Policy': "default-src 'none'; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src https://tile.openstreetmap.org data:; connect-src 'self'; manifest-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
};

export function createPortal(config, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const now = deps.now ?? (() => Date.now());
  const log = deps.log ?? ((l) => console.log(l));
  const ownerDigests = config.ownerTokens.map(digest);
  const ipHits = new Map();
  const emailDaily = new Map();
  let state = { snapshots: {}, requests: [] };
  // Truck positions are short-lived, so they live in memory only and are never saved to disk.
  const trucks = new Map();            // label -> { label, latitude, longitude, updatedAt }
  const assets = new Map();
  for (const [name, type] of Object.entries(ASSET_TYPES)) {
    try { assets.set(name, { type, body: fs.readFileSync(new URL(`./assets/${name}`, import.meta.url)) }); } catch { /* the page then simply has no map */ }
  }

  // ---- storage
  function load() {
    if (!config.dataFile || !fs.existsSync(config.dataFile)) return;
    try {
      const parsed = JSON.parse(fs.readFileSync(config.dataFile, 'utf8'));
      if (parsed && typeof parsed.snapshots === 'object' && Array.isArray(parsed.requests)) state = parsed;
      else throw new Error('bad shape');
    } catch {
      // Keep the unreadable file for recovery instead of overwriting it.
      try { fs.renameSync(config.dataFile, `${config.dataFile}.unreadable-${now()}`); } catch { /* ignore */ }
      log('portal data file unreadable: set aside, starting empty');
    }
  }
  function purge() {
    const t = now();
    for (const [token, s] of Object.entries(state.snapshots)) if (t - s.updatedAt > config.snapshotTtlDays * DAY) delete state.snapshots[token];
    state.requests = state.requests.filter((r) => t - Date.parse(r.createdAt) <= config.requestTtlDays * DAY);
  }
  function save() {
    purge();
    if (!config.dataFile) return;
    const tmp = `${config.dataFile}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(state));
    fs.renameSync(tmp, config.dataFile);
  }
  load();
  purge();

  // ---- helpers
  const sendJson = (res, status, obj) => {
    const body = JSON.stringify(obj);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store' });
    res.end(body);
  };
  const sendHtml = (res, status, html, extra = {}) => {
    res.writeHead(status, { 'content-type': 'text/html; charset=utf-8', 'content-length': Buffer.byteLength(html), ...SECURITY_HEADERS, ...extra });
    res.end(html);
  };
  const isOwner = (req) => {
    const h = req.headers.authorization || '';
    if (!h.startsWith('Bearer ')) return false;
    const d = digest(h.slice(7));
    let ok = false;
    for (const t of ownerDigests) if (crypto.timingSafeEqual(t, d)) ok = true;
    return ok;
  };
  const readBody = (req, limit = config.maxBodyBytes) => new Promise((resolve, reject) => {
    let size = 0; let tooLarge = false; const chunks = [];
    req.on('data', (c) => {
      if (tooLarge) return;
      size += c.length;
      if (size > limit) { tooLarge = true; reject(Object.assign(new Error('too large'), { status: 413 })); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
  const clientIp = (req) => {
    if (config.trustProxy) { const x = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim(); if (x) return x; }
    return req.socket.remoteAddress || 'unknown';
  };
  const ipAllowed = (req) => {
    const t = now(); const ip = clientIp(req);
    const recent = (ipHits.get(ip) ?? []).filter((x) => t - x < 60_000);
    if (recent.length >= config.ipLimitPerMinute) return false;
    recent.push(t); ipHits.set(ip, recent);
    return true;
  };
  async function jsonBody(req, res, limit) {
    try { return JSON.parse(await readBody(req, limit)); }
    catch (e) {
      if (e.status === 413) { res.on('finish', () => req.destroy()); sendJson(res, 413, { error: 'Request too large' }); }
      else sendJson(res, 400, { error: 'Body must be JSON' });
      return undefined;
    }
  }

  // ---- the client page
  function page(title, inner, extra = {}) {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><meta name="theme-color" content="#0d2540"><meta name="apple-mobile-web-app-capable" content="yes"><title>${escapeHtml(title)}</title>${extra.head || ''}<style>
body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;background:#f4f6f9;color:#14202e}main{max-width:34rem;margin:0 auto;padding:1rem}
.card{background:#fff;border-radius:12px;padding:1rem;margin:0 0 .8rem}h1{font-size:1.3rem;margin:.2rem 0 .6rem;color:#0d2540}h2{font-size:1rem;margin:0 0 .5rem}
.status{display:inline-block;padding:.25rem .6rem;border-radius:8px;background:#eaf3fc;color:#1d5fb4;font-weight:600}.done{background:#e3f4ea;color:#1f7a45}.skipped{background:#fde8d2;color:#b8610f}
label{display:block;margin:.4rem 0}textarea,select{width:100%;font:inherit;padding:.4rem;box-sizing:border-box}button{font:inherit;padding:.6rem 1rem;border:0;border-radius:8px;background:#2f7de1;color:#fff;margin-top:.6rem}
.small{font-size:.85rem;color:#5b6b7e}table{width:100%;border-collapse:collapse}td{padding:.35rem 0;border-top:1px solid #e3e9f0;vertical-align:top}td.r{text-align:right}
.pill{font-size:.8rem;font-weight:600;padding:.1rem .45rem;border-radius:6px;background:#eaf3fc;color:#1d5fb4}.pill.paid{background:#e3f4ea;color:#1f7a45}.pill.overdue{background:#fde8d2;color:#b8610f}.paybtn{display:inline-block;margin-top:.35rem;padding:.35rem .8rem;border-radius:8px;background:#1d5fb4;color:#fff;font-weight:600;text-decoration:none}.btn{display:inline-block;margin:.2rem .4rem 0 0;padding:.6rem 1.1rem;border-radius:999px;background:#2f7de1;color:#fff;font-weight:600;text-decoration:none}.btn.alt{background:#eaf3fc;color:#1d5fb4}.tipbtn{display:inline-block;margin:.2rem .4rem 0 0;padding:.5rem .9rem;border-radius:999px;background:#fff3d6;color:#7a4b00;font-weight:600;text-decoration:none;border:1px solid #f0d9a0}#map{height:260px;border-radius:10px}.pin-site{display:block;width:18px;height:18px;border-radius:50%;background:#2f7de1;border:3px solid #fff;box-shadow:0 0 0 2px #2f7de1}.pin-truck{display:block;font-size:22px;line-height:26px;text-align:center}</style></head><body${extra.bodyAttrs || ''}><main>${inner}</main>${extra.tail || ''}</body></html>`;
  }
  const notFound = (res) => sendHtml(res, 404, page('Page not available', '<div class="card"><h1>This page is not available</h1><p>The link may be old or mistyped. Please contact your snow service provider.</p></div>'));

  // ---- map, weather, tips: what the client page adds on top of the status
  const round = (n, d) => Math.round(n * 10 ** d) / 10 ** d;
  const validCoord = (c) => c && typeof c === 'object' && Number.isFinite(c.latitude) && Number.isFinite(c.longitude)
    && Math.abs(c.latitude) <= 90 && Math.abs(c.longitude) <= 180 && !(c.latitude === 0 && c.longitude === 0);
  const cleanSite = (c) => (validCoord(c) ? { latitude: round(c.latitude, 3), longitude: round(c.longitude, 3) } : null);   // about 100 m: the property, not the doorstep
  const cleanWeather = (w) => (w && typeof w === 'object' ? { summary: cleanText(w.summary, 160), alerts: (Array.isArray(w.alerts) ? w.alerts : []).slice(0, 3).map((a) => cleanText(a, 120)).filter(Boolean) } : null);

  /** What the page and the live updates show. Trucks appear only for a property that is waiting for service, and only while the position is fresh. */
  function liveView(token) {
    const s = state.snapshots[token];
    const t = now();
    const live = [...trucks.values()].filter((x) => t - x.updatedAt <= TRUCK_FRESH_MS);
    return {
      status: s.status, statusText: STATUS_TEXT[s.status], eta: s.eta || '', stopsAhead: Number.isInteger(s.stopsAhead) ? s.stopsAhead : null,
      site: s.siteLocation || null,
      trucks: s.status === 'planned' ? live.map((x) => ({ label: x.label, latitude: x.latitude, longitude: x.longitude })) : [],
      weather: s.weather || null, updatedAt: s.updatedAt,
    };
  }
  const jsonForScript = (o) => JSON.stringify(o).replace(/</g, '\\u003c').replace(/\u2028|\u2029/g, ' ');

  function renderClientPage(token, sentFlag) {
    const s = state.snapshots[token];
    const mine = state.requests.filter((r) => r.token === token && r.stormId === s.stormId).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 5);
    const statusClass = s.status === 'done' ? 'done' : s.status === 'skipped' ? 'skipped' : '';
    let html = `<div class="card"><p class="small">${escapeHtml(s.company)}</p><h1>${escapeHtml(s.label)}</h1>`;
    if (s.stormName) html += `<p>${escapeHtml(s.stormName)}${s.expected ? ': ' + escapeHtml(s.expected) : ''}</p>`;
    html += `<p><span class="status ${statusClass}" id="status">${escapeHtml(STATUS_TEXT[s.status])}</span></p>`;
    if (s.detail) html += `<p>${escapeHtml(s.detail)}</p>`;
    html += `<p id="eta"${s.eta ? '' : ' style="display:none"'}>${s.eta ? 'Estimated arrival: ' + escapeHtml(s.eta) : ''}</p><p class="small" id="ahead"></p>`;
    html += `<p>${s.canRequest ? '<a class="btn" href="#ask">Request service</a>' : ''}<a class="btn alt" href="#thanks">Say thanks</a></p>`;
    if (s.summary) html += `<p class="small">${escapeHtml(s.summary)}</p>`;
    html += `<p class="small">Updated ${escapeHtml(new Date(s.updatedAt).toUTCString())}. Forecasts can change.</p></div>`;
    const view = liveView(token);
    if (view.site && assets.has('leaflet.js')) {
      html += '<div class="card"><h2>Where is the truck?</h2><div id="map" role="img" aria-label="Map showing your property and the truck"></div><p class="small" id="mapnote"></p></div>';
    }
    if (s.weather && (s.weather.summary || s.weather.alerts.length)) {
      html += `<div class="card"><h2>Weather</h2><p id="wxsummary">${escapeHtml(s.weather.summary)}</p><p class="small" id="wxalerts">${escapeHtml(s.weather.alerts.join(' · '))}</p><p class="small">From the National Weather Service. Forecasts can change.</p></div>`;
    }
    html += `<div class="card" id="thanks"><h2>Say thanks</h2>`;
    if (s.payApps && s.payApps.length) {
      html += '<p class="small">Optional. You choose Venmo, PayPal or Cash App on the next page. The money goes straight to the crew.</p><p>';
      for (const [key, [label, emoji]] of Object.entries(PAY_REASONS)) html += `<a class="tipbtn" href="/c/${escapeHtml(token)}/pay?for=${key}">${emoji} ${escapeHtml(label)}</a>`;
      html += '</p>';
    }
    html += `<form method="post" action="/c/${escapeHtml(token)}/thanks"><label>Send a kind message to your driver
<textarea name="message" maxlength="${MAX_THANKS_CHARS}" rows="3" placeholder="Thank you for clearing the drive so early!"></textarea></label>
<label>Your first name (optional) <input name="from" maxlength="40" style="width:100%;font:inherit;padding:.4rem;box-sizing:border-box"></label>
<button type="submit">Send message</button></form></div>`;
    if (s.bills && s.bills.length) {
      html += '<div class="card"><h2>Your bills this winter</h2><table>';
      for (const b of s.bills) {
        const cls = b.status === 'Paid' ? 'paid' : b.status === 'Overdue' ? 'overdue' : '';
        const pay = b.payUrl ? `<br><a class="paybtn" href="${escapeHtml(b.payUrl)}" rel="noopener noreferrer">Pay now</a>` : '';
        html += `<tr><td>${escapeHtml(b.number)}<br><span class="small">${escapeHtml(b.label)}${b.due ? ' · ' + escapeHtml(b.due) : ''}</span></td><td class="r">${b.total ? escapeHtml(b.total) + '<br>' : ''}<span class="pill ${cls}">${escapeHtml(b.status)}</span>${pay}</td></tr>`;
      }
      html += '</table><p class="small">Paying goes through your snow service payment page. We never see your card.</p></div>';
    }
    if (sentFlag === 'thanks') html += '<div class="card"><p><strong>Message sent.</strong> Thank you! Your driver will see it.</p></div>';
    else if (sentFlag) html += '<div class="card"><p><strong>Request sent.</strong> Your snow service will review it. This page shows their answer.</p></div>';
    if (mine.length) {
      html += '<div class="card"><h2>Your requests</h2>';
      for (const r of mine) {
        const what = KIND_TEXT[r.kind] + (r.reason ? ` (${REASON_TEXT[r.reason]})` : '');
        const answer = r.kind === 'thanks' ? (r.status === 'pending' ? 'Sent' : 'Read by the crew')
          : r.status === 'pending' ? 'Waiting for an answer' : r.status === 'accepted' ? 'Accepted' : 'Declined';
        html += `<p>${escapeHtml(what)}<br><span class="small">${answer}${r.message ? ': ' + escapeHtml(r.message) : ''}</span></p>`;
      }
      html += '</div>';
    }
    if (s.canRequest) {
      html += `<form class="card" id="ask" method="post" action="/c/${escapeHtml(token)}/request"><h2>Ask for something</h2>
<label><input type="radio" name="kind" value="service" checked> ${KIND_TEXT.service}</label>
<label><input type="radio" name="kind" value="urgent"> ${KIND_TEXT.urgent}</label>
<label><input type="radio" name="kind" value="skip"> ${KIND_TEXT.skip}</label>
<label>If urgent, why? <select name="reason"><option value="">Choose</option>${[...REASONS].map((r) => `<option value="${r}">${escapeHtml(REASON_TEXT[r])}</option>`).join('')}</select></label>
<label>Note (optional) <textarea name="note" maxlength="500" rows="3"></textarea></label>
<button type="submit">Send request</button>
<p class="small">Your snow service decides whether and when to come. Sending a request does not guarantee service.</p></form>`;
    }
    const mapOn = Boolean(view.site && assets.has('leaflet.js'));
    return page(`${s.label}: snow update`, html, {
      head: `<link rel="manifest" href="/c/${escapeHtml(token)}/manifest.webmanifest">${mapOn ? '<link rel="stylesheet" href="/assets/leaflet.css">' : ''}`,
      bodyAttrs: ` data-token="${escapeHtml(token)}"`,
      tail: `<script type="application/json" id="live">${jsonForScript(view)}</script>${mapOn ? '<script src="/assets/leaflet.js"></script>' : ''}<script src="/assets/portal.js"></script>`,
    });
  }

  function renderPayPage(token, reason) {
    const s = state.snapshots[token];
    const [label, emoji, line] = PAY_REASONS[reason] || PAY_REASONS.tip;
    let inner = `<div class="card"><h1>${emoji} ${escapeHtml(label)}</h1><p>${escapeHtml(line)} Pick the app you use. It opens the crew's own page there, and you choose the amount.</p><p>`;
    for (const a of s.payApps || []) inner += `<a class="btn payapp" href="${escapeHtml(a.url)}" rel="noopener noreferrer">${escapeHtml(a.label)}</a>`;
    inner += `</p><p class="small">Totally optional. Nothing is charged here, and ${escapeHtml(s.company || 'your snow service')} is not told who tips.</p><p><a href="/c/${escapeHtml(token)}">Back to my page</a></p></div>`;
    return page(`${label}`, inner, { head: '' });
  }

  // ---- owner API
  /** A truck's position, sent every half minute while its crew shares location. Each truck is added or updated by its label, so
   *  several trucks can share at once; `remove` takes a truck off the map when its crew stops. Kept in memory only. */
  async function putTrucks(req, res) {
    const body = await jsonBody(req, res); if (body === undefined) return;
    if (!body || !Array.isArray(body.trucks) || body.trucks.length > MAX_TRUCKS || (body.remove !== undefined && (!Array.isArray(body.remove) || body.remove.length > MAX_TRUCKS))) {
      return sendJson(res, 400, { error: `trucks and remove must be lists of at most ${MAX_TRUCKS}` });
    }
    const incoming = [];
    for (const x of body.trucks) {
      if (!validCoord(x)) return sendJson(res, 400, { error: 'each truck needs a valid latitude and longitude' });
      incoming.push({ label: cleanText(x.label, 24) || 'Truck', latitude: round(x.latitude, 4), longitude: round(x.longitude, 4), updatedAt: now() });
    }
    for (const label of body.remove || []) trucks.delete(cleanText(label, 24));
    for (const x of incoming) trucks.set(x.label, x);
    if (trucks.size > MAX_TRUCKS) {                          // never grow without bound: drop the stalest
      const stale = [...trucks.values()].sort((a, b) => a.updatedAt - b.updatedAt).slice(0, trucks.size - MAX_TRUCKS);
      for (const x of stale) trucks.delete(x.label);
    }
    sendJson(res, 200, { stored: incoming.length });
  }

  async function putSnapshot(req, res) {
    const body = await jsonBody(req, res); if (body === undefined) return;
    if (!body || typeof body !== 'object' || !body.storm || !Array.isArray(body.sites)) return sendJson(res, 400, { error: 'company, storm and sites are required' });
    if (body.sites.length > config.maxSites) return sendJson(res, 400, { error: `at most ${config.maxSites} sites` });
    const company = cleanText(body.company, 80);
    const stormId = cleanText(body.storm.id, 64);
    if (!stormId) return sendJson(res, 400, { error: 'storm.id is required' });
    const stormName = cleanText(body.storm.name, 80); const expected = cleanText(body.storm.expected, 120);
    const weather = cleanWeather(body.weather);
    const payApps = PAY_APPS.map(([wire, alt, key, label]) => ({ key, label, url: cleanPayUrl(body.tips?.[wire] ?? body.tips?.[alt]) })).filter((g) => g.url);
    const next = [];
    for (const s of body.sites) {
      if (!s || !TOKEN_RE.test(String(s.token)) || !STATUSES.has(s.status)) return sendJson(res, 400, { error: 'each site needs a valid token and status' });
      let bills = [];
      if (s.bills !== undefined) {
        if (!Array.isArray(s.bills) || s.bills.length > MAX_BILLS) return sendJson(res, 400, { error: `bills must be a list of at most ${MAX_BILLS}` });
        for (const b of s.bills) {
          if (!b || !BILL_STATUSES.has(b.status)) return sendJson(res, 400, { error: 'each bill needs a status of Paid, Due or Overdue' });
          bills.push({ number: cleanText(b.number, 24), label: cleanText(b.label, 120), total: cleanText(b.total, 24), status: b.status, due: cleanText(b.due, 40),
            payUrl: b.status === 'Paid' ? '' : cleanPayUrl(b.payURL ?? b.payUrl) });
        }
      }
      next.push([s.token, { company, stormId, stormName, expected, label: cleanText(s.label, 120) || 'Your property', status: s.status,
        detail: cleanText(s.detail, 200), eta: cleanText(s.eta, 120), summary: cleanText(s.summary, 160), bills,
        siteLocation: cleanSite(s.siteLocation), stopsAhead: Number.isInteger(s.stopsAhead) && s.stopsAhead >= 0 && s.stopsAhead <= 500 ? s.stopsAhead : null,
        weather, payApps,
        canRequest: s.canRequest === true, updatedAt: now() }]);
    }
    for (const [token, snap] of next) state.snapshots[token] = snap;
    save();
    sendJson(res, 200, { stored: next.length });
  }

  function getRequests(req, res, url) {
    const since = url.searchParams.get('since');
    let sinceMs = 0;
    if (since) { sinceMs = Date.parse(since); if (!Number.isFinite(sinceMs)) return sendJson(res, 400, { error: 'since must be an ISO date' }); }
    const out = state.requests.filter((r) => Date.parse(r.createdAt) > sinceMs).sort((a, b) => a.createdAt.localeCompare(b.createdAt)).slice(0, 200)
      .map((r) => ({ id: r.id, token: r.token, kind: r.kind, reason: r.reason || null, note: r.note, createdAt: r.createdAt, stormId: r.stormId }));
    sendJson(res, 200, { requests: out });
  }

  async function postDecision(req, res) {
    const body = await jsonBody(req, res); if (body === undefined) return;
    if (!body || !['accepted', 'declined'].includes(body.status) || typeof body.id !== 'string') return sendJson(res, 400, { error: 'id and status (accepted or declined) are required' });
    const r = state.requests.find((x) => x.id === body.id);
    if (!r) return sendJson(res, 404, { error: 'No such request' });
    if (r.status !== 'pending') return sendJson(res, 409, { error: 'Already decided' });
    r.status = body.status; r.message = cleanText(body.message, 300); r.decidedAt = new Date(now()).toISOString();
    save();
    sendJson(res, 200, { ok: true });
  }

  // ---- email
  /** One PDF at most, a plain file name, real base64 that starts like a PDF, and not too big. Anything else is refused. */
  function cleanAttachments(list) {
    if (!Array.isArray(list) || list.length !== 1) return null;
    const a = list[0];
    if (!a || typeof a.filename !== 'string' || !/^[A-Za-z0-9._-]{1,60}\.pdf$/.test(a.filename)) return null;
    const content = a.content;
    if (typeof content !== 'string' || content.length > 1_500_000 || content.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(content) || !content.startsWith('JVBERi0')) return null;
    return [{ filename: a.filename, content }];
  }

  async function sendEmail(req, res) {
    if (!config.resendKey || !config.fromEmail) return sendJson(res, 503, { error: 'Email is not configured' });
    const body = await jsonBody(req, res, config.maxEmailBodyBytes); if (body === undefined) return;
    if (!body || !Array.isArray(body.messages) || body.messages.length === 0 || body.messages.length > 100) return sendJson(res, 400, { error: 'messages must be a list of 1 to 100' });
    const day = new Date(now()).toISOString().slice(0, 10);
    const used = emailDaily.get(day) ?? 0;
    if (used + body.messages.length > config.emailDailyCap) return sendJson(res, 429, { error: 'Daily email limit reached' });
    const results = [];
    let sent = 0;
    for (let i = 0; i < body.messages.length; i++) {
      const m = body.messages[i];
      const subject = cleanText(m && m.subject, 150); const text = typeof (m && m.text) === 'string' ? m.text.slice(0, 5000) : '';
      if (!m || !isValidEmail(m.to) || !subject || !text) { results.push({ index: i, ok: false, error: 'invalid_message' }); continue; }
      try {
        const payload = { from: config.fromEmail, to: [m.to], subject, text };
        if (m.attachments !== undefined) {
          const att = cleanAttachments(m.attachments);
          if (!att) { results.push({ index: i, ok: false, error: 'invalid_attachment' }); continue; }
          payload.attachments = att;
        }
        if (config.replyTo) payload.reply_to = config.replyTo;
        const r = await fetchImpl(config.emailUrl, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${config.resendKey}` }, body: JSON.stringify(payload) });
        if (r.ok) { sent++; results.push({ index: i, ok: true }); } else results.push({ index: i, ok: false, error: 'provider_rejected' });
      } catch { results.push({ index: i, ok: false, error: 'provider_unreachable' }); }
    }
    emailDaily.set(day, used + sent);
    log(`email batch: ${sent} of ${body.messages.length} sent`);          // counts only: never addresses or text
    sendJson(res, 200, { results });
  }

  // ---- a kind message for the driver
  async function postThanks(req, res, token) {
    let form;
    try { form = new URLSearchParams(await readBody(req)); }
    catch (e) { if (e.status === 413) { res.on('finish', () => req.destroy()); return sendHtml(res, 413, page('Too large', '<div class="card"><p>That message was too large.</p></div>'), { connection: 'close' }); } return sendHtml(res, 400, page('Error', '<div class="card"><p>Something went wrong.</p></div>')); }
    const s = state.snapshots[token];
    const message = cleanText(form.get('message'), MAX_THANKS_CHARS);
    if (!message) return sendHtml(res, 400, page('Check your message', `<div class="card"><p>Please write a message first.</p><p><a href="/c/${escapeHtml(token)}#thanks">Go back</a></p></div>`));
    const from = cleanText(form.get('from'), 40);
    const t = now();
    const mine = state.requests.filter((r) => r.token === token && r.kind === 'thanks');
    if (mine.filter((r) => t - Date.parse(r.createdAt) < 3_600_000).length >= config.requestsPerTokenPerHour) return sendHtml(res, 429, page('Too many messages', '<div class="card"><p>You have sent a few messages already. Thank you! Please try again later.</p></div>'));
    state.requests.push({ id: crypto.randomBytes(12).toString('hex'), token, kind: 'thanks', reason: '', note: from ? `From ${from}: ${message}` : message,
      createdAt: new Date(t).toISOString(), stormId: s.stormId, status: 'pending', message: '' });
    save();
    res.writeHead(303, { location: `/c/${token}?sent=thanks`, ...SECURITY_HEADERS });
    res.end();
  }

  // ---- client request form
  async function postClientRequest(req, res, token) {
    let form;
    try { form = new URLSearchParams(await readBody(req)); }
    catch (e) { if (e.status === 413) { res.on('finish', () => req.destroy()); return sendHtml(res, 413, page('Too large', '<div class="card"><p>That request was too large.</p></div>'), { connection: 'close' }); } return sendHtml(res, 400, page('Error', '<div class="card"><p>Something went wrong.</p></div>')); }
    const s = state.snapshots[token];
    const kind = String(form.get('kind') || ''); const reason = String(form.get('reason') || '');
    const bad = (msg) => sendHtml(res, 400, page('Check your request', `<div class="card"><p>${escapeHtml(msg)}</p><p><a href="/c/${escapeHtml(token)}">Go back</a></p></div>`));
    if (!s.canRequest) return sendHtml(res, 403, page('Not available', '<div class="card"><p>Requests are not available for this property right now.</p></div>'));
    if (!KINDS.has(kind)) return bad('Please choose what you would like to ask for.');
    if (kind === 'urgent' && !REASONS.has(reason)) return bad('For an urgent request, please choose a reason.');
    const t = now();
    const mine = state.requests.filter((r) => r.token === token);
    if (mine.filter((r) => t - Date.parse(r.createdAt) < 3_600_000).length >= config.requestsPerTokenPerHour) return sendHtml(res, 429, page('Too many requests', '<div class="card"><p>You have already sent several requests. Please wait, or contact your snow service directly.</p></div>'));
    if (mine.filter((r) => r.status === 'pending').length >= config.maxPendingPerToken) return sendHtml(res, 429, page('Too many requests', '<div class="card"><p>You already have requests waiting for an answer.</p></div>'));
    state.requests.push({ id: crypto.randomBytes(12).toString('hex'), token, kind, reason: kind === 'urgent' ? reason : '', note: cleanText(form.get('note'), 500),
      createdAt: new Date(t).toISOString(), stormId: s.stormId, status: 'pending', message: '' });
    save();
    res.writeHead(303, { location: `/c/${token}?sent=1`, ...SECURITY_HEADERS });
    res.end();
  }

  return {
    /** True for the paths this module owns, so another handler can take everything else. */
    matches(rawUrl) { const p = (rawUrl || '').split('?')[0]; return p.startsWith('/c/') || p.startsWith('/assets/') || p.startsWith('/v1/portal/') || p.startsWith('/v1/send/'); },
    async handle(req, res) {
      const url = new URL(req.url, 'http://localhost');
      const path = url.pathname;
      try {
        if (path.startsWith('/assets/')) {
          const name = path.slice('/assets/'.length);
          const asset = req.method === 'GET' && /^[a-z.]+$/.test(name) ? assets.get(name) : null;      // only the listed files, never a path
          if (!asset) return notFound(res);
          res.writeHead(200, { 'content-type': asset.type, 'content-length': asset.body.length, 'cache-control': 'public, max-age=86400', 'x-content-type-options': 'nosniff' });
          return res.end(asset.body);
        }
        const sub = path.match(/^\/c\/([^/]+)\/(live\.json|manifest\.webmanifest)$/);
        if (sub) {
          if (req.method !== 'GET') return sendJson(res, 405, { error: 'Method not allowed' });
          if (!ipAllowed(req)) return sendJson(res, 429, { error: 'Too many requests' });
          const token = sub[1];
          if (!TOKEN_RE.test(token) || !state.snapshots[token]) return notFound(res);
          if (sub[2] === 'live.json') return sendJson(res, 200, liveView(token));
          const s = state.snapshots[token];
          const body = JSON.stringify({ name: `${s.company || 'Snow service'}: ${s.label}`.slice(0, 80), short_name: (s.company || 'Snow update').slice(0, 24), start_url: `/c/${token}`, scope: `/c/${token}`, display: 'standalone', background_color: '#f4f6f9', theme_color: '#0d2540' });
          res.writeHead(200, { 'content-type': 'application/manifest+json', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' });
          return res.end(body);
        }
        const m = path.match(/^\/c\/([^/]+)(\/request|\/thanks|\/pay)?$/);
        if (m) {
          if (!ipAllowed(req)) return sendHtml(res, 429, page('Slow down', '<div class="card"><p>Too many requests from your connection. Please try again in a minute.</p></div>'));
          const token = m[1];
          if (!TOKEN_RE.test(token) || !state.snapshots[token]) return notFound(res);        // same answer for wrong, old and malformed links
          if (!m[2] && req.method === 'GET') return sendHtml(res, 200, renderClientPage(token, url.searchParams.get('sent') === 'thanks' ? 'thanks' : url.searchParams.get('sent') === '1'));
          if (m[2] === '/pay' && req.method === 'GET') return sendHtml(res, 200, renderPayPage(token, url.searchParams.get('for')));
          if (m[2] === '/request' && req.method === 'POST') return await postClientRequest(req, res, token);
          if (m[2] === '/thanks' && req.method === 'POST') return await postThanks(req, res, token);
          return sendJson(res, 405, { error: 'Method not allowed' });
        }
        if (!isOwner(req)) return sendJson(res, 401, { error: 'Missing or invalid token' });
        if (req.method === 'PUT' && path === '/v1/portal/snapshot') return await putSnapshot(req, res);
        if (req.method === 'PUT' && path === '/v1/portal/trucks') return await putTrucks(req, res);
        if (req.method === 'GET' && path === '/v1/portal/requests') return getRequests(req, res, url);
        if (req.method === 'POST' && path === '/v1/portal/decisions') return await postDecision(req, res);
        if (req.method === 'POST' && path === '/v1/send/email') return await sendEmail(req, res);
        return sendJson(res, 404, { error: 'Not found' });
      } catch {
        return sendJson(res, 500, { error: 'Internal error' });
      }
    },
    /** For tests. */
    _state: () => state,
  };
}
