# Review audit: Supperwise

Scanned 2026-11-11 20:56 · native · com.supperwise.app · version 1.0 (1) · iPhone

**0 blockers · 0 risks · 1 to check.** Static evidence from the code. Each finding gets confirmed or cleared in the reviewer walk (SKILL.md, step 1).

## CHECK · The app advertises a free trial

Guideline 3.1.2 · purchases · `trial-wording`

- `Supperwise/Views/Onboarding/FirstWeekView.swift:91  "No trial"`
- `Supperwise/Views/Onboarding/FirstWeekView.swift:129  "Free for 7 days, then \\(y.displayPrice) a year, charged to your Apple ID and renewing automatically. Cancel in Settings "`

**Why:** A trial must be shown with what happens after it: the price and period that start when it ends, at least as prominent as the trial itself. The trial must exist as an introductory offer on that exact product in App Store Connect, and only eligible people may be shown it.

**Fix:** Read trial length and eligibility from StoreKit (isEligibleForIntroOffer / RevenueCat checkTrialOrIntroDiscountEligibility), show "then <price>/<period>" next to it, and never promise a trial the product doesn't have.

**Status:** open

## What the app ships

- SDKs: none recognised
- Permissions declared: none
- Accounts: no · Purchases: yes · Privacy manifests: 1

## Decisions (2026-11-11)
- **CHECK 3.1.2, the app advertises a free trial: cleared.**
  - The trial is real. It's the yearly product's introductory offer (P1W, free) in Supperwise.storekit, to be configured on the same product in App Store Connect.
  - The paywall shows it only when `isEligibleForIntroOffer` is true. It states the length (7 days), the price after it (from StoreKit), "renewing automatically", and how to cancel.
  - The billed amount is the most prominent price on each option ($29.99/yr, $7.99/mo). The per-month figure is secondary text.

## Reviewer walk (code read; no simulator in this session)
1. **Launch:** works offline. Only StoreKit uses the network, and it has an error state ("Prices couldn't load…"). No debug-only paths.
2. **Onboarding:** no account exists. The core feature (a week's plan plus grocery list) is reached and kept without paying.
3. **Permissions:** notifications only, asked only when the person turns on the dinner reminder in Settings. No custom pre-prompt. Everything else works without it. No other permissions.
4. **Sign-in:** none, so 4.8 doesn't apply.
5. **Paywall:**
   - Prices come from StoreKit. Name, length and what's included are shown, plus "renews automatically".
   - Terms (Apple EULA) and Privacy links. Restore is on the paywall and in Settings.
   - Can be closed: "Keep my free week", or "Not now" on the sheet.
   - **Fixed:** removed the "we'll remind you 2 days before the trial ends" promise, which the app doesn't keep.
   - **Fixed:** the billed amount is now the most prominent price.
6. **Purchase:** both products must exist in App Store Connect, be Ready to Submit, and be attached to the version (connect-checklist.md).
7. **Core feature:** works for a fresh install with no data. Needs no hardware or second device.
8. **Content:** 19 real recipes, no placeholders, no user-generated content.
   - **Fixed:** the allergy copy no longer promises allergens are "never served". It says dishes with them are left out, and to always check labels.
9. **Settings:**
   - **Needs the person:** the privacy policy link (`supperwise.app/privacy`) and support (`rrizzo574@gmail.com`) are placeholders.
   - There's no account to delete. "Erase all my data" removes the on-device data and says it doesn't cancel a subscription.
10. **Third-party AI:** none. No data leaves the device.
11. **iPad:** iPhone only (TARGETED_DEVICE_FAMILY = 1).
12. **Links out:** Apple EULA, privacy, mailto. No external payment links.
