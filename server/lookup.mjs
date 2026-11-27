// Signing in to the website tracker with a last name (and a house number) instead of a property code.
// The phone never sends names. Per site it sends two hashes (see Sources/RidgelineCore/PortalLookup.swift):
//   lookup     = sha256("<salt>|<normalized last name>|<house number>")   lowercase hex
//   lookupName = sha256("<salt>|<normalized last name>")                  for PORTAL_LOOKUP=lastname
// plus the business's random salt (lookupSalt). This file hashes what a visitor typed the same way and compares in
// constant time. What was typed is never stored or logged.
import crypto from 'node:crypto';

export const SALT_RE = /^[0-9a-f]{32}$/;
export const HASH_RE = /^[0-9a-f]{64}$/;
export const LOOKUP_FAIL = "We couldn't find your service. Check the spelling of your last name and your house number.";
const ZERO = Buffer.alloc(32);

/** Letters only, lowercase, accents folded: "O'Neil" -> "oneil", "García" -> "garcia", "Smith-Jones" -> "smithjones".
 *  Must stay the same as PortalLookup.normalize in the app: NFKD, combining marks dropped, lowercased, a to z kept. */
export function normalizeName(raw) {
  if (typeof raw !== 'string') return '';
  return raw.slice(0, 200).normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z]/g, '');
}

/** What a visitor typed may be "Garcia", "José García" or "Van Dyke". The app hashes the last word of the client's name
 *  (or the owner's own "Name for their tracker", whole), so both the whole entry and its last word are tried. */
export function nameCandidates(raw) {
  const s = typeof raw === 'string' ? raw.slice(0, 200) : '';
  const words = s.split(/\s+/).map(normalizeName).filter(Boolean);
  return [...new Set([normalizeName(s), words.length ? words[words.length - 1] : ''].filter(Boolean))];
}

/** Leading digits only: "14B" -> "14". The app takes the same from the start of the site address. */
export function houseNumberOf(raw) {
  const m = (typeof raw === 'string' ? raw.trim() : '').match(/^[0-9]{1,10}/);
  return m ? m[0] : '';
}

export const lookupHash = (salt, name, number) => crypto.createHash('sha256').update(number === undefined ? `${salt}|${name}` : `${salt}|${name}|${number}`).digest();

/** Same list as the app's ReviewLink.allowedHosts: https only, no login, port or fragment, known review sites only. */
const REVIEW_HOSTS = ['g.page', 'google.com', 'maps.app.goo.gl', 'search.google.com', 'yelp.com', 'facebook.com', 'nextdoor.com'];
export function cleanReviewUrl(v) {
  if (typeof v !== 'string' || v.length > 500 || /\s/.test(v)) return '';
  let u; try { u = new URL(v); } catch { return ''; }
  if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash) return '';
  const host = u.hostname.toLowerCase();
  return REVIEW_HOSTS.some((h) => host === h || host.endsWith('.' + h)) ? u.href : '';
}

/** Compares a stored hex hash with every candidate, always all of them, in constant time per comparison. */
function matchesAny(storedHex, candidates) {
  const ok = HASH_RE.test(storedHex || '');
  const stored = ok ? Buffer.from(storedHex, 'hex') : ZERO;
  let hit = false;
  for (const c of candidates) hit = crypto.timingSafeEqual(stored, c) || hit;
  return ok && hit;
}

/**
 * @param o { config, getState, clientIp, now }
 * config.lookupMode 'both' (default: last name and house number) or 'lastname'.
 */
export function createLookup({ config, getState, clientIp, now = () => Date.now() }) {
  const mode = config.lookupMode === 'lastname' ? 'lastname' : 'both';
  const windowMs = Math.max(1, config.lookupWindowMinutes ?? 10) * 60_000;
  const perIp = config.lookupPerIp ?? 10;
  const globalCap = config.lookupGlobal ?? 300;
  const hits = new Map();
  let all = [];

  /** Every try counts, found or not: 10 per connection and a cap for the whole server per window. */
  function allowed(req) {
    const t = now(); const ip = clientIp(req);
    all = all.filter((x) => t - x < windowMs);
    const mine = (hits.get(ip) ?? []).filter((x) => t - x < windowMs);
    if (mine.length >= perIp || all.length >= globalCap) { hits.set(ip, mine); return false; }
    mine.push(t); all.push(t); hits.set(ip, mine);
    if (hits.size > 5000) for (const [k, v] of hits) if (!v.length || t - v[v.length - 1] >= windowMs) hits.delete(k);
    return true;
  }

  /** { token } on exactly one match, { needNumber: true } when several properties share the last name (lastname mode
   *  without a number), otherwise { fail: true }. The same work is done whether or not anything matches. */
  function find(lastName, houseNumber) {
    const names = nameCandidates(lastName);
    const num = houseNumberOf(houseNumber);
    const snaps = getState().snapshots;
    // Only the most recent publish of each business counts: a deleted client's old page is not found by name.
    const latest = new Map();
    for (const s of Object.values(snaps)) if (s.lookupSalt && s.publishedAt) latest.set(s.lookupSalt, Math.max(latest.get(s.lookupSalt) ?? 0, s.publishedAt));
    const cache = new Map();
    const hashesFor = (salt) => {
      if (!cache.has(salt)) {
        const n = names.length ? names : ['-'];
        cache.set(salt, { full: n.map((x) => lookupHash(salt, x, num || '-')), name: n.map((x) => lookupHash(salt, x)) });
      }
      return cache.get(salt);
    };
    const full = []; const byName = [];
    for (const [token, s] of Object.entries(snaps)) {
      if (!s.lookupSalt || s.publishedAt !== latest.get(s.lookupSalt)) continue;
      const h = hashesFor(s.lookupSalt);
      const f = matchesAny(s.lookup, h.full); const n = matchesAny(s.lookupName, h.name);
      if (f && num && names.length) full.push(token);
      if (n && names.length) byName.push(token);
    }
    if (!names.length) return { fail: true };
    if (mode === 'both' || num) return full.length === 1 ? { token: full[0] } : { fail: true };
    if (byName.length === 1) return { token: byName[0] };
    return byName.length > 1 ? { needNumber: true } : { fail: true };
  }

  return { mode, allowed, find };
}
