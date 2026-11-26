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
  'Each message from the person starts with a line in square brackets that the app adds: the current date and time. Use it to turn words like today, tomorrow or Friday into dates. Lines that start with [Update: are also from the app and say what the person tapped since your last answer.',
].join('\n');
// The same lines are in the app (Sources/RidgelineCore/DirectAssistantTransport.swift); a test checks they match.
// This text and the tool list must not change in the middle of a chat: Claude ties its thinking to the conversation so far and
// answers 400 when the system prompt, the tools or an earlier message is different from when it last answered. That is why the
// time is not in here (the app puts it in front of each question) and why nothing below edits what the app sent.

/** The fewest answer tokens worth asking for. Below this an answer with thinking is almost always cut off, which costs money for nothing. */
export const MIN_ANSWER_TOKENS = 2048;

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
    // Room for one answer: thinking, the words and a tool call all come out of this. 4096 was too little (answers were cut off
    // and the app had to drop them). 16000 is Anthropic's suggested size for answers that are not streamed; above about 21,000
    // the SDK insists on streaming, so 20000 is the ceiling. The spend cap below still holds: see `chat`.
    maxTokens: Math.max(1, Math.min(Math.floor(num(env.AI_MAX_TOKENS, 16000)), 20000)),
    dailyCap: num(env.AI_DAILY_MESSAGE_CAP, 400),
    // One question is up to 8 requests (one per tool step) plus a status check, so 20 a minute ran out after two quick questions.
    ipLimitPerMinute: num(env.AI_RATE_LIMIT_PER_MIN, 60),
    maxBodyBytes: num(env.AI_MAX_BODY_BYTES, 400_000),
    maxMessages: num(env.AI_MAX_MESSAGES, 120),
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

/** Dollars per million tokens [input, output] for a request with this many input tokens. */
export function rates(config, inTok, { fallbackPossible = false } = {}) {
  let [pin, pout] = fallbackPossible ? SAFE_PRICE : (PRICES[config.model] || SAFE_PRICE);
  const tier = !fallbackPossible && PRICES[config.model]?.[2];
  if (tier && inTok > tier.overInput) { pin = tier.inHigh; pout = tier.outHigh; }
  if (config.priceIn !== undefined && Number.isFinite(config.priceIn)) pin = config.priceIn;
  if (config.priceOut !== undefined && Number.isFinite(config.priceOut)) pout = config.priceOut;
  return [pin, pout];
}

/** Cost of one answer in micro-dollars, rounded up. Cached tokens are counted at the full input price (slightly high, never low). */
export function costMicros(config, usage, { fallbackPossible = false } = {}) {
  const inTok = (usage?.input_tokens || 0) + (usage?.cache_read_input_tokens || 0) + (usage?.cache_creation_input_tokens || 0);
  const outTok = usage?.output_tokens || 0;
  const [pin, pout] = rates(config, inTok, { fallbackPossible });
  return Math.ceil(inTok * pin + outTok * pout);        // dollars per million tokens equals micro-dollars per token
}

/**
 * How many answer tokens this request may use, and what to hold back for it, so the month's allowance can never be passed.
 * `room` is what is left of the allowance in micro-dollars. The input is priced from a deliberately high estimate (and at the
 * long-prompt price when the estimate is anywhere near that line); whatever is left after it buys the answer, up to the usual
 * maximum. Returns { maxTokens: 0 } when there is not room for a useful answer.
 */
export function affordable(config, inputTokens, room, { fallbackPossible = false } = {}) {
  const [pin, pout] = rates(config, Math.ceil(inputTokens * 1.5), { fallbackPossible });
  const inputHold = Math.ceil(inputTokens * pin);
  const left = room - inputHold;
  const canBuy = pout > 0 ? Math.floor(left / pout) : config.maxTokens;
  const maxTokens = Math.min(config.maxTokens, canBuy);
  if (left <= 0 || maxTokens < Math.min(MIN_ANSWER_TOKENS, config.maxTokens)) return { maxTokens: 0, reserve: 0 };
  return { maxTokens, reserve: inputHold + Math.ceil(maxTokens * pout) };
}

const clean = (v, max) => (typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ').trim().slice(0, max) : '');

/**
 * Checks the shape of what the app sent. Returns { error } or { messages, tools, context }.
 * A problem with the conversation itself is marked `conversation` (a fresh chat fixes it) or `tooLong`, so the app can recover
 * by itself instead of showing the same error for every question. Blocks are only checked for having a type: thinking,
 * redacted_thinking, tool_use, tool_result and anything newer pass through untouched, as Claude needs them back unchanged.
 */
export function validateChat(body, config) {
  if (!body || typeof body !== 'object') return { error: 'Body must be JSON' };
  const { messages, tools } = body;
  if (!Array.isArray(messages) || messages.length === 0) return { error: 'messages must be a list' };
  if (messages.length > config.maxMessages) return { error: `messages must be a list of 1 to ${config.maxMessages}`, tooLong: true };
  for (const m of messages) {
    if (!m || !ROLES.has(m.role)) return { error: 'each message needs a role of user or assistant', conversation: true };
    if (typeof m.content === 'string') { if (!m.content.trim()) return { error: 'messages cannot be empty', conversation: true }; continue; }
    if (!Array.isArray(m.content) || m.content.length === 0 || m.content.some((b) => !b || typeof b !== 'object' || typeof b.type !== 'string')) return { error: 'message content must be text or a list of blocks', conversation: true };
  }
  if (messages[messages.length - 1].role !== 'user') return { error: 'the last message must be from the user', conversation: true };
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

/** What to tell the app when Claude answers with an error. Nothing from Claude is passed on except its reason for refusing a conversation. */
export function upstreamFailure(e) {
  const status = e && typeof e.status === 'number' ? e.status : 0;
  // Anthropic's own error text describes the request's shape (never what people asked), so it is safe to log and pass on.
  const reason = clean(e?.error?.error?.message ?? e?.error?.message ?? '', 300);
  const low = reason.toLowerCase();
  const timedOut = !status && /timeout|timed out/i.test(`${e?.name || ''} ${e?.constructor?.name || ''}`);
  let out;
  if (status === 429) out = [429, { error: 'The assistant is busy. Try again in a minute.' }];
  else if (status === 529 || status === 503) out = [503, { error: 'Claude is busy right now. Try again in a minute.', retry: true }];
  else if (status === 401 || status === 403) out = [502, { error: 'The assistant is not set up correctly on the server (Anthropic did not accept its key).' }];
  else if (status === 404) out = [502, { error: 'The assistant is not set up correctly on the server (Anthropic does not know the model in AI_MODEL).' }];
  else if (status === 413 || (status === 400 && /too long|too large|context window/.test(low))) out = [413, { error: 'This chat is too long for the assistant. Start a new chat.', tooLong: true }];
  else if (status === 400 && /credit|billing/.test(low)) out = [502, { error: 'The assistant is out of credit on the server. Its owner needs to add credit at console.anthropic.com.' }];
  else if (status === 400) out = [502, { error: 'Claude did not accept this chat. Start a new chat and ask again.', reason, conversation: true }];
  else if (status >= 500) out = [502, { error: 'Claude had a problem on its side. Try again in a minute.', retry: true }];
  else if (timedOut) out = [504, { error: 'Claude took too long to answer. Try again, or ask for one thing at a time.' }];
  else out = [502, { error: 'The server could not reach Claude. Try again in a minute.' }];
  return { status: out[0], body: out[1], log: `assistant upstream error ${status || (timedOut ? 'timeout' : 'network')}${reason ? `: ${reason}` : ''}` };
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
    // 90 seconds and one retry is at most about three minutes. The app waits 200 seconds, so it always hears the real reason.
    if (!clientPromise) clientPromise = import('@anthropic-ai/sdk').then((m) => new (m.default ?? m.Anthropic)({ apiKey: config.apiKey, maxRetries: 1, timeout: 90_000 }));
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
    if (ipHits.size > 5000) for (const [k, v] of ipHits) if (t - v[v.length - 1] >= 60_000) ipHits.delete(k);   // never grow without bound
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
    if (v.error) return sendJson(res, 400, { error: v.error, ...(v.conversation ? { conversation: true, reason: v.error } : {}), ...(v.tooLong ? { tooLong: true } : {}) });

    const used = daily.get(key);
    const today = day();
    const count = used && used.day === today ? used.count : 0;
    if (count >= config.dailyCap) return sendJson(res, 429, { error: 'The assistant has reached its limit for today. It resets at midnight UTC.' });
    daily.set(key, { day: today, count: count + 1 });
    if (daily.size > 5000) for (const [k, u] of daily) if (u.day !== today) daily.delete(k);

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
    // When the allowance is nearly used, the answer is given less room rather than refused, down to MIN_ANSWER_TOKENS.
    const budget = budgetFor(who);
    const e = entry(key);
    const inputEstimate = Math.ceil(JSON.stringify(params).length / 3);       // high on purpose: real text is nearer 4 characters a token
    const room = budget - e.spent - e.reserved;
    const appRoom = who.app && config.appMonthlyCapUsd > 0 ? Math.round(config.appMonthlyCapUsd * 1_000_000) - appSpentMicros() : Infinity;
    const hold = affordable(config, inputEstimate, Math.min(room, appRoom), { fallbackPossible });
    if (!hold.maxTokens) {
      if (affordable(config, inputEstimate, room, { fallbackPossible }).maxTokens) {
        // This phone still has allowance; it is the ceiling for all built-in tokens together that is used up.
        log('assistant built-in monthly cap reached');
        return sendJson(res, 429, { error: 'The assistant has reached this month\'s limit. It starts again on the 1st.' });
      }
      return sendJson(res, 429, { error: 'The assistant has used this month\'s allowance. It starts again on the 1st.', usedPercent: Math.min(100, Math.round((e.spent / Math.max(budget, 1)) * 100)) });
    }
    params.max_tokens = hold.maxTokens;
    const reserve = hold.reserve;
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
      const failure = upstreamFailure(e);
      log(failure.log);
      actual = 0;                                    // a failed call is not billed
      return sendJson(res, failure.status, failure.body);
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
