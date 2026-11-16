# Ridgeline Ops

Snow-first crew and route software for iPhone, iPad and Mac. See `PLAN.md` for the market research, plans and pricing, and `research/` for the source notes. `research/INTERVIEW-SCRIPT.md` is the owner interview script.

## What exists so far

**Core logic (`Sources/RidgelineCore`)**: platform-neutral Swift, compiled and tested on Linux. 91 unit tests, all passing.
- `Pricing`, `Entitlements`: Pro and Max per-crew prices, annual 20% off, 14-day trial (all features unlocked), feature gating, read-only after trial.
- `SnowBilling`: per-push, seasonal, per-inch, hybrid (base, cap, overage) and time-and-materials. One invoice line per storm, skipped visits never billed, per-contract push counting (default one push per storm).
- `Storm`: trigger depth per site, near-trigger warnings.
- **Routing engine** (`RouteSequencer`, `RouteOptimizer`, `Conditions`, `DriveTimeMatrix`, `GoogleRoutes`, `NavigationLinks`): see "How routing works" below.
- `Scheduling` (`RouteBook`): bulk move routes to another crew or weekday, swap crews, move sites between routes.
- `VisitLog`, `DisputePacket`, `SHA256`: hash-chained, tamper-evident proof-of-service log (arrival, geofence, photos with hashes, weather note, salt) and a shareable text packet. Pure-Swift SHA-256 checked against reference vectors.
- `TimeClock`: shifts and per-job timers, audited corrections, labor cost per site, missed punch-out detection, geofence "start the job?" prompt, 20-region monitoring cap.
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

## How routing works
1. **Drive times** come from a `MatrixSource`: Google Routes API (traffic-aware, batch, through your own server) first, then the offline estimate if it fails. `GoogleRoutesMatrix` builds the request, splits big jobs into allowed-size blocks and reads the response. The Google key must stay on the server.
2. **Weather layer** (`ConditionsModel`): snow on the ground, snowfall rate, temperature, wind and visibility become a driving-speed factor and a time-per-site factor. Google and Apple drive times know traffic but have no snow logic, so this sits on top. The numbers are starting guesses; `SpeedCalibrator` replaces them with what your trucks actually did (median of expected vs actual drive time from the visit log).
3. **Ordering** (`RouteOptimizer`): frozen first stops never move, priority tiers are strict (hospital before driveway), inside a tier nearest-next then 2-opt improvement (never longer than nearest-next). Deadlines are checked and late stops reported, not forced. Crews are assigned by sweeping around the depot into balanced groups.
4. **Live refresh**: Apple MapKit gives a live ETA per leg on the device (`MapKitETASource`, one leg per request, so only the next few legs via `LegRefiner`).
5. **Navigation**: the driver taps through to Apple Maps (next stop) or Google Maps (whole route in linked parts, about 9 waypoints each) for turn-by-turn.

**Limits and open questions**
- Neither Apple nor Google has snow-aware or plow-aware routing, and the weather factors are not validated yet.
- Strict priority tiers can add driving. The dispatcher can freeze stops and override.
- Google Maps Platform terms limit caching and showing its results beside a non-Google map. Read the current terms before relying on it. An open-source engine (Valhalla with VROOM) avoids that and the per-request cost, and fits behind the same `MatrixSource`.
- Cost check from research: Google traffic-aware matrices were about $10 per 1,000 elements, and a matrix grows with the square of the stops (about $6 for a 25-stop route). Cache and refresh only the next stops.
- **Routing server built** (`server/`, see its README): holds the Google key, caps cost per token per day, caches, splits large requests. The Swift client (`ProxyMatrixSource`) is built. Both are tested against a stand-in for Google, and the real Swift client was run against the real server (token check, matrix, outage fallback). **Not yet run against real Google**, not deployed, and not wired into the app screens. The Apple live-ETA code needs Xcode to compile.

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
