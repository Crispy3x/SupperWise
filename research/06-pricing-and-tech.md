# 06 - Pricing, unit economics and tech architecture

Researched 2026-11-16. Legend: **[E]** = evidence from a web source (URL given; mostly third-party aggregators, so verify on vendor pages before quoting publicly). **[I]** = inference / assumption / from training memory, not verified this session.

---
## 1. Competitor pricing

### 1.1 Price points
| Product | Entry / mid / top | Extra users | Notes |
|---|---|---|---|
| Jobber | Core ~$49, Connect ~$139, Grow ~$199, Plus ~$499-599 (monthly billing, 1 user on Core/Connect/Grow). Annual: ~$29 / $99 / $149 / $399 [E: getonecrew.com/post/jobber-pricing, activepieces.com/blog/jobber-pricing-2026-plans-add-ons-and-total-cost] | $29/user/mo on every plan [E, same sources] | Core went $39->$49, Connect $119->$139 in 2026 [E: costbench.com/changelog/jobber-price-increase-2026-02-3/]. Sources conflict on exact tiers. Card 2.9%+30c, ACH 1%, Tap to Pay 2.7%+30c [E: hackceleration/getonecrew summaries; paymentproviders.io/compare/stripe-vs-jobber-payments] |
| Housecall Pro | Basic $79 (1 user), Essentials $189 (5 users), MAX $329 (8 users) monthly; annual ~$59 / $149 / $299 [E: housecallpro.com/llm-info/, contractortoolstack.com/software/housecall-pro/pricing/] | Conflicting: $35 (old) vs $100 (Essentials) / $75 (MAX) [E, unresolved] | Card ~2.59%-3.49% depending on in-person/online/card-on-file; ACH 1%; Instapay +1% [E: helcim.com/extensions/housecallpro/, help.housecallpro.com] |
| Workiz | Stopped publishing prices in 2026 (Request Pricing). Last published ~$225 / $275 / $325 per month, first 5 users included; extra users ~$55-65 [E: fieldproxy.ai/fsm-software-pricing/workiz, fieldservicepicker.pages.dev] | ~$55-65 | Low confidence |
| Service Fusion | ~$208/mo annual, $245 monthly, unlimited users [E: fieldservicesoftware.io/comparisons/service-fusion-vs-workiz/]; reportedly stopped publishing in July 2026 | Unlimited users | Low confidence |
| FieldPulse | Quote-only; third-party estimates ~$89/mo up to ~$65/user [E: contractortoolstack.com/compare/workiz-vs-fieldpulse/] | n/a | Very low confidence |
| LMN (landscape) | Starter ~$297/mo, Professional ~$598-648/mo [E: getapp.com/lawn-care-software/a/lmn, costbench.com/software/lawn-care-software/]; GetApp frames per user, other sources say flat/unlimited users | Disputed | Landscape estimating/costing focused |
| Aspire | Custom/quote only [E: softwareadvice.com/field-service/aspire-profile/] | n/a | Targets bigger landscape firms |
| Route4Me | Pricing hidden since early 2026; free trial reportedly removed [E: shipday.com/post/7-best-route4me-alternatives-in-2026] | n/a | |
| OptimoRoute | Lite $35.10, Pro $44.10 per driver/mo annual; ~$39 / $49 monthly [E: upperinc.com/blog/optimoroute-pricing/] | per driver | Routing only, no CRM/invoicing |
| Workyard | Time tracking $50/mo company fee + $8/user ($6 annual); Workforce tier $16/user ($13 annual) [E: help.workyard.com/en/articles/4800717-how-much-is-workyard-going-to-cost] | per user | Time clock/GPS only |

### 1.2 Where customers feel gouged
- **Per-seat creep and annual increases** [E: hackceleration.com/labs/switch/jobber; getonecrew.com/post/jobber-reviews]. "Cheap at 2 users, not at 12." Note: those sources are mostly competitors' marketing, so treat as directional. I did not find Reddit threads directly.
- **Stacked add-ons plus card fees** (marketing tools, payments, SMS) lift the real bill well above plan price [E: pipelineon.com/blog/jobber-pricing/].
- **Opaque "contact sales" pricing** (Workiz, FieldPulse, Aspire, Route4Me, increasingly Service Fusion) [E above].
- **Seasonal mismatch [I]**: snow contractors earn in ~5 months but pay 12; none of the researched vendors offered season/pause pricing in the results. Worth validating, but a plausible wedge.

### 1.3 The pricing gap [I, derived from the table]
- **Solo / 1-3 trucks**: Jobber Core ($49, one user) is cheap but a seat costs $29 each, and Core is thin. HCP Basic is $79. Real all-in cost for a 3-person crew on Jobber Connect: ~$139+2x29 = ~$197/mo. Gap: a $29-49 plan with unlimited office users, routing, time clock and payments included.
- **5-20 crews**: Jobber Grow w/ 15 users ~$499; HCP MAX $329+extras; LMN $600+. Gap: flat per-crew pricing (a crew = one truck/device), with the owner/dispatcher/office seats free, plus snow-specific features (triggers by snowfall, per-push/seasonal contracts, site logs/proof of service) that the generalist tools lack [I; verify feature gap in the competitor-features research file].
- Route optimizers charge ~$35-49 per driver per month for routing alone; bundling routing into a $30-50/crew plan is a strong "more for the price" story.

---
## 2. Recommended pricing and unit economics

### 2.1 Structure (price by **crew = one active field device**; unlimited office/dispatch/owner seats on iPad/Mac)
| Tier | Included | Monthly | Annual (2 months free, ~17% off) |
|---|---|---|---|
| Solo | 1 crew, 1 office login | $39 | $390/yr ($32.50/mo) |
| Crew | 3 crews, unlimited office users, +$25/extra crew | $99 | $990/yr |
| Business | 10 crews, +$18/extra crew, roles/permissions, QuickBooks sync, API | $249 | $2,490/yr |
| Fleet | 20+ crews | custom, ~$15-18/crew | custom |
All with 14-day free trial, no card up front on web. Positioning vs competitors (3 crews: ~$99 vs ~$197 Jobber Connect w/ 3 seats [I]).

Add-ons (all optional, metered where COGS is metered):
- SMS/email bundle: 200 SMS included on Solo, 500 Crew, 2,000 Business; overage ~$0.03/SMS (cost ~$0.01-0.012 [I]).
- Marketing module (review requests, email campaigns, seasonal renewal blasts): +$19-39/mo.
- Advanced routing (multi-depot, time windows, re-optimize on weather): +$5/crew.
- Seasonal "pause": allow a down-tier to Solo-price Apr-Oct for snow-only customers. Churn-reducer [I].

Payments take-rate: pass through the processor's rate plus a ~0.3% platform fee via Stripe Connect (e.g. ~2.9% + 30c online, ~2.7% in person via Tap to Pay, ACH 0.8-1% capped) - stay at or below the 2.9%+30c / 1% ACH that Jobber advertises [E above]. Stripe's exact Connect/Terminal fee schedule was NOT verified this session [I]; confirm with Stripe.

### 2.2 Unit economics (per account per month; **all COGS figures are assumptions [I]** unless noted)
COGS assumptions per crew: hosting + sync (Supabase/PowerSync, storage, photos) $1.50; maps/routing $1.00 (MapKit is free to use on-device; own VRP solver on cheap server; Google Route Optimization is billed per shipment, rates not verified [E: developers.google.com/maps/documentation/route-optimization/usage-and-billing]); SMS 100 msgs/crew-month... modeled below as totals; email ~$0.30 / $1 / $3; support $2 / $6 / $15 per account. SMS cost ~$0.012 each incl. carrier fees [I].

| | Solo $39 | Crew $99 | Business $249 |
|---|---|---|---|
| Hosting+sync | 1.5 | 4.5 | 15.0 |
| Maps/routing | 1.0 | 3.0 | 10.0 |
| SMS (120 / 400 / 1,500 msgs) | 1.4 | 4.8 | 18.0 |
| Email | 0.3 | 1.0 | 3.0 |
| Support | 2.0 | 6.0 | 15.0 |
| **Subtotal ex-billing** | **6.2** | **19.3** | **61.0** |
| Billing via App Store @15% (Small Business Program) | 5.85 | 14.85 | 37.35 |
| **Gross margin, StoreKit 15%** | **$26.95 = 69%** | **$64.85 = 66%** | **$150.65 = 61%** |
| Billing via web (Stripe ~3.5% incl. Billing fee [I]) | 1.37 | 3.47 | 8.72 |
| **Gross margin, web billing** | **$31.43 = 81%** | **$76.23 = 77%** | **$179.28 = 72%** |
Annual plans at 17% off: Solo web ~$32.50 -> ~$25.1 GM (77%); StoreKit ~$21.4 (66%).
Payments revenue (not in the table): e.g. a Crew-tier customer processing $15k/mo x 0.3% = ~$45/mo of extra gross margin [I]. Treat as upside; payments attach rate is uncertain.
Standard (30%) rate would cut StoreKit margins by another 15 points; stay under the $1M/yr Small Business Program threshold or push web billing.

### 2.3 Apple fees and billing channel
- Small Business Program: 15% commission for developers under $1M in annual proceeds; standard 30%, dropping to 15% after a subscriber's first year [I, from Apple's public program terms; corroborated indirectly in E: macrumors.com/2026/08/13/app-store-fees-apple-link-outs/].
- US link-outs: after the April 30, 2025 Epic v. Apple ruling, Apple cannot charge commission on purchases through external links in US apps; in August 2026 Apple filed a proposal for 15% (standard) / 5% (Small Business) on link-outs, with subscription rates of 15% year one and 10% after, **not yet court-approved** [E: macrumors.com/2026/08/13/app-store-fees-apple-link-outs/; subscriptioninsider.com/blog/apple-proposes-15-year-one-link-out-fee-10-on-subscription-renewals]. Risk: today's free link-out advantage may shrink to ~5-15%, which is still similar to or below the IAP rate. Re-check before launch.
- Recommendation: **web-first billing (Stripe Billing + Checkout) with the app as a login client** (the multiplatform/B2B pattern [I; confirm against App Review Guidelines 3.1.3]), AND offer StoreKit subscriptions as a convenience path for solo users who want one-tap in-app purchase. The 14-day trial can be a StoreKit introductory offer (free, 2-week duration is supported [I, verify in App Store Connect]); on web use a Stripe trial.
- RevenueCat: unifies StoreKit and Stripe entitlements and handles receipts/webhooks; free until a monthly tracked-revenue threshold, then ~1% [I, verify on revenuecat.com/pricing]. Sensible for a solo dev to avoid building receipt validation.
- Caveat: don't dark-pattern the link-out; App Review requires compliant link entitlement/disclosure in some storefronts [I].

---
## 3. Tech architecture

### 3.1 Recommended stack
- **UI**: SwiftUI multiplatform target (iOS, iPadOS, macOS) with shared Swift package for models, sync and business logic; Mac gets sidebar/table-heavy dispatch views; MapKit for maps.
- **Local DB**: SQLite via **GRDB** or PowerSync's embedded SQLite (more control than SwiftData for sync conflict handling and queries) [I].
- **Sync**: **PowerSync + Supabase Postgres**. PowerSync has a native Swift SDK for offline-first iOS/macOS with an embedded SQLite synced to Postgres, local-first writes queued to your backend [E: powersync.com, docs referenced in search; supabase/PowerSync integration: powersync.com/blog/bringing-offline-first-to-supabase]. Supabase Pro listed at ~$25/mo and PowerSync Basic from ~$49/mo by aggregators, conflicting [E: toolradar.com/tools/powersync]; verify.
- **Backend**: Supabase (Postgres, Auth with RLS for multi-tenant, Storage for photos, Edge Functions for Stripe/Twilio webhooks, APNs push trigger). Stripe Connect for payments, Twilio or similar for SMS, Postmark/Resend for email.
- **Why not the others [I]**:
  - CloudKit/SwiftData+CloudKit: free-ish and zero-ops, but Apple-only, weak for multi-user org data with roles (CKShare complexity), no web customer portal or server-side hooks, hard to debug. Fine for a personal-data app, wrong for crews + dispatcher.
  - Firebase Firestore: offline cache is built in, but NoSQL data modelling for invoices/relations, Apple SDK size, and pay-per-read cost surprises.
  - Custom SwiftData + own sync: highest dev cost; sync is the hardest part to get right.
- **Push**: APNs direct or via Supabase edge function; use time-sensitive notifications for storm alerts; optional Live Activities for "crew en route" [I].
- **Weather**: WeatherKit: 500,000 calls/month included in the Apple Developer Program; extra from $49.99/mo per 1M calls [E: developer.apple.com/weatherkit/get-started/, 9to5mac.com/2022/09/12/developers-weatherkit-api-requests/]. Cache by geohash server-side so calls scale with service areas, not devices; Apple attribution is required [I]. Snow-accumulation/trigger logic should also be validated against NWS data (free) [I].

### 3.2 iOS constraints [I - from training knowledge; verify against Apple docs]
- Background location: needs "Always" authorization for geofence/track; Apple reviews justification strings. Region monitoring is limited to **20 regions per app** (CLMonitor/CLLocationManager), so geofence only the next N jobs and refresh them. Use significant-change / visits for cheap tracking; continuous GPS drains battery (budget: workday on-clock tracking at 10-30 s intervals, `activityType = automotiveNavigation`, `pausesLocationUpdatesAutomatically`, `CLBackgroundActivitySession`). iOS shows the blue location indicator. Time clock should be explicitly user-driven with background tracking only while clocked in, which also helps privacy/legal compliance for employee tracking.
- Background sync: BGTaskScheduler is opportunistic, not guaranteed; rely on push-triggered silent notifications plus sync on foreground. Offline queue must persist.
- macOS: no background-location/geofence use case; Mac is the dispatch/office client.

### 3.3 Tap to Pay on iPhone [E + I]
- Requires working with a supported PSP, requesting Apple's Tap to Pay entitlement (development entitlement first, production entitlement before TestFlight/App Store) [E: docs.stripe.com/terminal/payments/setup-reader/tap-to-pay; developer.apple.com/forums/thread/801715].
- iPhone only: Stripe says iPads are not supported [E: support.stripe.com/questions/tap-to-pay-on-iphone-and-stripe-terminal]. Min device iPhone XS or newer; iOS minimum varies by SDK (16.7 via Square, 18.1 via another provider) so check Stripe Terminal's current docs [E: search results above]. Needs a physical device (no simulator) [E]. Stripe Terminal iOS SDK 2.23+ supports PIN entry [E].
- Implication: gate the feature to iPhone, and consider Stripe Terminal as the single PSP across online/invoice and in-person.

### 3.4 Realistic 3-phase roadmap (solo dev + part-time help) [I]
**Phase 1 - MVP (weeks 1-12)**: Auth/org model, customers/properties, jobs and recurring visits, drag-and-drop schedule (iPad/Mac), basic route ordering (nearest-neighbor + MapKit ETA; no solver yet), crew app with offline job list, photos, notes, complete job, time clock (foreground + background while clocked in), invoice PDF + Stripe card-on-file/online pay link, PowerSync offline sync, push, web checkout + 14-day trial with Stripe. Ship TestFlight to 5-10 design-partner snow/landscape contractors by week 8-10.
**Phase 2 - Beta to paid (weeks 13-26)**: StoreKit subscriptions + RevenueCat, Tap to Pay on iPhone (apply for entitlement in week ~4 of Phase 1 because approval lead time is unknown), snowfall-triggered work orders via WeatherKit, route optimization with time windows, SMS "on the way", geofenced auto-arrival, QuickBooks Online sync, client portal (web).
**Phase 3 - Scale (months 7-12)**: Marketing module (campaigns, review requests, renewals), seasonal contracts/per-push pricing, advanced reports/profitability, roles and permissions, Fleet tier + API, Android/web crew client decision (if demand), SOC-2-lite hardening.
Key risks: sync correctness (budget 25-30% of Phase 1 for it), Apple review of background location and payments, Tap to Pay entitlement lead time, SMS A2P 10DLC registration lead time [I], accuracy of competitor prices (volatile; several vendors stopped publishing).

## Open items to verify
Jobber/HCP extra-seat prices; Apple link-out court decision; Stripe Connect/Terminal fee schedule; StoreKit free-trial durations; PowerSync/Supabase current pricing; Google/Apple routing API rates.
