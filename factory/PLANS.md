# Supperwise: plans and features (v2, 2026-11-12)
Prices are placeholders; the person sets the real ones in App Store Connect.
**Subscriptions only (monthly or yearly). No one-time purchases** (the person's decision, 2026-11-12).

**Superseded the same day: three plans again, through RevenueCat (the person asked for multiple levels).**
- **Entitlements:** `plus`, `family`, `supper_wise_pro` (Pro).
- **Products (live in RevenueCat project "Supper Wise", Test Store):** `plus_monthly` $4.99, `plus_yearly` $34.99, `family_monthly` $7.99, `family_yearly` $54.99, and Pro is the original `monthly` $9.99 and `yearly` $79.99.
- **Offering:** `default` (current) holds all 6 packages.
- **Attachment:** each product is attached to its own entitlement and every lower one.

**Earlier the same day: one plan through RevenueCat.**
- **Entitlement:** `supper_wise_pro` unlocks every feature below.
- **Products:** `monthly` and `yearly`.
- **Screens:** RevenueCat Paywall and Customer Center.

The Plus / Family / Pro split below is kept in the code so plans can be split later, by adding `plus` or `family` entitlements in RevenueCat.
In the Apple setup: one subscription group with three levels (Pro > Family > Plus), so people can upgrade and downgrade. Monthly and yearly for each, with a 7-day free trial on yearly. Family can turn on Family Sharing (up to 6 people).

| Feature | Free | Plus $4.99/mo · $34.99/yr | Family $7.99/mo · $54.99/yr | Pro $11.99/mo · $79.99/yr | What it costs to run |
|---|---|---|---|---|---|
| First week's plan and list, kept | ✓ | ✓ | ✓ | ✓ | none |
| New week every Sunday, swaps, whole-pack pricing, pantry, per-person rules | | ✓ | ✓ | ✓ | none (on device) |
| Cook mode with timers, dinner reminders | | ✓ | ✓ | ✓ | none |
| Holiday menus: guests and vegetarians, USDA turkey and ham times, a one-oven cooking timeline, one priced list (Thanksgiving, Christmas) | | ✓ | ✓ | ✓ | none |
| First foods: 100+ foods with how to serve by age, allergen tracker, food log with reactions, tonight's dinner adapted for the baby | | | ✓ | ✓ | none |
| Lunchbox planner: nut-free packed lunches for school days, last night's leftovers become tomorrow's lunch, priced on the same list | | | ✓ | ✓ | none |
| Save recipes from TikTok, Instagram or a link | | 10/month | unlimited | unlimited | low: link parsing, an AI model for messy captions |
| Product scanner: calories, added sugar, sodium, ingredients, 1–100 health score, household conflicts | | | ✓ | ✓ | none: Open Food Facts (free, ODbL; attribution required) |
| Eating out: restaurant dishes scored 1–100, household conflicts | | | ✓ | ✓ | menu data: chains publish nutrition by law; a licensed nutrition API costs money (to price) |
| Leftovers for lunch | | | ✓ | ✓ | none |
| Receipt check: plan vs paid, estimates learn your store | | | ✓ | ✓ | low: on-device text recognition (Vision) |
| Weekly recap | | | ✓ | ✓ | none |
| One list shared with up to 6 people | | | ✓ | ✓ | low: CloudKit sharing |
| Fridge scan: what can I cook tonight? | | | | ✓ (60 scans/mo) | **per scan:** an AI vision model; hence Pro and the cap |

## The health score (1–100)
- **Nutrient density per calorie:** added sugar, sodium and saturated fat lose points when they're above their share of a 2,000-calorie day (FDA daily values). Protein and fibre add points, and low protein or fibre for the calories loses points.
- **Processing:** fried, refined and ultra-processed foods lose points, as do artificial colours and meals over 600 calories.
- **Bands:** 70+ good, 40–69 OK, under 40 poor.
- **What it is:** a guide, not medical advice. It must be described that way in the app and in the listing (App Review 1.4.1).
- **Formula:** in preview/template.html, `healthScore`.

## Why these tiers
- **Plus is the core habit:** planning every week. Its price is under most competitors' monthly price.
- **Family is where retention lives:** the scanner and restaurant scores bring daily use beyond dinner, and sharing and receipts deepen lock-in. It's expected to be the most-bought tier.
- **Pro carries the only feature with a real cost per use** (the AI fridge scan), priced and capped so it can't lose money.

## App Review notes for these features
- **Health claims:** none medical. Scores and flags are informational, with sources shown (FDA daily values, Open Food Facts).
- **Fridge scan and recipe import send images and text to an AI provider.** That needs a disclosure and consent before the first use (5.1.2(i)), and a privacy-label update.
- **Open Food Facts:** credit it in the app (ODbL).

## Status (Swift app, 2026-11-12)
Built in the iPhone app, not yet compiled. It needs a Mac, and a separate review found no compile errors after fixes.
- **Plans:** three tiers in StoreKit (6 products, one group), locked features with a plan picker, test products in Supperwise.storekit.
- **Product scanner:** VisionKit barcode camera plus typed barcodes, Open Food Facts lookup, 1–100 score, household conflicts.
- **Eating out:** dishes entered from posted nutrition, scored and checked, grouped by restaurant.
- **Receipt check:** on-device text recognition finds the total; you confirm it; estimates can adjust (capped at ±25%).
- **Fridge scan:** on-device image classification suggests foods; you confirm; dinners are ranked by what you have.
- **Saving recipes from websites:** schema.org Recipe data, whole-word ingredient matching. Saved recipes are never auto-planned.
- **Leftovers, cook mode, weekly recap.**
- **Not built yet:** TikTok and Instagram saving (needs a paid AI service), the shared family list (iCloud sharing). Neither is listed in the app's paywall.
- **Tests:** SupperwiseTests/FeatureTests.swift (score bands, conflicts, leftovers, store adjustment, receipt total, timers, Open Food Facts parsing, recipe-link parsing, plan mapping).

## RevenueCat project "Supper Wise" (set up through the API, 2026-11-12)
- **Apps:**
  - Test Store: used by Debug builds.
  - "Supperwise (App Store)", bundle `com.supperwise.app`: used by Release builds. App Store Connect isn't connected yet.
- **Entitlements:** `plus`, `family`, `supper_wise_pro`. Higher plans' products are attached to the lower entitlements too.
- **Offering:** `default` (current), with 6 packages.
- **Paywall:** created and published on `default`, using RevenueCat's default template. Customise it in Paywalls.
- **Test Store prices currently set:**
  - Plus: $4.99 a month, $34.99 a year.
  - Family: $7.99 a month, $54.99 a year.
  - Pro: $9.99 a month, $79.99 a year.
- **Recommended prices** (approved; still to apply, because the API can't change a price once it's set):
  - Plus: $5.99 a month, $29.99 a year.
  - Family: $9.99 a month, $49.99 a year.
  - Pro: $14.99 a month, $79.99 a year.
