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
- `GET /privacy`, `GET /support`, `GET /terms`: the public pages for the App Store listing (see below).

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
| `SUPPORT_EMAIL` | none | The address shown on `/support` (and as the contact on `/privacy`). Left out of both pages when unset or not a plain email address. |

Privacy: the server never stores phone numbers, email addresses or customer names (the website tracker sign-in keeps only salted hashes, see "Signing in with a last name"). Email addresses and message text pass through to the provider and are not logged (only counts). Unreadable data files are set aside, never overwritten.

## Tests
```
cd server && npm test
```
`node --test test/*.test.mjs` runs six files against stand-ins for Google, the email provider and Claude (no real key, no real calls): routing (`server.test.mjs`), client pages and email (`portal.test.mjs`), the assistant (`ai.test.mjs`) the public pages plus the pre-launch fixes (`pages.test.mjs`) the website widget (`embed.test.mjs`) and its last-name sign-in (`lookup.test.mjs`). Two of them also read the app's Swift sources when the whole repository is there, to check that the privacy policy and the assistant's house rules are word for word the same in the app and on the server.

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
- The page shows the status, the arrival window, stops ahead, a live map with the trucks, the weather, bills with a Pay now link, a request form, and a way to say thanks: a kind message for the driver plus Tip the crew and Send a coffee buttons. Both open a page with the crew's own Venmo, PayPal and Cash App links.
- Trucks appear only for a property waiting for service, only while their position is under 4 minutes old, and positions are rounded to about 10 metres. The app sends a position about once a minute while it is sharing (also when the truck stands still), and the page says "last seen about N min ago" when a position has not been refreshed for a while. Sharing only runs while the app is open on the phone.
- A thank-you message never counts against the request limit, and a mistyped page address (or one with a trailing slash) gets the plain "not available" page.
- `GET /v1/portal/requests` returns the newest 200 requests, oldest first, each with its `status`; with `?since=` it returns the first 200 after that moment.
- Map tiles come from OpenStreetMap (the customer's browser asks them directly). The map script itself is served from this server.
- `PORTAL_DATA_FILE` keeps requests and pages across restarts. Without it everything is lost on a restart.

### Email
- `RESEND_API_KEY` and `FROM_EMAIL` switch email on. An invoice is sent as a PDF attachment (one PDF per message, at most about 1 MB).
- `PORTAL_MAX_EMAIL_BODY_BYTES` (default 3000000) is the largest email request. Public pages keep the smaller `PORTAL_MAX_BODY_BYTES`.

### Public pages for the App Store listing
Three pages need no token and hold no client data. They use the same dark card style as the client page, and search engines may index them (client pages stay `noindex`).

| Page | What it is | Where it goes in App Store Connect |
|---|---|---|
| `GET /privacy` | The privacy policy: the same text as `LegalText.privacy` in the app. | Privacy Policy URL |
| `GET /support` | How to get help, cancel or change a plan, restore a purchase, and delete the account and data. Shows `SUPPORT_EMAIL` when it is set. | Support URL |
| `GET /terms` | Says the app is licensed under Apple's standard EULA and links to `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`. | Only if you want your own Terms link; the app itself links straight to Apple's EULA. |

The policy text lives in `legal.mjs` (`PRIVACY`) and in the app (`Sources/RidgelineCore/LegalText.swift`). Change both together: `test/pages.test.mjs` fails if they differ by a single character. A trailing slash and a query string are accepted; anything but GET or HEAD gets 405.

### The assistant
Set `ANTHROPIC_API_KEY` to switch it on. Without it the app uses the assistant built into the app if there is one, and otherwise shows that the assistant is not set up.

How a chat stays working (read this before changing `ai.mjs` or the app's `AssistantRunner`):
- Claude ties its thinking to the conversation so far. If the system prompt, the tool list or any earlier message is different from when it last answered, it answers 400. So the house rules and tool list are the same for a whole chat, the current time travels in front of each question (never in the system prompt), and neither the app nor this server edits earlier messages. If Claude still refuses a chat for that reason, the app sends it once more without the old thinking blocks; for any other refusal it starts a fresh chat by itself.
- One answer has room for thinking, the words and a tool call (`AI_MAX_TOKENS`, default 16000). 4096 was too little: answers were cut off and dropped.
- Every failure has its own plain message. The app never shows a bare "could not answer right now".

| Variable | Default | What it does |
|---|---|---|
| `ANTHROPIC_API_KEY` | none | Your key. It stays on the server. |
| `AI_MODEL` | `claude-haiku-5-5` | The cheapest current model. Raise it to `claude-sonnet-5-5` or `claude-opus-5-5` if answers are not good enough. No app update needed. |
| `AI_EFFORT` | `medium` | `low`, `medium` or `high`. |
| `AI_MAX_TOKENS` | 16000 | Room for one answer (thinking, words and a tool call together), at most 20000. Leave it unset. Below about 8000, answers get cut off; the server warns at start. |
| `AI_MAX_MESSAGES` | 120 | Most messages in one chat. The app starts a fresh chat by itself well before this. |
| `AI_MAX_BODY_BYTES` | 400000 | Largest request. A chat that reaches it gets "too long" and the app starts a fresh one. |
| `AI_PLANS` | none | JSON that says what each customer pays, for the spending limit: `{"<owner token>": {"plan": "pro", "crews": 2, "billing": "monthly"}}`. The app cannot change it. |
| `AI_BUDGET_PERCENT` | 10 | The most a customer's assistant use may cost, as a percent of what they pay after Apple's cut. |
| `APPLE_FEE_PERCENT` | 30 | Apple's cut. Use 15 if you are in the App Store Small Business Program. |
| `AI_APP_TOKENS` | (empty) | Tokens built into the app (GitHub secret `RIDGELINE_AI_APP_TOKEN`) so the assistant works with no setup. They reach only the assistant, never client pages or email. The app must send a device id. |
| `AI_APP_DEVICE_BUDGET_USD` | 1 | Monthly allowance per phone using a built-in token, in dollars. |
| `AI_APP_MONTHLY_CAP_USD` | 25 | Hard monthly ceiling for all built-in-token use together, in dollars. 0 means none. |
| `AI_TRIAL_BUDGET_USD` | 0.50 | Monthly allowance for a token with no paid plan listed (free trials). Set 0 to switch the assistant off for them. |
| `AI_USAGE_FILE` | none | Keeps each customer's spend across restarts. Set it, or a restart resets the limit. |
| `AI_DAILY_MESSAGE_CAP` | 400 | Requests per customer per day. One question is one request per tool step, up to 8. |
| `AI_RATE_LIMIT_PER_MIN` | 60 | Requests per minute per connection (one question is up to 8, plus a status check). |
| `AI_PRICE_IN_PER_MTOK`, `AI_PRICE_OUT_PER_MTOK` | built in | Override Claude's prices (dollars per million tokens) if they change. The built-in table is from 2026-11-03. |

Each request holds back the most it could cost before it runs, so requests arriving together cannot go over the limit. The hold is the input (estimated high, and at the long-prompt price when it is anywhere near 100,000 tokens) plus `max_tokens` at the output price. When less than a full answer's worth of allowance is left, the answer is given less room (`max_tokens` is lowered to what the allowance still covers) instead of being refused; below 2,048 tokens it is refused, because a shorter answer is nearly always cut off. A dearer model therefore gets shorter answers near the end of the month, never a bigger bill. The app is told only a percent used, never dollars.

## Embed on your website

A "Track your plow" box for a page on your own website (Wix, Squarespace, WordPress, GoDaddy, Shopify). The app shows the exact text to copy in Settings, under "Put it on your website".

Paste this where the box should appear (use your server's address):
```html
<div data-ridgeline></div>
<script src="https://YOUR-SERVER/embed.js" async></script>
```
- `data-mode="tracker"` (the default) shows your business name and asks the client for their **last name and house number** (see "Signing in" below). It then shows their status, the arrival time (big), "N stops before your house" or "You're next", the live truck map, the weather, Tip the driver and Send a coffee (the crew's Venmo, PayPal and Cash App page, in a new tab), Leave us a review (only when the app sent a valid review link), "Leave a note for the driver" (the client page's thanks form, answered inside the box), and a small Request service link that opens the client's own page in a new tab.
- `<div data-ridgeline data-mode="tips"></div>` is a box for everyone, with no client data: your business name, Tip the crew and Send a coffee with the crew's pay apps and, while a storm is on, "Crews are out: 12 of 30 stops done" (counts only, never addresses). It uses the most recent snapshot the app published.
- The script only adds an iframe from this server and sets its height when the page inside says how tall it is (it checks the message comes from this server and from its own frame). It loads nothing from anyone else. The map inside the frame loads tiles from OpenStreetMap, like the client page.

If your site builder removes scripts, paste a plain iframe instead (no automatic height, and no `?code=` pass-through):
```html
<iframe src="https://YOUR-SERVER/embed/tracker" title="Track your service" loading="lazy" referrerpolicy="no-referrer" style="width:100%;height:640px;border:0"></iframe>
```
For the tips box use `/embed/tips` and `height:320px`.

**Linking clients to your own page.** A client's code is the part after `/c/` in their season link. If your tracking page is `https://yourwebsite.com/track`, a client's link can be `https://yourwebsite.com/track?code=THEIRCODE`: the script passes the code to the box, so it opens straight on their property. In the app, save that page in Settings ("Your website's tracking page") and the season emails and the Share page link on a client's profile use it instead of the server page. The code then sits in your website's address bar, so your website's own analytics can see it; it is still only that client's page. Some builders (Wix "Embed HTML", for example) run pasted code inside their own frame, where the script cannot read your page's address: there clients type or paste their code (a whole season link works too).

### Signing in with a last name
Clients type the last name on their account and their house number, then press "Find my service". The form is a POST, and a match redirects to `/embed/tracker?code=<their code>`, so a refresh keeps the view and the name never appears in an address. `/embed/tracker?code=` keeps working for season-email links, and the box still has a "Have a private link?" field.

**The server never sees names.** For every property the app sends two hashes: `lookup` = SHA-256 of `"<salt>|<last name>|<house number>"` and `lookupName` = SHA-256 of `"<salt>|<last name>"`, plus `lookupSalt` (a random 32-character value made once per business and kept in the app's data). The last name is the last word of the client's name, lowercase, letters only, accents folded and apostrophes and hyphens removed ("O'Neil" becomes `oneil`, "José García" `garcia`, "Smith-Jones" `smithjones`). For a business client such as "Lakeside Clinic" that would be `clinic`, so the owner can type the name to use in "Name for their tracker (optional)" on the client's profile; when set it wins (used whole, so "Van Dyke" works). The house number is the leading digits of the site address ("14B Elm Ave" gives `14`). The server hashes what the visitor typed the same way (both the whole entry and its last word, so "José García" and "Garcia" both work) and compares in constant time. It never stores or logs what was typed. Only the most recent publish counts, so a client who was removed or asked to stop is not found by name. Two properties with the same last name and house number cannot be told apart and get the failure message: give one of them a different "Name for their tracker".

Someone with access to the server's data file could still try common last names and house numbers against the hashes (the salt is stored next to them). The hashes keep names out of the file and the logs; they do not make a stolen data file harmless.

**Why both fields by default (`PORTAL_LOOKUP`).** A last name alone is not a secret: neighbours, delivery drivers and anyone with a phone book know it. With last name only, anyone could type a stranger's surname and see when the plow reaches that house, roughly where it is on the map, and whether the property was serviced. Asking for the house number as well means a visitor has to know who lives at which number. `PORTAL_LOOKUP=lastname` switches to last name only, for owners who accept that trade-off (for example a small rural route where everyone knows each other): one match signs straight in, and when more than one property matches, the box asks for the house number. The server warns at start when it is set.

**Guessing is slowed down.** Every try counts, found or not: at most `PORTAL_LOOKUP_PER_IP` per connection and `PORTAL_LOOKUP_GLOBAL` for the whole server per `PORTAL_LOOKUP_WINDOW_MIN` minutes (on top of `PORTAL_IP_LIMIT_PER_MIN`). Every failure (wrong number, unknown name, empty or malformed form) gets the same page and status: "We couldn't find your service. Check the spelling of your last name and your house number." Each answer takes at least `PORTAL_LOOKUP_MIN_MS`, and the same hashing work is done whether or not anything matches.

**Who may frame it.** Only `/embed/*` pages may be shown inside another site; every other page keeps `frame-ancestors 'none'`. No cookies are used, and every page sends `X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer`.

| Variable | Default | What it does |
|---|---|---|
| `EMBED_ORIGINS` | none (any site) | Space-separated websites allowed to show the widget, for example `https://ridgeplow.com https://www.ridgeplow.com`. Unset means any site may frame it: easy to set up, and the widget shows nothing private without a valid code, but anyone could put your tips box or code form on their own page. Set it once your site works. Wix, Squarespace and Shopify may show the box from their own domains (for example `https://yoursite.wixsite.com` or a `filesusr.com` frame on Wix), so add those too if the box goes blank. Entries that are not plain origins are ignored with a warning at start. |
| `PUBLIC_URL` | none | This server's public address, for example `https://plow.example.com`. Optional: `embed.js` otherwise uses the address it was loaded from. |
| `PORTAL_LOOKUP` | both | Unset: clients sign in with last name **and** house number. `lastname`: last name only, house number asked only when several properties match (see the trade-off above). |
| `PORTAL_LOOKUP_PER_IP` | 10 | Sign-in tries per connection per window. |
| `PORTAL_LOOKUP_GLOBAL` | 300 | Sign-in tries for the whole server per window. |
| `PORTAL_LOOKUP_WINDOW_MIN` | 10 | The window, in minutes. |
| `PORTAL_LOOKUP_MIN_MS` | 250 | Every sign-in answer takes at least this long, found or not. |

Wrong, old and malformed codes all get the same "We could not find that code" with the same status, and the box counts against `PORTAL_IP_LIMIT_PER_MIN` like client pages. The review button links to the app's review link only when it is https on a known review site (Google, Yelp, Facebook, Nextdoor), the same list the app uses.
