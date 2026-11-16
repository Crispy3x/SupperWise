# Ridgeline Ops

Snow-first crew and route software for iPhone, iPad and Mac. See `PLAN.md` for the market research, plans and pricing, and `research/` for the source notes. `research/INTERVIEW-SCRIPT.md` is the owner interview script.

## What exists so far

**Core logic (`Sources/RidgelineCore`)**: platform-neutral Swift, compiled and tested on Linux. 59 unit tests, all passing.
- `Pricing`, `Entitlements`: Pro and Max per-crew prices, annual 20% off, 14-day trial (all features unlocked), feature gating, read-only after trial.
- `SnowBilling`: per-push, seasonal, per-inch, hybrid (base, cap, overage) and time-and-materials. One invoice line per storm, skipped visits never billed, per-contract push counting (default one push per storm).
- `Storm`: trigger depth per site, near-trigger warnings.
- `RouteSequencer`, `Geo`: dispatcher-controlled ordering: strict priority tiers, nearest-next within a tier, first N stops frozen, storm speed factor, ETAs. Uses an offline straight-line drive-time estimate behind a `DriveTimeProvider` protocol, so a traffic-aware provider (Valhalla, Google, Mapbox) can be swapped in.
- `Scheduling` (`RouteBook`): bulk move routes to another crew or weekday, swap crews, move sites between routes.
- `VisitLog`, `DisputePacket`, `SHA256`: hash-chained, tamper-evident proof-of-service log (arrival, geofence, photos with hashes, weather note, salt) and a shareable text packet. Pure-Swift SHA-256 checked against reference vectors.
- `TimeClock`: shifts and per-job timers, audited corrections, labor cost per site, missed punch-out detection, geofence "start the job?" prompt, 20-region monitoring cap.
- `Notices`: customer message templates (scheduled, en route, delayed, skipped, complete). Completion notices require an after photo.
- `SubPay`: percent of job, hourly, per-push, per-lot, with "no photo, no pay".
- `Persistence` (`FileStore`): offline-first single-file store with atomic writes.

**App screens (`Sources/RidgelineUI`)**: SwiftUI for iPhone, iPad and Mac. **Written but never compiled or run**, because SwiftUI only builds on Apple platforms; expect small fixes on first build in Xcode.
- Crew: log a visit (completed or skipped with a reason), see standing site instructions, preview the customer message.
- Storm: set snowfall, see sites at trigger in planned order with ETAs, freeze stops, adjust storm speed.
- Customers: add customers and sites, or load demo data.
- Invoices: built from the visit log.
- Proof: tamper check and a shareable proof-of-service packet.
- Plans: Pro and Max price calculator.

**Known placeholders**
- Photo capture only logs that a photo was taken (no camera yet).
- No map geocoding: addresses added in the app have no coordinates, so they are left out of route order until coordinates exist. Demo data has coordinates.
- Drive times are straight-line estimates, not real roads or traffic.
- No weather feed (snowfall is entered by hand), no sync, no accounts, no payments, no push notifications, no real StoreKit or web billing. The trial clock runs locally.

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
