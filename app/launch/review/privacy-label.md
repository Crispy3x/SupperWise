# Privacy label (updated 2026-11-13: accounts, community recipes, food scan)

App Store Connect › App Privacy. Meal plans and household data stay on the device. Fill in:

| Data type | Collected by | Linked to the person | Tracking | Purpose |
|---|---|---|---|---|
| Contact info › Email address | Supperwise (Supabase), only if they sign in | Yes | No | App functionality (sign-in) |
| User content › Photos or videos | Supperwise: shared recipe photos; food-scan photos (sent for analysis, not stored) | Yes (shared recipes); food-scan photos not stored | No | App functionality |
| User content › Other user content | Supperwise: shared recipes, reports | Yes | No | App functionality |
| Identifiers › User ID | Supperwise account ID; RevenueCat anonymous ID | Yes | No | App functionality |
| Purchases › Purchase history | RevenueCat | Yes (anonymous RevenueCat ID) | No | App functionality, analytics |
| Usage data › Product interaction | Supperwise: monthly food-scan count | Yes | No | App functionality (limits) |

**Not collected:** name (the first name on a shared recipe is user content they type), location, health records, contacts, browsing, diagnostics, ads. **Tracking: No.** No ATT prompt.

**Other notes:**
- Third-party AI: food-scan photos go to Anthropic. The app asks permission before the first scan (guideline 5.1.2(i)).
- Account deletion is in the app (Settings › Account, or Community › My shared recipes).
- User-generated content (guideline 1.2): recipes are approved before publishing, anyone can report one, and reports are reviewed within 24 hours.
