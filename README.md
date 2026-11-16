# Ridgeline Ops

Snow-first crew and route software for iPhone, iPad and Mac. See `PLAN.md` for the market research, plans and pricing, and `research/` for the source notes. `research/INTERVIEW-SCRIPT.md` is the owner interview script.

## What exists so far
- `Sources/RidgelineCore`: platform-neutral Swift logic (no UI), compiled and tested on Linux and Apple platforms.
  - `Pricing`: Pro and Max plans, per-crew pricing, annual 20% off, 14-day trial constant.
  - `SnowBilling`: per-push, seasonal, per-inch, hybrid (base plus cap and overage) and time-and-materials billing. One invoice line per storm, skipped visits are never billed.
  - `Money`: integer-cent money type.
- `Models`: Customer, Site (priority, trigger depth, crew instructions) and SnowContract, all Codable.
- `Sources/RidgelineUI`: SwiftUI shell (`RidgelineRootView`) with a plan/price calculator and a billing preview. **Not compiled or run yet**: it only builds on Apple platforms, so on Linux the files compile to nothing. Expect small fixes when first opened in Xcode.
- `Tests/RidgelineCoreTests`: 21 unit tests.

## Decision: how pushes are counted
Each per-push or hybrid contract has a `counting` setting. Default is `perStorm` (one push per storm however many times the crew returns, which avoids billing surprises). Set `perVisit` to bill every return trip.

## Run the tests
```
swift test
```
(Needs the Swift 6 toolchain. On a Mac, Xcode 16 or later includes it.)

## Open in Xcode
1. File > New > Project > Multiplatform > App, named Ridgeline Ops.
2. File > Add Package Dependencies > Add Local, choose this folder, add `RidgelineUI` to the app target.
3. In the app's `@main` struct use `WindowGroup { RidgelineRootView() }` and import `RidgelineUI`.

## Not built yet
Offline sync, scheduling, the crew time clock, proof-of-service log, customer notifications and routing. These need Xcode on a Mac to build and run.
