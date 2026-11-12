# Privacy label (updated for RevenueCat, 2026-11-12)

App Store Connect › App Privacy. Supperwise itself stores everything on the device. **RevenueCat**, the subscription service, receives purchase data, so the label must list it:

| Data type | Collected by | Linked to the person | Used for tracking | Purpose |
|---|---|---|---|---|
| Purchases (purchase history) | RevenueCat | Yes, to an anonymous RevenueCat app user ID | No | App functionality (unlocking the subscription), analytics |
| Identifiers (user ID) | RevenueCat (anonymous ID it creates) | Yes | No | App functionality |

**What isn't collected:**
- No other data: no accounts, no names, no email, no location, no analytics SDK, no ads.
- **Tracking: No.** No ATT prompt.

**Other notes:**
- The RevenueCat SDK ships its own privacy manifest, which Xcode merges with the app's.
- Product barcodes go to Open Food Facts, but they aren't personal data.
- Check RevenueCat's current guidance before you submit: revenuecat.com/docs, "Apple App Privacy".
