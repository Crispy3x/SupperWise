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
| `MAX_POINTS` | 50 | Most points (depot plus stops) per request. A 50-point matrix is 2,500 elements. |
| `MAX_ELEMENTS_PER_REQUEST` | 100 | Size of each upstream request. Raise to 625 only after confirming the current Google limit for traffic-aware requests. |
| `CACHE_TTL_SECONDS` | 300 | How long an identical request is served from memory. Confirm Google's terms on caching before raising it. |
| `RATE_LIMIT_PER_MIN` | 30 | Requests per token per minute. |
| `DAILY_ELEMENT_CAP` | 20000 | Matrix elements per token per UTC day. Set from your budget (Google bills per element). |
| `MAX_BODY_BYTES` | 1000000 | Largest request body. |
| `UPSTREAM_URL` | Google | Only for tests. |

## API
`POST /v1/matrix` with `Authorization: Bearer <token>` and body
`{"points":[{"latitude":45.0,"longitude":-93.0}, ...], "departureTime":"2030-01-01T00:00:00Z"}`
(`departureTime` optional, must be in the future).
Returns `{"seconds":[[0,100,...],...], "cached":false, "elements":9}`. `null` means no route was found; the app fills those from its offline estimate.
Errors: 400 bad input, 401 bad token, 413 too large, 429 rate or daily limit, 502 Google failed, 503 not configured.
`GET /health` returns `{"ok":true}`.

## Tests
```
cd server && npm test
```
16 tests against a stand-in for Google (no real key, no real calls): auth, validation, request splitting, caching and expiry, rate and daily caps, missing routes, upstream failure without leaking the key, oversized bodies.

## Before you rely on it
- **Not run against real Google yet.** The request and response shapes follow Google's documented Routes API, but they have only been exercised against a stand-in. Test with a real key and a small matrix first.
- **Check Google's terms.** Google Maps Platform terms limit how long results may be stored and restrict using results with a non-Google map. Read the current terms (and ask a lawyer if unsure). Valhalla with VROOM is an alternative that avoids both the terms question and per-request cost, and would sit behind this same `/v1/matrix` API.
- **Cost.** Google bills per matrix element. A 25-stop route is 625 elements. The daily cap, cache and small `MAX_POINTS` are there to keep this predictable. Watch real usage and billing alerts in the Google console.
- **Hosting, monitoring and backups are not set up.** Pick a host, store the key as a secret there, and set a budget alert.
- **In-memory limits and cache** reset on restart and are per server instance. If you run several instances, move them to a shared store.
- **Token handling.** Tokens are compared in constant time and never logged. Issue one per customer so you can revoke individually (restart with the token removed).
