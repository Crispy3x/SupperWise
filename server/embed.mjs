// The "track your plow" widget an owner pastes into a page on their own website (Wix, Squarespace, WordPress, GoDaddy, Shopify).
//   GET /embed.js        a tiny script: puts an iframe where <div data-ridgeline></div> is, and sizes it to fit
//   GET /embed/tracker   "Track your service": a code field, and with ?code=<client token> that client's compact page
//   GET /embed/tips      business-wide: name, Tip the crew / Send a coffee, and storm progress as counts only
//   GET /embed/tips/pay  the crew's pay apps (opened in a new tab from the tips widget)
// Only /embed/* pages may be framed (frame-ancestors from EMBED_ORIGINS, or * when unset). No cookies are used.
// Run by portal.mjs, which passes in its page template, state and helpers.

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
  const framePage = (title, inner, extra = {}) => page(title, inner, {
    head: extra.head || '',
    bodyAttrs: ` class="embed"${extra.bodyAttrs || ''}`,
    tail: `${extra.tail || ''}<script src="/assets/frame.js"></script>`,
  });

  // ---- tracker
  function codeForm(notFound) {
    let html = '<div class="card"><h1>Track your service</h1>';
    // Same words for a mistyped, malformed, old or unknown code: nothing here helps anyone guess.
    if (notFound) html += '<p class="err" role="alert">We could not find that code. Please check it and try again.</p>';
    html += `<form method="get" action="/embed/tracker"><label>Your property code
<input name="code" required maxlength="300" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="From your season link"></label>
<button type="submit">Show</button></form>
<p class="small">Your code is in the private link your snow service sent you, after /c/. You can also paste the whole link.</p></div>`;
    return framePage('Track your service', html);
  }

  function trackerView(token) {
    const s = getState().snapshots[token];
    const view = liveView(token);
    const statusClass = s.status === 'done' ? 'done' : s.status === 'skipped' ? 'skipped' : '';
    const t = esc(token);
    let html = `<div class="card"><p class="small">${esc(s.company)}</p><h1>Track your service</h1><p><strong>${esc(s.label)}</strong></p>`;
    if (s.stormName) html += `<p class="small">${esc(s.stormName)}${s.expected ? ': ' + esc(s.expected) : ''}</p>`;
    html += `<p><span class="status ${statusClass}" id="status">${esc(statusText[s.status])}</span></p>`;
    html += `<p class="small etalabel" id="etalabel"${s.eta ? '' : ' style="display:none"'}>${s.eta ? 'Estimated arrival' : ''}</p><p id="eta"${s.eta ? '' : ' style="display:none"'}>${s.eta ? esc(s.eta) : ''}</p>`;
    const ahead = Number.isInteger(view.stopsAhead) && s.status === 'planned'
      ? (view.stopsAhead === 0 ? 'You are next.' : `${view.stopsAhead} ${view.stopsAhead === 1 ? 'stop' : 'stops'} before yours.`) : '';
    html += `<p class="small" id="ahead">${ahead}</p>`;
    if (s.weather && (s.weather.summary || s.weather.alerts.length)) {
      html += `<p class="small"><span id="wxsummary">${esc(s.weather.summary)}</span> <span id="wxalerts">${esc(s.weather.alerts.join(' · '))}</span></p>`;
    }
    html += `<p class="small">Updated <span id="updated">${esc(new Date(s.updatedAt).toUTCString())}</span>. Forecasts can change.</p></div>`;
    const mapOn = Boolean(view.site && hasMap());
    if (mapOn) html += '<div class="card"><div id="map" role="img" aria-label="Map showing your property and the truck"></div><p class="small" id="mapnote"></p></div>';
    html += '<div class="card"><p>';
    if (s.payApps && s.payApps.length) {
      for (const [key, [label, emoji]] of Object.entries(payReasons)) html += `<a class="tipbtn" href="/c/${t}/pay?for=${key}" target="_blank" rel="noopener">${emoji} ${esc(label)}</a>`;
    }
    html += s.canRequest
      ? `<a class="btn" href="/c/${t}#ask" target="_blank" rel="noopener">Request service</a>`
      : `<a class="btn alt" href="/c/${t}" target="_blank" rel="noopener">Open my full page</a>`;
    html += '</p><p class="small"><a href="/embed/tracker">Use a different code</a></p></div>';
    return framePage('Track your service', html, {
      head: mapOn ? '<link rel="stylesheet" href="/assets/leaflet.css">' : '',
      bodyAttrs: ` data-token="${t}"`,
      tail: `<script type="application/json" id="live">${jsonForScript(view)}</script>${mapOn ? '<script src="/assets/leaflet.js"></script>' : ''}<script src="/assets/portal.js"></script>`,
    });
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
    handle(req, res, path, url) {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
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
      if (path === '/embed/tracker') {
        const raw = url.searchParams.get('code');
        if (raw === null || !raw.trim()) return send(res, 200, codeForm(false));
        const code = extractCode(raw);
        if (!CODE_RE.test(code) || !getState().snapshots[code]) return send(res, 404, codeForm(true));
        return send(res, 200, trackerView(code));
      }
      if (path === '/embed/tips') return send(res, 200, tipsWidget());
      if (path === '/embed/tips/pay') return send(res, 200, tipsPay(url.searchParams.get('for')));
      return send(res, 404, framePage('Page not available', '<div class="card"><h1>This page is not available</h1></div>'));
    },
  };
}
