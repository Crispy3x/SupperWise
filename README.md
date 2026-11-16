# Ridgeline Ops

Snow-first crew and route software for iPhone, iPad and Mac. See `PLAN.md` for the market research, plans and pricing, and `research/` for the source notes. `research/INTERVIEW-SCRIPT.md` is the owner interview script.

## What exists so far
- `Sources/RidgelineCore`: platform-neutral Swift logic (no UI), compiled and tested on Linux and Apple platforms.
  - `Pricing`: Pro and Max plans, per-crew pricing, annual 20% off, 14-day trial constant.
  - `SnowBilling`: per-push, seasonal, per-inch, hybrid (base plus cap and overage) and time-and-materials billing. One invoice line per storm, skipped visits are never billed.
  - `Money`: integer-cent money type.
- `Tests/RidgelineCoreTests`: 15 unit tests.

## Run the tests
```
swift test
```
(Needs the Swift 6 toolchain. On a Mac, Xcode 16 or later includes it.)

## Not built yet
SwiftUI app targets (iPhone, iPad, Mac), offline sync, scheduling, the crew time clock, proof-of-service log, customer notifications and routing. These need Xcode on a Mac to build and run.
