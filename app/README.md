# Supperwise (iOS app)

A weekly dinner planner. It builds a week of dinners for your household, priced as one grocery list at your kind of store, by the whole pack you actually buy. SwiftUI, iOS 17+, iPhone, StoreKit 2 subscriptions.

## Run it on your Mac

1. Install Xcode 26 from the Mac App Store. Xcode 16 can run it in the simulator, but App Store uploads need the iOS 26 SDK (since April 28, 2026).
2. Open `Supperwise.xcodeproj`.
3. Signing: select the **Supperwise** target, open **Signing & Capabilities**, and pick your Team. If Xcode says the bundle id is taken, change `com.supperwise.app` to something of your own, such as `com.yourname.supperwise`. If you change it, change the product ids in `Supperwise/Store/Subscriptions.swift` and `Supperwise.storekit` to match.
4. Pick an iPhone simulator, such as iPhone 17 Pro, and press **⌘R**.
5. Run the tests with **⌘U**. They check the planner rules: allergies never served, everyone gets a plate, the budget is kept, prices are by the whole pack.

**Subscriptions (RevenueCat).**
- **Setup:** purchases go through the RevenueCat SDK (Swift Package `purchases-ios-spm`, products `RevenueCat` and `RevenueCatUI`, which Xcode fetches on first open).
- **Key:** `Supperwise/Store/Subscriptions.swift` holds the SDK key. It's currently a **Test Store** key, so purchases are simulated and nothing is charged.
- **Entitlement:** `supper_wise_pro` unlocks every paid feature.
- **Paywall:** designed in the RevenueCat dashboard (Paywalls). A default template shows until you publish one.
- **Customer Center:** handles manage and cancel requests, under Settings › Manage subscription.
- **Before release:** swap the `test_` key for your project's Apple key (`appl_…`), and connect App Store Connect in RevenueCat.

## What to check (step 3 of the factory)

Walk the first run and capture every screen into `launch/captures/iphone/` (the simulator's **⌘S** saves a screenshot):

1. Store step → household step → **first week** (the plan before the paywall)
2. Keep my free week → **Week** tab (today's title card) → **Swap** (the plate spins, the price rolls) → **Start cooking** (recipe) → **I cooked it**
3. **Groceries** (total, whole packs, leftover notes, "How we price this")
4. **Kitchen** (tick something and watch the bill drop)
5. **Next week** (Plan) → Plan next week → the paywall sheet → subscribe with the test StoreKit config
6. Settings, and the same screens in dark mode (**Features › Toggle Appearance** in the simulator)

## Before App Store submission

- **Recipe photos**: the images in `Assets.xcassets/dish_*` are Unsplash stand-ins. Shoot your own (one plate, overhead, daylight) and replace them. Recipes without a photo show a designed coloured plate.
- **Privacy policy and support**: Settings and the paywall link to `supperwise.app/privacy` and `support@supperwise.app`. Point those at pages you actually own.
- **In-App Purchases**: create the two auto-renewable subscriptions in App Store Connect, in one group, with the same ids: `com.supperwise.app.yearly` (7-day free trial) and `com.supperwise.app.monthly`. The prices in `Supperwise.storekit` ($29.99 a year, $7.99 a month) are placeholders. You set the real ones.
- **Prices are estimates**: reference prices live in `Supperwise/Resources/ingredients.json`, regenerated from `tools/make_catalog.py`. The app says so in "How we price this".

## Layout

```
Supperwise/
  App/          entry point, root view
  Model/        catalog, planner, whole-pack pricing, app state (JSON in Application Support)
  Store/        StoreKit 2
  Theme/        weekday colours, Instrument Serif, cut-paper shapes, plate
  Views/        Today, Recipe, Groceries, Kitchen, Plan, Settings, onboarding and paywall
  Resources/    recipes.json, ingredients.json, font (OFL), privacy manifest
SupperwiseTests/  planner and pricing tests
tools/          scripts that generate the catalog and the asset catalog
                (run make_catalog.py, then make_holiday.py: the holiday script adds its ingredients to the catalog)
```

The design these screens follow is in `../design/` (mockups, DIRECTION.md, CRITIQUE.md).
