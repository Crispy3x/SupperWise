# Ridgeline routing proxy

A small server between the app and Google's Routes API. It exists so that:
- the **Google key never ships inside the app** (anything in an app can be extracted),
- **cost is capped** per customer per day,
- repeat requests are **cached**,
- the app gets one simple answer: a drive-time matrix.

Zero dependencies. Node 20 or newer.

## Run it
```
cd server
export GOOGLE_MAPS_API_KEY=...        # the Google key; keep it only here
export API_TOKENS=token-one,token-two # one secret per app/customer; the app sends it as a Bearer token
node index.mjs                        # listens on PORT (default 8080)
```
Put it behind HTTPS (any host that terminates TLS for you). Never send tokens over plain HTTP outside local testing.

## Settings (environment variables)
| Variable | Default | What it does |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | none | Required for real answers. Without it requests get 503. |
| `API_TOKENS` | none | Comma-separated accepted tokens. The server refuses to start with none. |
| `PORT` | 8080 | Port to listen on. |
| `MAX_POINTS` | 30 | Most points (depot plus stops) per request. A 30-point matrix is 900 elements, about $9 at the list price I found earlier (check current pricing). |
| `MAX_ELEMENTS_PER_REQUEST` | 100 | Size of each upstream request. Raise to 625 only after confirming the current Google limit for traffic-aware requests. |
| `CACHE_TTL_SECONDS` | 300 | How long an identical request is served from memory. Confirm Google's terms on caching before raising it. |
| `RATE_LIMIT_PER_MIN` | 30 | Requests per token per minute. |
| `DAILY_ELEMENT_CAP` | 3000 | Matrix elements per token per UTC day. At about $10 per 1,000 elements that is at most about $30 a day per token before any free allowance. Set it from your own budget. |
| `MAX_BODY_BYTES` | 1000000 | Largest request body. |
| `UPSTREAM_URL` | Google | Only for tests. |

## API
`POST /v1/matrix` with `Authorization: Bearer <token>` and body
`{"points":[{"latitude":45.0,"longitude":-93.0}, ...], "departureTime":"2030-01-01T00:00:00Z"}`
(`departureTime` optional, must be in the future).
Returns `{"seconds":[[0,100,...],...], "cached":false, "elements":9}`. `null` means no route was found; the app fills those from its offline estimate.
Errors: 400 bad input, 401 bad token, 413 too large, 429 rate or daily limit, 502 Google failed, 503 not configured.
`GET /health` returns `{"ok":true}`.

## Client portal, requests and email (`portal.mjs`)
Run by the same server. Owner endpoints use the same `API_TOKENS` bearer token.
- `PUT /v1/portal/snapshot`: the app publishes what each client page shows (address label, status, one sentence).
- `GET /v1/portal/requests?since=<ISO date>`: new client requests.
- `POST /v1/portal/decisions`: accept or decline a request, with a message the client sees.
- `POST /v1/send/email`: up to 100 messages per call, sent through the email provider.
- `GET /c/<token>` and `POST /c/<token>/request`: the client's page and request form (public, no login).

| Variable | Default | What it does |
|---|---|---|
| `PORTAL_DATA_FILE` | none | Where pages and requests are saved. Without it they are lost on restart. Use a persistent disk. |
| `RESEND_API_KEY` | none | Your email provider key (Resend). Without it sending returns 503. |
| `FROM_EMAIL` | none | The sender address. The provider needs to verify your domain first. |
| `REPLY_TO_EMAIL` | none | Where client replies go: your support address. |
| `EMAIL_DAILY_CAP` | 300 | Emails per day for the whole server. |
| `PORTAL_REQUESTS_PER_HOUR` | 3 | Requests one client page may send per hour. |
| `PORTAL_MAX_PENDING` | 5 | Unanswered requests one page may hold. |
| `PORTAL_IP_LIMIT_PER_MIN` | 120 | Client page loads per connection per minute. Set `TRUST_PROXY=1` only behind a proxy that sets `X-Forwarded-For` honestly. |

Privacy: the server never stores phone numbers, email addresses or customer names. Email addresses and message text pass through to the provider and are not logged (only counts). Unreadable data files are set aside, never overwritten.

## Tests
```
cd server && npm test
```
30 tests (16 routing, 14 portal) against stand-ins for Google and the email provider (no real key, no real calls): auth, validation, request splitting, caching and expiry, rate and daily caps, missing routes, upstream failure without leaking the key, oversized bodies.

## Before you rely on it
- **Not run against real Google yet.** The request and response shapes follow Google's documented Routes API, but they have only been exercised against a stand-in. Test with a real key and a small matrix first.
- **Check Google's terms.** Google Maps Platform terms limit how long results may be stored and restrict using results with a non-Google map. Read the current terms (and ask a lawyer if unsure). Valhalla with VROOM is an alternative that avoids both the terms question and per-request cost, and would sit behind this same `/v1/matrix` API.
- **Cost.** Google bills per matrix element. A 25-stop route is 625 elements. The daily cap, cache and small `MAX_POINTS` are there to keep this predictable. Watch real usage and billing alerts in the Google console.
- **Hosting, monitoring and backups are not set up.** Pick a host, store the key as a secret there, and set a budget alert.
- **In-memory limits and cache** reset on restart and are per server instance. If you run several instances, move them to a shared store.
- **Token handling.** Tokens are compared in constant time and never logged. Issue one per customer so you can revoke individually (restart with the token removed).

## Client pages, email and the assistant

The same server also serves each client's private page (`/c/<token>`), sends email for the app, and runs the in-app assistant.

### Client pages
- A client's link lasts the whole winter (`PORTAL_SNAPSHOT_TTL_DAYS`, default 240). Send it once at the start of the season from the app (Clients, Send winter page links).
- The page shows the status, the arrival window, stops ahead, a live map with the trucks, the weather, bills with a Pay now link, a request form, and a way to say thanks: a kind message for the driver plus your own tip, coffee, donut and lunch links.
- Trucks appear only for a property waiting for service, only while their position is under 10 minutes old, and positions are rounded to about 10 metres.
- Map tiles come from OpenStreetMap (the customer's browser asks them directly). The map script itself is served from this server.
- `PORTAL_DATA_FILE` keeps requests and pages across restarts. Without it everything is lost on a restart.

### Email
- `RESEND_API_KEY` and `FROM_EMAIL` switch email on. An invoice is sent as a PDF attachment (one PDF per message, at most about 1 MB).
- `PORTAL_MAX_EMAIL_BODY_BYTES` (default 3000000) is the largest email request. Public pages keep the smaller `PORTAL_MAX_BODY_BYTES`.

### The assistant
Set `ANTHROPIC_API_KEY` to switch it on. Without it the app shows that the assistant is not set up.

| Variable | Default | What it does |
|---|---|---|
| `ANTHROPIC_API_KEY` | none | Your key. It stays on the server. |
| `AI_MODEL` | `claude-haiku-5-5` | The cheapest current model. Raise it to `claude-sonnet-5-5` or `claude-opus-5-5` if answers are not good enough. No app update needed. |
| `AI_EFFORT` | `medium` | `low`, `medium` or `high`. |
| `AI_PLANS` | none | JSON that says what each customer pays, for the spending limit: `{"<owner token>": {"plan": "pro", "crews": 2, "billing": "monthly"}}`. The app cannot change it. |
| `AI_BUDGET_PERCENT` | 10 | The most a customer's assistant use may cost, as a percent of what they pay after Apple's cut. |
| `APPLE_FEE_PERCENT` | 30 | Apple's cut. Use 15 if you are in the App Store Small Business Program. |
| `AI_TRIAL_BUDGET_USD` | 0.50 | Monthly allowance for a token with no paid plan listed (free trials). Set 0 to switch the assistant off for them. |
| `AI_USAGE_FILE` | none | Keeps each customer's spend across restarts. Set it, or a restart resets the limit. |
| `AI_DAILY_MESSAGE_CAP` | 200 | Questions per customer per day. |
| `AI_RATE_LIMIT_PER_MIN` | 20 | Requests per minute per connection. |
| `AI_PRICE_IN_PER_MTOK`, `AI_PRICE_OUT_PER_MTOK` | built in | Override Claude's prices (dollars per million tokens) if they change. The built-in table is from 2026-11-03. |

Each request holds back the most it could cost before it runs, so requests arriving together cannot go over the limit. The app is told only a percent used, never dollars.
