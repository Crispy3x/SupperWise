# Ridgeline Ops

Snow-first crew and route software for iPhone, iPad and Mac. See `PLAN.md` for the market research, plans and pricing, and `research/` for the source notes. `research/INTERVIEW-SCRIPT.md` is the owner interview script.

## What exists so far

**Core logic (`Sources/RidgelineCore`)**: platform-neutral Swift, compiled and tested on Linux. 202 unit tests, all passing.
- `Pricing`, `Entitlements`: Pro and Max per-crew prices, annual 20% off, 14-day trial (all features unlocked), feature gating, read-only after trial.
- `SnowBilling`: per-push, seasonal, per-inch, hybrid (base, cap, overage) and time-and-materials. One invoice line per storm, skipped visits never billed, per-contract push counting (default one push per storm).
- `Storm`: trigger depth per site, near-trigger warnings.
- **Routing engine** (`RouteSequencer`, `RouteOptimizer`, `Conditions`, `DriveTimeMatrix`, `GoogleRoutes`, `NavigationLinks`): see "How routing works" below.
- `Scheduling` (`RouteBook`): bulk move routes to another crew or weekday, swap crews, move sites between routes.
- `VisitLog`, `DisputePacket`, `SHA256`: hash-chained, tamper-evident proof-of-service log (arrival, geofence, photos with hashes, weather note, salt) and a shareable text packet. Pure-Swift SHA-256 checked against reference vectors.
- `TimeClock`: shifts and per-job timers, audited corrections, labor cost per site, missed punch-out detection, geofence "start the job?" prompt, 20-region monitoring cap.
- `Invoicing`: editable invoices (add, change or remove lines until the first payment), due dates, manual payments (cash, check, other), partial payments, void, statuses, invoice numbering, seasonal installment splits with exact cents, a late-fee policy that is applied only when the owner chooses (once, labelled), CSV export with spreadsheet-formula protection, and `InvoicePlanner`, which stops a storm being billed twice and keeps hybrid push caps correct across invoices. A return trip added after its storm was invoiced is flagged, not silently billed or lost.
- `Quotes`: quotes that expire, can be accepted or declined once, and produce the contract; `SeasonEstimate` shows a customer the season cost (and a mild-to-heavy winter range) for every contract type from stated assumptions, so a per-push price never becomes a surprise; `JobCosting` gives margin per site from invoiced revenue, labor at your cost per hour, salt and sub pay.
- `DataExport`: a full JSON backup that restores everything, eight spreadsheet files (customers, sites, contracts, visits, invoices, payments, time entries, quotes) with spreadsheet-formula protection, and a restore that refuses non-backups and files from newer versions, flags a tampered visit log, and (in the app) saves a safety copy of the current data first. Photo files are not in the backup.
- `Notices`: customer message templates (scheduled, en route, delayed, skipped, complete). Completion notices require an after photo.
- `SubPay`: percent of job, hourly, per-push, per-lot, with "no photo, no pay".
- `Persistence` (`FileStore`): offline-first single-file store with atomic writes.

**App screens (`Sources/RidgelineUI`)**: SwiftUI for iPhone, iPad and Mac. **Written but never compiled or run**, because SwiftUI only builds on Apple platforms; expect small fixes on first build in Xcode.
- Crew: log a visit (completed or skipped with a reason), see standing site instructions, preview the customer message.
- Storm: set snowfall, falling rate, temperature and wind; see sites at trigger in planned order with ETAs and late warnings; freeze stops; open the route in Apple Maps or Google Maps.
- Customers: add customers and sites, or load demo data.
- Invoices: built from the visit log.
- Proof: tamper check and a shareable proof-of-service packet.
- Plans: Pro and Max price calculator.

**Known placeholders**
- Photo capture only logs that a photo was taken (no camera yet).
- No map geocoding: addresses added in the app have no coordinates, so they are left out of route order until coordinates exist. Demo data has coordinates.
- Drive times in the app are still the straight-line estimate. The Google server call and the live Apple ETAs are written (Apple) or specified (Google) but not wired in.
- No weather feed (snowfall is entered by hand), no sync, no accounts, no payments, no push notifications, no real StoreKit or web billing. The trial clock runs locally.

## Storm broadcast and client portal (built, not in the screens yet)
- **Core (`StormBroadcast`, `ServiceRequests`, `Portal`)**: plans a storm-start message for every client (expected snow as a range, whether service is expected, what it means for their bill by contract type, a private page link), with consent rules: no message without recorded consent, an opt-out always wins, quiet hours push non-urgent messages to morning, nothing is sent twice for the same storm, and each skipped client comes back with a reason. Clients can ask for service, urgent service (with a reason) or a skip; nothing changes the route until you accept, and an accepted urgent request moves that site to the top priority tier for that storm only.
- **Server (`server/portal.mjs`)**: the private client page (no login, 24-character random link, no scripts, strict security headers, same plain answer for wrong, old or malformed links), the owner's request inbox, and email sending through an email provider (the code is written for Resend's API and tested against a stand-in). The server stores no phone numbers or email addresses: only the page link, the address label, a status sentence and the requests; snapshots are deleted after 14 days and requests after 30.
- **Tested together**: the real Swift client was run against the real server: send the email, publish the page, the client submits an urgent request from the page, the owner imports it, accepts it, and the client's page shows the answer.
- **Not built yet**: the screens for it (send the storm message, the request inbox, collecting consent), real email sending with your own provider account, and text messages (they need carrier registration first).

## Apple Maps routing (default)
Drive times now come from **Apple Maps on the device** by default (free, no key, includes live traffic). Apple answers one origin and destination per request and slows heavy use down, so `SampledMatrixSource` measures only the legs that matter most (yard to every stop, then each stop to its 3 nearest neighbours, capped at 150 requests, 3 at a time with short pauses), scales the straight-line estimate for every other pair by how the measured legs compared, and stops asking and finishes with estimates if Apple stops answering. The Storm screen says how many legs were measured. Answers are cached in memory only, for 10 minutes (`CachedETASource`), so changing the weather sliders does not ask Apple again. Settings lets you pick Apple Maps, your own Google routing server, or the offline estimate.

**Apple's terms (read from the Apple Developer Program License Agreement, Attachment 6, version date not visible in what I read; I did not read the whole agreement):**
- §1.2 bars **MapKit JS on non-Apple hardware** from fleet management (including dispatch), asset tracking and enterprise route optimization. The sentence names MapKit JS; this app calls native MapKit on Apple devices. Because of that sentence, Apple Maps must **never be called from a server** (no Apple Maps Server API or MapKit JS in this project). This reading is mine, not a legal opinion, and an app for dispatching crews is close to what that sentence is about. **Ask Apple developer support or a lawyer before launch, and keep the Google or offline options as a fallback.**
- §2.5 allows Map Data to be kept only temporarily and limitedly, then deleted: hence memory-only 10-minute caching.
- §2.4 requires Apple map results shown on a map to be shown on an Apple map: the app hands off navigation to Apple or Google Maps and does not draw Apple results on another map.
- §2.6 bars charging fees solely for access to the Apple Maps Service. The Max plan includes the route planner, which is our own logic, but keep the pricing wording about features, not about maps.
- §2.7 lets Apple limit or revoke access at any time.

## How routing works
1. **Drive times** come from a `MatrixSource`: Google Routes API (traffic-aware, batch, through your own server) first, then the offline estimate if it fails. `GoogleRoutesMatrix` builds the request, splits big jobs into allowed-size blocks and reads the response. The Google key must stay on the server.
2. **Weather does not change routes.** Decision: routes are ordered by drive time only. The weather model (`ConditionsModel`, `SpeedCalibrator`) is still in the code and tested, but the app does not use it. Weather decides which sites need service (snowfall against each site's trigger depth), not how long a drive takes. Apple's live traffic already reflects slowdowns that show up in traffic data.
3. **Ordering** (`RouteOptimizer`): frozen first stops never move, priority tiers are strict (hospital before driveway), inside a tier nearest-next then 2-opt improvement (never longer than nearest-next). Deadlines are checked and late stops reported, not forced. Crews are assigned by sweeping around the depot into balanced groups.
4. **Live refresh**: Apple MapKit gives a live ETA per leg on the device (`MapKitETASource`, one leg per request, so only the next few legs via `LegRefiner`).
5. **Navigation**: the driver taps through to Apple Maps (next stop) or Google Maps (whole route in linked parts, about 9 waypoints each) for turn-by-turn.

**Limits and open questions**
- Neither Apple nor Google has snow-aware or plow-aware routing, and the weather factors are not validated yet.
- Strict priority tiers can add driving. The dispatcher can freeze stops and override.
- Google Maps Platform terms limit caching and showing its results beside a non-Google map. Read the current terms before relying on it. An open-source engine (Valhalla with VROOM) avoids that and the per-request cost, and fits behind the same `MatrixSource`.
- Cost check from research: Google traffic-aware matrices were about $10 per 1,000 elements, and a matrix grows with the square of the stops (about $6 for a 25-stop route). Cache and refresh only the next stops.
- **Routing server built** (`server/`, see its README): holds the Google key, caps cost per token per day, caches, splits large requests. The Swift client (`ProxyMatrixSource`) is built. Both are tested against a stand-in for Google, and the real Swift client was run against the real server (token check, matrix, outage fallback). **Not yet run against real Google**, not deployed, and not wired into the app screens. The Apple live-ETA code needs Xcode to compile.

## What to do next
See `SETUP.md`: steps for you (Mac and Xcode, accounts, Google, legal) and what to send me.

## Weather feed (National Weather Service)
`NWSClient` loads the free NWS forecast and winter alerts for the yard location (rounded to about 1 km; customer addresses are never sent). `NWSForecast.summary(from:to:)` turns it into storm total snow (inches) and other numbers for a time window. The Storm screen uses only the snowfall total, to fill in the snowfall slider that decides which sites reach their trigger depth.

## Use the server from the app
```swift
let planner = RoutePlanner(matrixSource: FallbackMatrixSource(
    primary: ProxyMatrixSource(baseURL: serverURL, token: tokenFromKeychain),
    secondary: ProviderMatrixSource()))   // offline estimate if the server is down
let plan = await planner.plan(stops: stops, start: depot, conditions: weather)
```

## Run the tests
```
swift test
```
(Needs the Swift 6 toolchain. On a Mac, Xcode 16 or later includes it.)

## Open in Xcode
1. File > New > Project > Multiplatform > App, named Ridgeline Ops.
2. File > Add Package Dependencies > Add Local, choose this folder, add `RidgelineUI` to the app target.
3. In the app's `@main` struct use `WindowGroup { RidgelineRootView() }` and import `RidgelineUI`.

## Next build steps
1. Open in Xcode, fix compile issues, run on a device.
2. Camera capture with background upload and retry.
3. Address geocoding (MapKit) so new sites get coordinates.
4. WeatherKit and NWS feed for snowfall and alerts.
5. Sync (PowerSync with Supabase) and accounts, then StoreKit and web billing for the 14-day trial.
6. Real drive times (Valhalla and VROOM, or a traffic API).
