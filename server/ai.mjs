// Ridgeline Ops assistant: a small, stateless proxy between the app and Claude.
// The app keeps the conversation and runs the tools on the device; this server only holds the API key, caps cost and
// abuse, and fixes the model and the house rules. It stores nothing: no messages, no results, no client details.
import crypto from 'node:crypto';
import fs from 'node:fs';

const digest = (s) => crypto.createHash('sha256').update(s).digest();
const DAY = 86_400_000;
const TOOL_NAME = /^[A-Za-z0-9_-]{1,64}$/;
const ROLES = new Set(['user', 'assistant']);

// Models that accept the server-side refusal fallback. Any other model is called without it.
const FALLBACK_MODELS = new Set(['claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5', 'claude-fable-5-2', 'claude-fable-5-1']);

// What Claude costs, in US dollars per million tokens (input, output). From Anthropic's published prices as of 2026-11-03: CHECK THEM
// before relying on the cap, and override with AI_PRICE_IN_PER_MTOK / AI_PRICE_OUT_PER_MTOK if they change.
// A model that is not listed is charged at the highest price here, so the cap errs on the safe side.
const PRICES = {
  'claude-haiku-5-5': [0.10, 0.50, { overInput: 100_000, inHigh: 0.50, outHigh: 2.50 }],
  'claude-sonnet-5-5': [2, 10], 'claude-sonnet-5': [2, 10],
  'claude-opus-5-5': [4, 20], 'claude-opus-5': [5, 25],
  'claude-fable-5-2': [8, 40], 'claude-fable-5-1': [10, 50],
};
const SAFE_PRICE = [10, 50];

/** Monthly price a customer pays Apple for, before Apple's cut. Mirrors the app's Pricing: per crew, 20% off when billed yearly. */
export function grossMonthlyUsd({ plan, crews = 1, billing = 'monthly' }) {
  const table = { pro: [29, 19, 12], max: [79, 29, 19] }[plan];
  if (!table) return 0;
  const n = Math.max(1, Math.floor(crews) || 1);
  const monthly = table[0] + table[1] * Math.min(Math.max(n - 1, 0), 4) + table[2] * Math.max(n - 5, 0);
  return billing === 'annual' ? Math.round(monthly * 80) / 100 : monthly;
}

export const SYSTEM_PROMPT = [
  'You are the Ridgeline Ops assistant, built into an app for snow removal and landscaping business owners and their crews.',
  'Help with the work in the app: today\'s jobs, routes, clients, quotes and invoices. Use the tools to read the business\'s data and to make changes; never invent clients, jobs, invoices or amounts.',
  'Only say something was done after a tool result confirms it. Sending an invoice or message to a client is never done by you alone: the tool asks the person to confirm in the app, so say you have prepared it and that they need to tap Send.',
  'If a tool says the person is not allowed to do something, say so plainly and do not try another way around it.',
  'Ask one short question when a request is unclear or could match more than one client or job. Keep answers brief and plain, with no markdown headings.',
  'Routes are ordered by drive time only. You are not a weather or safety authority: for road conditions or safety, tell people to use their own judgement.',
].join('\n');

export function loadAiConfig(env = process.env) {
  const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
  return {
    ownerTokens: (env.API_TOKENS || '').split(',').map((t) => t.trim()).filter(Boolean),
    // Tokens built into the app so the assistant works with no setup. They reach only the assistant, never client data,
    // and every phone gets its own allowance (by the device id the app sends).
    appTokens: (env.AI_APP_TOKENS || '').split(',').map((t) => t.trim()).filter(Boolean),
    // What each phone using a built-in token may spend per month, in dollars.
    appDeviceBudgetUsd: num(env.AI_APP_DEVICE_BUDGET_USD, 1),
    // A hard ceiling for everything sent through built-in tokens together, per month, in dollars. 0 means no ceiling.
    appMonthlyCapUsd: num(env.AI_APP_MONTHLY_CAP_USD, 25),
    apiKey: env.ANTHROPIC_API_KEY || '',
    model: env.AI_MODEL || 'claude-haiku-5-5',          // the cheapest current model. Raise it with AI_MODEL (claude-sonnet-5-5, claude-opus-5-5) if answers are not good enough
    effort: ['low', 'medium', 'high'].includes(env.AI_EFFORT) ? env.AI_EFFORT : 'medium',
    maxTokens: Math.min(num(env.AI_MAX_TOKENS, 4096), 8192),
    dailyCap: num(env.AI_DAILY_MESSAGE_CAP, 200),
    ipLimitPerMinute: num(env.AI_RATE_LIMIT_PER_MIN, 20),
    maxBodyBytes: num(env.AI_MAX_BODY_BYTES, 300_000),
    maxMessages: num(env.AI_MAX_MESSAGES, 80),
    maxTools: 20,
    trustProxy: env.TRUST_PROXY === '1',
    // Spend cap: a share of what each customer pays, after Apple's cut. 30% is Apple's standard rate (the safe assumption);
    // set APPLE_FEE_PERCENT=15 if you are enrolled in Apple's Small Business Program.
    budgetPercent: num(env.AI_BUDGET_PERCENT, 10),
    appleFeePercent: num(env.APPLE_FEE_PERCENT, 30),
    // What a token gets when no paid plan is listed for it (a free trial, or a customer not set up yet), in dollars per month.
    trialBudgetUsd: num(env.AI_TRIAL_BUDGET_USD, 0.5),
    plans: parsePlans(env.AI_PLANS),
    usageFile: env.AI_USAGE_FILE || '',
    priceIn: env.AI_PRICE_IN_PER_MTOK ? Number(env.AI_PRICE_IN_PER_MTOK) : undefined,
    priceOut: env.AI_PRICE_OUT_PER_MTOK ? Number(env.AI_PRICE_OUT_PER_MTOK) : undefined,
  };
}

/** AI_PLANS is JSON: { "<owner token>": { "plan": "pro", "crews": 2, "billing": "monthly" } }. Set on the server, never by the app. */
export function parsePlans(text) {
  if (!text) return {};
  try { const o = JSON.parse(text); return o && typeof o === 'object' ? o : {}; } catch { return {}; }
}

/** The most this token may cost this month, in micro-dollars: budgetPercent of the revenue left after Apple's fee. */
export function monthlyBudgetMicros(config, token) {
  const spec = config.plans[token];
  const gross = spec ? grossMonthlyUsd(spec) : 0;
  if (gross <= 0) return Math.round(config.trialBudgetUsd * 1_000_000);
  // gross dollars x (100 - Apple's %) x the share % x 100 = micro-dollars. Done in whole numbers so rounding never lets it slip over.
  return Math.floor(Math.round(gross * 100) * (100 - config.appleFeePercent) * config.budgetPercent);
}

/** Cost of one answer in micro-dollars, rounded up. Cached tokens are counted at the full input price (slightly high, never low). */
export function costMicros(config, usage, { fallbackPossible = false } = {}) {
  const inTok = (usage?.input_tokens || 0) + (usage?.cache_read_input_tokens || 0) + (usage?.cache_creation_input_tokens || 0);
  const outTok = usage?.output_tokens || 0;
  let [pin, pout] = fallbackPossible ? SAFE_PRICE : (PRICES[config.model] || SAFE_PRICE);
  const tier = !fallbackPossible && PRICES[config.model]?.[2];
  if (tier && inTok > tier.overInput) { pin = tier.inHigh; pout = tier.outHigh; }
  if (config.priceIn !== undefined && Number.isFinite(config.priceIn)) pin = config.priceIn;
  if (config.priceOut !== undefined && Number.isFinite(config.priceOut)) pout = config.priceOut;
  return Math.ceil(inTok * pin + outTok * pout);        // dollars per million tokens equals micro-dollars per token
}

const clean = (v, max) => (typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ').trim().slice(0, max) : '');

/** Checks the shape of what the app sent. Returns { error } or { messages, tools, context }. */
export function validateChat(body, config) {
  if (!body || typeof body !== 'object') return { error: 'Body must be JSON' };
  const { messages, tools } = body;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > config.maxMessages) return { error: `messages must be a list of 1 to ${config.maxMessages}` };
  for (const m of messages) {
    if (!m || !ROLES.has(m.role)) return { error: 'each message needs a role of user or assistant' };
    if (typeof m.content === 'string') { if (!m.content.trim()) return { error: 'messages cannot be empty' }; continue; }
    if (!Array.isArray(m.content) || m.content.length === 0 || m.content.some((b) => !b || typeof b !== 'object' || typeof b.type !== 'string')) return { error: 'message content must be text or a list of blocks' };
  }
  if (messages[messages.length - 1].role !== 'user') return { error: 'the last message must be from the user' };
  let cleanTools;
  if (tools !== undefined) {
    if (!Array.isArray(tools) || tools.length > config.maxTools) return { error: `tools must be a list of at most ${config.maxTools}` };
    cleanTools = [];
    for (const t of tools) {
      if (!t || !TOOL_NAME.test(t.name || '') || typeof t.description !== 'string' || !t.input_schema || typeof t.input_schema !== 'object' || t.input_schema.type !== 'object') return { error: 'each tool needs a name, a description and an object input_schema' };
      cleanTools.push({ name: t.name, description: clean(t.description, 1500), input_schema: t.input_schema });
    }
  }
  return { messages, tools: cleanTools, context: clean(body.context, 2000) };
}

export function createAi(config, deps = {}) {
  const now = deps.now ?? (() => Date.now());
  const log = deps.log ?? ((l) => console.log(l));
  const ownerDigests = config.ownerTokens.map(digest);
  const appDigests = (config.appTokens || []).map(digest);
  const DEVICE_RE = /^[A-Za-z0-9-]{16,64}$/;
  const ipHits = new Map();
  const daily = new Map();
  let clientPromise = null;

  // ---- spend ledger: micro-dollars per token per month. Saved to a file, so a restart cannot reset the cap.
  const month = () => new Date(now()).toISOString().slice(0, 7);
  let ledger = {};
  if (config.usageFile && fs.existsSync(config.usageFile)) {
    try { ledger = JSON.parse(fs.readFileSync(config.usageFile, 'utf8')) || {}; }
    catch { try { fs.renameSync(config.usageFile, `${config.usageFile}.unreadable-${now()}`); } catch { /* ignore */ } log('assistant usage file unreadable: set aside, starting empty'); }
  }
  const saveLedger = () => {
    if (!config.usageFile) return;
    try { const tmp = `${config.usageFile}.tmp`; fs.writeFileSync(tmp, JSON.stringify(ledger)); fs.renameSync(tmp, config.usageFile); } catch { log('assistant usage file could not be saved'); }
  };
  const entry = (key) => {
    const m = month();
    if (!ledger[key] || ledger[key].month !== m) ledger[key] = { month: m, spent: 0, reserved: 0 };
    return ledger[key];
  };
  const fallbackPossible = FALLBACK_MODELS.has(config.model);

  /** The SDK is loaded only when the assistant is switched on, so servers that do not use it never need it installed. */
  function getClient() {
    if (deps.client) return Promise.resolve(deps.client);
    if (!clientPromise) clientPromise = import('@anthropic-ai/sdk').then((m) => new (m.default ?? m.Anthropic)({ apiKey: config.apiKey, maxRetries: 1, timeout: 120_000 }));
    return clientPromise;
  }

  const sendJson = (res, status, obj) => {
    const body = JSON.stringify(obj);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store' });
    res.end(body);
  };
  /** The caller's identity: a hash for the ledger, and the token itself only to look up its plan (never stored or logged). */
  const owner = (req) => {
    const h = req.headers.authorization || '';
    if (!h.startsWith('Bearer ')) return null;
    const d = digest(h.slice(7));
    for (const t of ownerDigests) if (crypto.timingSafeEqual(t, d)) return { key: d.toString('hex'), token: h.slice(7) };
    for (const t of appDigests) {
      if (!crypto.timingSafeEqual(t, d)) continue;
      const device = String(req.headers['x-ridgeline-device'] || '');
      if (!DEVICE_RE.test(device)) return null;
      return { key: `app:${digest(`${h.slice(7)}:${device}`).toString('hex')}`, token: null, app: true };
    }
    return null;
  };
  /** Spent plus held back this month through built-in tokens, across every phone. */
  const appSpentMicros = () => {
    const m = month(); let total = 0;
    for (const [k, e] of Object.entries(ledger)) if (k.startsWith('app:') && e.month === m) total += e.spent + e.reserved;
    return total;
  };
  const budgetFor = (who) => (who.app ? Math.round(config.appDeviceBudgetUsd * 1_000_000) : monthlyBudgetMicros(config, who.token));
  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0; let tooLarge = false; const chunks = [];
    req.on('data', (c) => {
      if (tooLarge) return;
      size += c.length;
      if (size > config.maxBodyBytes) { tooLarge = true; reject(Object.assign(new Error('too large'), { status: 413 })); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
  const clientIp = (req) => {
    if (config.trustProxy) { const x = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim(); if (x) return x; }
    return req.socket.remoteAddress || 'unknown';
  };
  const withinRate = (req) => {
    const t = now(); const ip = clientIp(req);
    const recent = (ipHits.get(ip) ?? []).filter((x) => t - x < 60_000);
    if (recent.length >= config.ipLimitPerMinute) return false;
    recent.push(t); ipHits.set(ip, recent);
    return true;
  };
  const day = () => Math.floor(now() / DAY);

  async function chat(req, res, who) {
    const key = who.key;
    let body;
    try { body = JSON.parse(await readBody(req)); }
    catch (e) {
      if (e.status === 413) { res.on('finish', () => req.destroy()); return sendJson(res, 413, { error: 'Request too large' }); }
      return sendJson(res, 400, { error: 'Body must be JSON' });
    }
    const v = validateChat(body, config);
    if (v.error) return sendJson(res, 400, { error: v.error });

    const used = daily.get(key);
    const today = day();
    const count = used && used.day === today ? used.count : 0;
    if (count >= config.dailyCap) return sendJson(res, 429, { error: 'The assistant has reached its limit for today. It resets at midnight UTC.' });
    daily.set(key, { day: today, count: count + 1 });

    const params = {
      model: config.model,
      max_tokens: config.maxTokens,
      thinking: { type: 'adaptive' },
      output_config: { effort: config.effort },
      system: v.context ? `${SYSTEM_PROMPT}\n\nAbout this business and person (from the app):\n${v.context}` : SYSTEM_PROMPT,
      messages: v.messages,
    };
    if (v.tools && v.tools.length) params.tools = v.tools;
    if (FALLBACK_MODELS.has(config.model)) { params.betas = ['server-side-fallback-2026-07-01']; params.fallbacks = 'default'; }

    // Money: hold back the most this answer could cost, and refuse if the month's allowance cannot cover it.
    // Holding it first means requests that arrive together cannot add up to more than the allowance.
    const budget = budgetFor(who);
    const e = entry(key);
    const reserve = costMicros(config, { input_tokens: Math.ceil(JSON.stringify(params).length / 3), output_tokens: config.maxTokens }, { fallbackPossible });
    if (who.app && config.appMonthlyCapUsd > 0 && appSpentMicros() + reserve > Math.round(config.appMonthlyCapUsd * 1_000_000)) {
      log('assistant built-in monthly cap reached');
      return sendJson(res, 429, { error: 'The assistant has reached this month\'s limit. It starts again on the 1st.' });
    }
    if (e.spent + e.reserved + reserve > budget) {
      return sendJson(res, 429, { error: 'The assistant has used this month\'s allowance. It starts again on the 1st.', usedPercent: Math.min(100, Math.round((e.spent / Math.max(budget, 1)) * 100)) });
    }
    e.reserved += reserve;
    let actual = null;

    try {
      const client = await getClient();
      const msg = await client.beta.messages.create(params);
      actual = costMicros(config, msg.usage, { fallbackPossible });
      return sendJson(res, 200, {
        content: msg.content,
        stop_reason: msg.stop_reason,
        model: msg.model,
        usage: msg.usage ? { input_tokens: msg.usage.input_tokens, output_tokens: msg.usage.output_tokens } : undefined,
      });
    } catch (e) {
      const status = e && typeof e.status === 'number' ? e.status : 0;
      // Anthropic's own error text describes the request's shape (never what people asked), so it is safe to log and pass on.
      const reason = clean(e?.error?.error?.message ?? e?.error?.message ?? '', 200);
      log(`assistant upstream error ${status || 'network'}${reason ? `: ${reason}` : ''}`);
      actual = 0;                                    // a failed call is not billed
      if (status === 429) return sendJson(res, 429, { error: 'The assistant is busy. Try again in a minute.' });
      if (status === 529 || status === 503) return sendJson(res, 503, { error: 'Claude is busy right now. Try again in a minute.', retry: true });
      if (status === 401 || status === 403) return sendJson(res, 502, { error: 'The assistant is not set up correctly on the server.' });
      if (status === 400) return sendJson(res, 502, { error: 'The assistant could not answer right now.', reason, conversation: true });
      return sendJson(res, 502, { error: 'The assistant could not answer right now.' });
    } finally {
      const cur = entry(key);
      cur.reserved = Math.max(0, cur.reserved - reserve);
      cur.spent += actual ?? reserve;                // if something went wrong before we saw the usage, charge what was held back
      saveLedger();
    }
  }

  return {
    matches(rawUrl) { const p = (rawUrl || '').split('?')[0]; return p === '/v1/ai/chat' || p === '/v1/ai/status'; },
    async handle(req, res) {
      try {
        const who = owner(req);
        if (!who) return sendJson(res, 401, { error: 'Missing or invalid token' });
        if (!withinRate(req)) return sendJson(res, 429, { error: 'Too many requests, slow down' });
        const path = (req.url || '').split('?')[0];
        if (req.method === 'GET' && path === '/v1/ai/status') {
          const budget = budgetFor(who); const e = entry(who.key);
          // Percent only: the app shows how much of the month's allowance is used, not dollar amounts.
          return sendJson(res, 200, { enabled: Boolean(config.apiKey || deps.client), model: config.model, usedPercent: Math.min(100, Math.round(((e.spent + e.reserved) / Math.max(budget, 1)) * 100)) });
        }
        if (req.method === 'POST' && path === '/v1/ai/chat') {
          if (!config.apiKey && !deps.client) return sendJson(res, 503, { error: 'The assistant is not switched on for this server.' });
          return await chat(req, res, who);
        }
        return sendJson(res, 405, { error: 'Method not allowed' });
      } catch {
        return sendJson(res, 500, { error: 'Internal error' });
      }
    },
  };
}
