// The "track your plow" widget an owner pastes into a page on their own website (Wix, Squarespace, WordPress, GoDaddy, Shopify).
//   GET /embed.js        a tiny script: puts an iframe where <div data-ridgeline></div> is, and sizes it to fit
//   GET /embed/tracker   "Track your service": sign in with last name (and house number), and with ?code=<client token> that client's compact page
//   POST /embed/tracker  the sign-in form (lookup.mjs); on a match it redirects to ?code=<token>, so a refresh keeps the view
//   GET /embed/tips      business-wide: name, Tip the crew / Send a coffee, and storm progress as counts only
//   GET /embed/tips/pay  the crew's pay apps (opened in a new tab from the tips widget)
// Only /embed/* pages may be framed (frame-ancestors from EMBED_ORIGINS, or * when unset). No cookies are used.
// Run by portal.mjs, which passes in its page template, state and helpers.
import { createLookup, LOOKUP_FAIL } from './lookup.mjs';

const CODE_RE = /^[A-Za-z0-9_-]{22,64}$/;          // the same shape as a client page token
const ORIGIN_RE = /^https?:\/\/(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)*(:\d{1,5})?$/;
const HOST_RE = /^[A-Za-z0-9.-]{1,253}(:\d{1,5})?$/;
const PROGRESS_FRESH_MS = 24 * 3_600_000;           // a storm not updated for a day is not shown as "crews are out"
const FINISHED_FRESH_MS = 12 * 3_600_000;

/** EMBED_ORIGINS: space- or comma-separated site origins such as "https://ridgeplow.com https://www.ridgeplow.com".
 *  Unset or empty: null (any site may frame the widget). Entries that are not plain origins are dropped and reported,
 *  so nothing can be smuggled into the Content-Security-Policy header. */
export function parseEmbedOrigins(v) {
  const raw = typeof v === 'string' ? v.split(/[\s,]+/).filter(Boolean) : [];
  if (!raw.length) return { origins: null, invalid: [] };
  const origins = []; const invalid = [];
  for (const r of raw) {
    const o = r.toLowerCase().replace(/\/+$/, '');
    if (ORIGIN_RE.test(o)) { if (!origins.includes(o)) origins.push(o); } else invalid.push(r.slice(0, 80));
  }
  return { origins, invalid };
}

/** PUBLIC_URL: this server's public address, for example https://plow.example.com. Only its origin is kept. */
export function cleanPublicUrl(v) {
  if (typeof v !== 'string' || !v.trim()) return '';
  try { const u = new URL(v.trim()); return (u.protocol === 'https:' || u.protocol === 'http:') && !u.username && !u.password ? u.origin : ''; } catch { return ''; }
}

/** What a visitor typed or the link carried: a bare code, or a whole season link (…/c/<token>) or website link (…?code=<token>). */
export function extractCode(raw) {
  const s = typeof raw === 'string' ? raw.trim().slice(0, 300) : '';
  const fromLink = s.match(/\/c\/([A-Za-z0-9_-]+)/) || s.match(/[?&]code=([A-Za-z0-9_-]+)/);
  return fromLink ? fromLink[1] : s;
}

/** The host-page script. ORIGIN_SET is PUBLIC_URL (when set); ORIGIN_GUESS comes from the Host header.
 *  Otherwise the script's own address is used, which is exactly where the browser loaded it from. */
function embedScript(originSet, originGuess) {
  const lit = (s) => JSON.stringify(s).replace(/</g, '\\u003c');
  return `/* Ridgeline Ops widget. Paste: <div data-ridgeline></div><script src="${originSet || originGuess || 'https://YOUR-SERVER'}/embed.js" async></script>
   data-mode="tracker" (default) or data-mode="tips". Makes no requests of its own; the iframe loads from the server. */
(function () {
  'use strict';
  var ORIGIN_SET = ${lit(originSet)};
  var ORIGIN_GUESS = ${lit(originGuess)};
  var origin = ORIGIN_SET;
  if (!origin) {
    try {
      var s = document.currentScript;
      if (s && s.src) { var u = new URL(s.src, location.href); if (u.protocol === 'https:' || u.protocol === 'http:') origin = u.origin; }
    } catch (e) { /* fall back to the guess */ }
  }
  origin = origin || ORIGIN_GUESS;
  if (!origin) return;
  var CODE_RE = /^[A-Za-z0-9_-]{22,64}$/;
  var W = window.__ridgelineEmbed = window.__ridgelineEmbed || { frames: [], listening: false };

  // The season email can link to the owner's own page, for example their-site.com/track?code=<client code>
  function pageCode() {
    try { var c = (new URLSearchParams(location.search).get('code') || '').trim(); return CODE_RE.test(c) ? c : ''; }
    catch (e) { return ''; }
  }

  function mount(host) {
    if (host.getAttribute('data-ridgeline-ready')) return;
    host.setAttribute('data-ridgeline-ready', '1');
    var mode = host.getAttribute('data-mode') === 'tips' ? 'tips' : 'tracker';
    var src = origin + '/embed/' + mode;
    var code = mode === 'tracker' ? pageCode() : '';
    if (code) src += '?code=' + encodeURIComponent(code);
    var f = document.createElement('iframe');
    f.setAttribute('src', src);
    f.setAttribute('title', mode === 'tips' ? 'Tip the crew' : 'Track your service');
    f.setAttribute('loading', 'lazy');
    f.setAttribute('referrerpolicy', 'no-referrer');
    f.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox');
    f.style.cssText = 'display:block;width:100%;max-width:100%;border:0;border-radius:16px;overflow:hidden;height:' + (mode === 'tips' ? 300 : 420) + 'px';
    f.__ridgelineOrigin = origin;
    host.appendChild(f);
    W.frames.push(f);
  }

  function mountAll() {
    var list = document.querySelectorAll('[data-ridgeline]');
    for (var i = 0; i < list.length; i++) mount(list[i]);
  }

  if (!W.listening) {
    W.listening = true;
    // The page inside the frame says how tall it is. Only our own frames, from our own server, with the expected shape.
    window.addEventListener('message', function (e) {
      var d = e.data;
      if (!d || typeof d !== 'object' || d.ridgeline !== 'height' || typeof d.height !== 'number' || !isFinite(d.height)) return;
      for (var i = 0; i < W.frames.length; i++) {
        var f = W.frames[i];
        if (f.contentWindow === e.source && e.origin === f.__ridgelineOrigin) {
          f.style.height = Math.max(120, Math.min(5000, Math.ceil(d.height))) + 'px';
          return;
        }
      }
    });
  }

  mountAll();
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountAll);
  window.addEventListener('load', mountAll);
})();
`;
}

/**
 * @param ctx {
 *   config, getState, page, escapeHtml, jsonForScript, liveView, ipAllowed, securityHeaders, statusText, payReasons, hasMap
 * }
 */
export function createEmbed(ctx) {
  const { config, getState, page, escapeHtml: esc, jsonForScript, liveView, ipAllowed, securityHeaders, statusText, payReasons, hasMap } = ctx;
  const now = ctx.now ?? (() => Date.now());
  const lookup = createLookup({ config, getState, clientIp: ctx.clientIp ?? ((req) => req.socket.remoteAddress || 'unknown'), now });
  const readBody = ctx.readBody;
  const origins = config.embedOrigins === undefined ? null : config.embedOrigins;
  // Unset: '*' (any website may show the widget; the pages hold nothing without a valid code, and the code is the secret).
  // Set: only those sites. Set but nothing valid: no site (the owner sees a warning at start).
  const ancestors = origins === null ? '*' : origins.length ? origins.join(' ') : "'none'";
  const headers = {
    ...securityHeaders,
    'Content-Security-Policy': securityHeaders['Content-Security-Policy'].replace(/frame-ancestors [^;]*/, `frame-ancestors ${ancestors}`),
  };

  const send = (res, status, html) => {
    res.writeHead(status, { 'content-type': 'text/html; charset=utf-8', 'content-length': Buffer.byteLength(html), ...headers });
    res.end(html);
  };
  const EMBED_STYLE = '<style>.embed h1.biz{font-size:1.7rem}.embed #eta{font-size:2rem;font-weight:800}.poweredby{text-align:center;margin:4px 0 2px}.embed details summary{cursor:pointer}.embed .notice{color:var(--ok);font-weight:700}</style>';
  const framePage = (title, inner, extra = {}) => page(title, inner, {
    head: EMBED_STYLE + (extra.head || ''),
    bodyAttrs: ` class="embed"${extra.bodyAttrs || ''}`,
    tail: `${extra.tail || ''}<script src="/assets/frame.js"></script>`,
  });

  // ---- tracker
  const FOOTER = '<p class="small poweredby">Powered by Ridgeline Ops</p>';
  const EMBED_PAY_LABELS = { tip: 'Tip the driver' };

  /** The business name, big, from the latest snapshot the app published (it is public: the tips box shows it too). */
  function brandCard(company) {
    return company
      ? `<div class="card"><p class="small">Track your service</p><h1 class="biz">${esc(company)}</h1></div>`
      : '<div class="card"><h1 class="biz">Track your service</h1></div>';
  }

  /**
   * The sign-in page. Every failed lookup gets exactly the same page (nothing typed is echoed back), so it tells a
   * guesser nothing. `needNumber` (PORTAL_LOOKUP=lastname, several matches) shows the name again and asks for the number.
   */
  function signInPage({ error = '', needNumber = false, name = '', codeError = false } = {}) {
    const p = getState().public;
    let html = brandCard(p && p.company);
    const askNumber = lookup.mode === 'both' || needNumber;
    html += '<div class="card"><h2>Find my service</h2>';
    if (error) html += `<p class="err" role="alert">${esc(error)}</p>`;
    if (needNumber) html += '<p class="err" role="alert">More than one property matches that name. Please add your house number.</p>';
    html += `<p class="small">${askNumber ? 'Use the last name on your account and your house number.' : 'Use the last name on your account.'}</p>`;
    html += `<form method="post" action="/embed/tracker"><label>Last name
<input name="lastName" required maxlength="80" autocomplete="family-name" spellcheck="false" value="${esc(name)}"></label>`;
    if (askNumber) {
      html += `<label>House number
<input name="houseNumber" required maxlength="12" inputmode="numeric" autocomplete="off" placeholder="For example 14"></label>`;
    }
    html += '<button type="submit">Find my service</button></form></div>';
    // Season emails carry a private link; it still works, pasted here or as ?code=.
    // Same words for a mistyped, malformed, old or unknown code: nothing here helps anyone guess.
    html += `<details class="card"${codeError ? ' open' : ''}><summary class="small">Have a private link from your snow service?</summary>`;
    if (codeError) html += '<p class="err" role="alert">We could not find that code. Please check it and try again.</p>';
    html += `<form method="get" action="/embed/tracker"><label>Your link or code
<input name="code" required maxlength="300" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Paste the link"></label>
<button type="submit">Show</button></form></details>${FOOTER}`;
    return framePage('Track your service', html);
  }

  const NOTE_SENT = {
    thanks: ['notice', 'Note sent. Thank you! Your driver will see it.'],
    empty: ['err', 'Please write a note first.'],
    limit: ['err', 'You have sent a few notes already. Thank you! Please try again later.'],
  };

  function trackerView(token, sent) {
    const s = getState().snapshots[token];
    const view = liveView(token);
    const statusClass = s.status === 'done' ? 'done' : s.status === 'skipped' ? 'skipped' : '';
    const t = esc(token);
    let html = `<div class="card"><p class="small">Track your service</p><h1 class="biz">${esc(s.company)}</h1><p><strong>${esc(s.label)}</strong></p>`;
    if (s.stormName) html += `<p class="small">${esc(s.stormName)}${s.expected ? ': ' + esc(s.expected) : ''}</p>`;
    html += `<p><span class="status ${statusClass}" id="status">${esc(statusText[s.status])}</span></p>`;
    html += `<p class="small etalabel" id="etalabel"${s.eta ? '' : ' style="display:none"'}>${s.eta ? 'Estimated arrival' : ''}</p><p id="eta"${s.eta ? '' : ' style="display:none"'}>${s.eta ? esc(s.eta) : ''}</p>`;
    const ahead = Number.isInteger(view.stopsAhead) && s.status === 'planned'
      ? (view.stopsAhead === 0 ? "You're next." : `${view.stopsAhead} ${view.stopsAhead === 1 ? 'stop' : 'stops'} before your house.`) : '';
    html += `<p class="small" id="ahead">${ahead}</p>`;
    if (s.weather && (s.weather.summary || s.weather.alerts.length)) {
      html += `<p class="small"><span id="wxsummary">${esc(s.weather.summary)}</span> <span id="wxalerts">${esc(s.weather.alerts.join(' · '))}</span></p>`;
    }
    html += `<p class="small">Updated <span id="updated">${esc(new Date(s.updatedAt).toUTCString())}</span>. Forecasts can change.</p></div>`;
    const mapOn = Boolean(view.site && hasMap());
    if (mapOn) html += '<div class="card"><div id="map" role="img" aria-label="Map showing your house and the truck"></div><p class="small" id="mapnote"></p></div>';
    const tips = s.payApps && s.payApps.length;
    if (tips || s.reviewURL) {
      html += '<div class="card"><p>';
      if (tips) {
        for (const [key, [label, emoji]] of Object.entries(payReasons)) html += `<a class="tipbtn" href="/c/${t}/pay?for=${key}" target="_blank" rel="noopener">${emoji} ${esc(EMBED_PAY_LABELS[key] || label)}</a>`;
      }
      if (s.reviewURL) html += `<a class="btn alt" href="${esc(s.reviewURL)}" target="_blank" rel="noopener noreferrer">Leave us a review</a>`;
      html += '</p></div>';
    }
    // The driver's note uses the client page's own thanks form; back=embed brings the answer back into this frame.
    const note = NOTE_SENT[sent];
    html += `<div class="card" id="note"><h2>Leave a note for the driver</h2>${note ? `<p class="${note[0]}" role="status">${esc(note[1])}</p>` : ''}
<form method="post" action="/c/${t}/thanks"><input type="hidden" name="back" value="embed">
<label>Your note <textarea name="message" maxlength="200" rows="3" placeholder="Thank you for clearing the drive so early!"></textarea></label>
<label>Your first name (optional) <input name="from" maxlength="40"></label>
<button type="submit">Send note</button></form></div>`;
    html += '<p class="small">';
    html += s.canRequest
      ? `<a href="/c/${t}#ask" target="_blank" rel="noopener">Request service</a>`
      : `<a href="/c/${t}" target="_blank" rel="noopener">Open my full page</a>`;
    html += ` · <a href="/embed/tracker">Look up a different property</a></p>${FOOTER}`;
    return framePage('Track your service', html, {
      head: mapOn ? '<link rel="stylesheet" href="/assets/leaflet.css">' : '',
      bodyAttrs: ` data-token="${t}"`,
      tail: `<script type="application/json" id="live">${jsonForScript(view)}</script>${mapOn ? '<script src="/assets/leaflet.js"></script>' : ''}<script src="/assets/portal.js"></script>`,
    });
  }

  /** POST /embed/tracker. Rate limited per connection and for the whole server; at least `lookupMinMs` per answer so
   *  a hit and a miss take about as long. On a match: 303 to ?code=<token> (the name never goes into a URL). */
  async function postLookup(req, res) {
    const started = Date.now();
    if (!lookup.allowed(req)) {
      return send(res, 429, framePage('Slow down', `${brandCard(getState().public?.company)}<div class="card"><p class="err" role="alert">Too many tries. Please wait a few minutes and try again.</p><p class="small"><a href="/embed/tracker">Back</a></p></div>${FOOTER}`));
    }
    let form = null;
    try { form = new URLSearchParams(await readBody(req, 4000)); }
    catch (e) { if (e.status === 413) res.on('finish', () => req.destroy()); }
    const result = form ? lookup.find(form.get('lastName'), form.get('houseNumber')) : { fail: true };
    const wait = (config.lookupMinMs ?? 250) - (Date.now() - started);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    if (result.token) {
      res.writeHead(303, { location: `/embed/tracker?code=${result.token}`, 'content-length': 0, ...headers });
      return res.end();
    }
    if (result.needNumber) return send(res, 200, signInPage({ needNumber: true, name: String(form.get('lastName') || '').slice(0, 80) }));
    return send(res, 404, signInPage({ error: LOOKUP_FAIL }));
  }

  // ---- business-wide tips widget: no client data at all
  function progressLine(p) {
    if (!p || !Number.isInteger(p.planned) || !Number.isInteger(p.done)) return '';
    const age = now() - p.updatedAt;
    const total = p.planned + p.done;
    if (p.planned > 0 && age <= PROGRESS_FRESH_MS) return `Crews are out: ${p.done} of ${total} ${total === 1 ? 'stop' : 'stops'} done`;
    if (p.planned === 0 && p.done > 0 && age <= FINISHED_FRESH_MS) return `All ${p.done} ${p.done === 1 ? 'stop is' : 'stops are'} done for this storm`;
    return '';
  }

  function tipsWidget() {
    const p = getState().public;
    if (!p) return framePage('Tip the crew', '<div class="card"><h1>Say thanks to the crew</h1><p class="small">This is not set up yet.</p></div>');
    let html = `<div class="card"><p class="small">Say thanks to the crew</p><h1>${esc(p.company || 'Your snow crew')}</h1>`;
    const line = progressLine(p);
    if (line) html += `<p><span class="status" id="progress">${esc(line)}</span></p>${p.stormName ? `<p class="small">${esc(p.stormName)}</p>` : ''}`;
    if (p.payApps && p.payApps.length) {
      html += '<p class="small">Optional. You choose Venmo, PayPal or Cash App. The money goes straight to the crew.</p><p>';
      for (const [key, [label, emoji]] of Object.entries(payReasons)) html += `<a class="tipbtn" href="/embed/tips/pay?for=${key}" target="_blank" rel="noopener">${emoji} ${esc(label)}</a>`;
      html += '</p>';
    } else {
      html += '<p class="small">Thank you for choosing us.</p>';
    }
    return framePage('Tip the crew', `${html}</div>`);
  }

  function tipsPay(reason) {
    const p = getState().public;
    const [label, emoji, line] = payReasons[reason] || payReasons.tip;
    const apps = (p && p.payApps) || [];
    let inner = `<div class="card"><h1>${emoji} ${esc(label)}</h1>`;
    if (!apps.length) return page(label, `${inner}<p>Tipping is not set up right now.</p></div>`);
    inner += `<p>${esc(line)} Pick the app you use. It opens the crew's own page there, and you choose the amount.</p><p>`;
    for (const a of apps) inner += `<a class="btn payapp" href="${esc(a.url)}" rel="noopener noreferrer">${esc(a.label)}</a>`;
    inner += `</p><p class="small">Totally optional. Nothing is charged here, and ${esc(p.company || 'your snow service')} is not told who tips.</p></div>`;
    return page(label, inner);
  }

  return {
    matches: (p) => p === '/embed.js' || p === '/embed' || p.startsWith('/embed/'),
    /** `path` is already without a trailing slash. */
    async handle(req, res, path, url) {
      const isLookup = path === '/embed/tracker' && req.method === 'POST';
      if (req.method !== 'GET' && req.method !== 'HEAD' && !isLookup) {
        res.writeHead(405, { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
        return res.end(JSON.stringify({ error: 'Method not allowed' }));
      }
      if (path === '/embed.js') {
        const host = String(req.headers.host || '');
        const fwd = config.trustProxy ? String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim() : '';
        const proto = fwd === 'https' || req.socket.encrypted ? 'https' : 'http';
        const guess = HOST_RE.test(host) ? `${proto}://${host.toLowerCase()}` : '';
        const body = embedScript(config.publicUrl || '', guess);
        res.writeHead(200, {
          'content-type': 'text/javascript; charset=utf-8', 'content-length': Buffer.byteLength(body),
          'cache-control': 'public, max-age=3600', vary: 'Host, X-Forwarded-Proto',
          'x-content-type-options': 'nosniff', 'cross-origin-resource-policy': 'cross-origin', 'referrer-policy': 'no-referrer',
        });
        return res.end(req.method === 'HEAD' ? undefined : body);
      }
      if (!ipAllowed(req)) return send(res, 429, framePage('Slow down', '<div class="card"><p>Too many requests from your connection. Please try again in a minute.</p></div>'));
      if (isLookup) return await postLookup(req, res);
      if (path === '/embed/tracker') {
        const raw = url.searchParams.get('code');
        if (raw === null || !raw.trim()) return send(res, 200, signInPage());
        const code = extractCode(raw);
        if (!CODE_RE.test(code) || !getState().snapshots[code]) return send(res, 404, signInPage({ codeError: true }));
        return send(res, 200, trackerView(code, url.searchParams.get('sent')));
      }
      if (path === '/embed/tips') return send(res, 200, tipsWidget());
      if (path === '/embed/tips/pay') return send(res, 200, tipsPay(url.searchParams.get('for')));
      return send(res, 404, framePage('Page not available', '<div class="card"><h1>This page is not available</h1></div>'));
    },
  };
}
