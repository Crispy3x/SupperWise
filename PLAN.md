# Snow & Home-Service Route App: Market Research and Plan

Built from six research passes (files in `research/`). **Evidence quality caveat:** agents mostly saw search snippets, competitor blogs and aggregator pricing. Only Jobber's official pricing page and ~20 Trustpilot reviews were read directly. G2/Capterra were blocked, and no Reddit/PlowSite threads surfaced. Treat complaint themes as strong directional signals, not statistics. Verify every competitor price on vendor pages before publishing comparisons. Founder experience should validate the snow-specific priorities.

## 1. What people dislike (ranked by how often it appeared)

1. **Billing, contracts and cancellation.** Annual lock-ins, refusal to cancel, reactivated accounts, nonrefundable setup fees, refund disputes. Seen at Jobber, Housecall Pro, Workiz, Service Fusion, ServiceTitan (12-month minimum).
2. **Price creep.** Per-seat fees ($29/user at Jobber), paid add-ons (Marketing $99), annual increases (Service Autopilot reportedly 10-25%), "contact sales" pricing (ServiceTitan, Aspire, Workiz, FieldPulse).
3. **Payments pain.** Held funds and limits (Square, Housecall Pro, Jobber), forced in-house processors, opaque fees.
4. **Support reachability**, especially when money is involved.
5. **Reliability.** Sync/offline failures (FieldPulse), UI churn, QuickBooks duplicate and mismatch errors (Jobber, FieldPulse).
6. **Learning curve.** Aspire, LMN and ServiceTitan are powerful but heavy.
7. **Routing.** Geocoding errors, drivers abandoning in-app nav, per-driver cost escalation, routes reshuffling mid-day. **No competitor found that optimizes for weather or road conditions.**
8. **Time clocks.** GPS battery drain, unwanted auto clock-ins, per-user fees stacked on a base fee.
9. **Snow gap.** Nothing in Jobber, Housecall Pro or the routing tools covers storm triggers, per-push/seasonal billing or proof of service. This rests on absence in vendors' own pages.

**What users like (don't break it):** simple quote-to-invoice, drag-and-drop calendar, quick onboarding, flat unlimited-user pricing (Service Fusion), responsive human support.

## 2. Positioning

> The snow-first, all-in-one crew app: flat per-crew pricing, no contracts, plain payments, native on Apple.

Promises that map directly to complaints:
- **Cancel in one tap, export your data.** Month-to-month by default.
- **Office seats are free.** Price by crew/device only.
- **Published payment rates and payout times.** Human support for money issues.
- **Offline-first.** Crews keep working with no signal, then sync.
- **Storm mode** (below) is the wedge no competitor has.

## 3. Feature set

**MVP (months 1-3):** customers/sites CRM, quotes to invoices, drag-and-drop schedule, offline crew app, time clock (per-job timer, shift clock, prompted geofence "you arrived, start?" rather than silent auto-punch), Stripe payments and pay links, basic dispatch map and route list.

**Snow differentiators (the reason to switch):**
1. **Proof of service:** timestamped GPS and photos per visit, exportable evidence pack, long retention (slip-and-fall claims can arrive ~18 months later).
2. **Billing engine for snow contracts:** per-push, seasonal, per-inch/trigger, hybrid (seasonal base with cap and overage), time and materials. Auto-invoicing per event or season, and warnings when a seasonal cap is hit.
3. **Storm events:** per-site trigger depth, weather snapshot logged to each visit, presets (plow, salt, both), 3am push dispatch.
4. **Conditions-aware routing:** traffic-aware drive times, storm speed/service-time factors (editable), site priorities, time windows, truck constraints. Freeze the next N stops so routes don't reshuffle mid-storm. Hand turn-by-turn off to Apple/Google Maps.
5. **"Service complete" text/email with photos** to kill the "did you come?" calls.
6. **Sub/driver management:** pay by hour, push or lot, insurance expiry tracking, "no photo, no pay", scorecards.
7. **Salt/material logging** per site and cost per storm.

**Phase 2-3:** Tap to Pay on iPhone, QuickBooks two-way sync that matches one deposit to many invoices (headline feature), review requests, quote follow-ups, seasonal renewal campaigns, SMS/email templates with consent, forecast alerts ("these N sites will hit trigger"), equipment tracking, roles/permissions, reports. Skip lead-gen marketplaces and a full campaign builder.

**Platform risk:** Apple-only excludes Android crew members. Plan a lightweight web/PWA crew view later.

## 4. Pricing (draft, verify before launch)

Priced per crew (one field device). Office seats free. 14-day free trial.

| Tier | Includes | Monthly | Annual |
|---|---|---|---|
| Solo | 1 crew | $39 | $390 |
| Crew | 3 crews, extra $25 | $99 | $990 |
| Business | 10 crews, extra $18 | $249 | $2,490 |
| Fleet | 20+ crews | custom | custom |

Comparison (Jobber's official page): Connect for 5 users is $199/mo month-to-month, and a 3-person crew is about $197. Route optimizers alone are $35-49 per driver. Our Crew tier bundles routing, time clock and payments for $99.

Seasonal idea: since snow is seasonal, offer a **season pass or pause** (pay Nov-Mar, or pause in summer). No researched competitor offered this, so it is untested.

**Payments revenue:** about 0.2-0.5% on card volume (roughly $40/mo for a contractor processing $15k/mo). Treat as a bonus, not the business. Don't pursue payfac registration at MVP.

**Margins (all COGS are assumptions, not measured):** about 77-81% gross on web billing for Solo/Crew, 72% at Business. Through StoreKit at 15% commission, about 61-69%. At 30% commission, about 15 points lower.

**Billing channel:** Apple's US link-out rules are in flux (a proposal for 15% on link-outs was filed Aug 2026 and is not court-approved). Re-check before launch. Suggested approach: web billing (Stripe) as primary, StoreKit as a convenience path, with the 14-day trial as a StoreKit introductory offer and a Stripe trial on the web. RevenueCat is available to unify entitlements.

## 5. Tech (recommended)

- **App:** SwiftUI multiplatform (iPhone, iPad, Mac) with a shared Swift package.
- **Sync/backend:** local SQLite with PowerSync and Supabase Postgres. CloudKit is rejected (Apple-only, weak multi-user roles, no web or webhooks). Budget 25-30% of Phase 1 for sync correctness.
- **Routing:** self-hosted Valhalla plus VROOM on a regional OSM extract (near-zero cost per stop, so flat pricing works). Use Google Routes or Mapbox live traffic only to refresh the next few stops. Keep a provider abstraction so you can swap in HERE for trucks. Apple's directions API cannot be the engine.
- **Weather:** Apple WeatherKit (500k calls/mo included) plus NWS alerts (free). Cache by region.
- **iOS limits:** background location needs "Always", region monitoring is capped at 20 regions per app (geofence only the next few jobs), track continuously only while clocked in.
- **Tap to Pay on iPhone:** needs Apple's entitlement (apply early), iPhone only, physical device.
- **Roadmap:** Phase 1 (weeks 1-12) MVP with design partners on TestFlight. Phase 2 (weeks 13-26) StoreKit, Tap to Pay, snow triggers, optimizer, SMS, QuickBooks. Phase 3 (months 7-12) marketing, seasonal contracts, reports, Fleet tier.

## 6. Name ideas

*(Trademark and domain availability not checked.)*

| Name | Why | Logo idea |
|---|---|---|
| **Windrow** | A windrow is the ridge of snow a plow leaves. Insider term, memorable. | A plow-blade curve forming a "W" |
| **Plowline** | Plow plus route line. Instantly clear. | A route line ending in a plow blade |
| **Driftline** | Snowdrift plus route, and works beyond snow. | Wave-like drift that becomes a path |
| **Pushline** | "Push" is what owners call each plow visit. | Arrow turning into a blade |
| **Trigger** | Snow trigger depth is the core snow workflow. | Snowflake inside a crosshair or pin |
| **Saltway** | Salt plus pathway. | Pin with a salt-crystal hexagon |
| **Flurry** | Friendly and easy to say, but weak for the trades. | A single stylised flake as a pin |
| **Crewline** | Suits the all-in-one scope and landscaping in summer. | Three connected dots, one per crew |

**Recommendation:** Windrow or Plowline. Windrow is the most distinctive and speaks to the trade. Plowline is the safest and clearest. If you want one name that carries into lawn season, Driftline or Crewline.

**Logo direction:** a simple pin or route-line mark in an icy blue-to-navy gradient, with one warm accent (safety orange or hi-vis yellow) for the "active job" dot. It should read at 29px as an app icon, in dark and light mode. Keep the UI calm and high-contrast, with big tap targets for gloved hands and night mode by default for 3am dispatch.

## 7. Still to verify

- Competitor prices and fees on vendor pages (Housecall Pro extra seats, Stripe Connect fees, Square rates).
- Real owner complaints from Reddit, PlowSite and Facebook (manual pass).
- Snow-removal market size and typical operator revenue.
- Apple link-out fee ruling, StoreKit trial durations, Tap to Pay minimum iOS.
- Routing at 200-1,000 stops: solve time, server memory, Mapbox/HERE costs.
- Name trademark and domain checks.

---

# Update: Name and plan structure (supersedes sections 4 and 6)

## Name: Ridgeline Ops
Web searches found no software product with this exact name (nearest: RIDGID Connect, an unrelated jobsite app). Not a trademark clearance, so run a USPTO search and check domains and the App Store before spending on branding. "Ridgeline" alone is a very common word and brand, so always use the full name "Ridgeline Ops".

## Plans: Pro and Max (14-day free trial)
Priced per crew (one field device). Office/admin seats are free. Price rises with the number of crews.

| | **Pro** | **Max** |
|---|---|---|
| For | Solo to small crews running the business | Crews that want storm automation and optimization |
| Base (includes 1 crew) | $39/mo | $79/mo |
| Each extra crew (2-5) | +$25 | +$39 |
| Each extra crew (6+) | +$18 | +$29 |
| Annual | 2 months free | 2 months free |

Example monthly totals:

| Crews | Pro | Max |
|---|---|---|
| 1 | $39 | $79 |
| 3 | $89 | $157 |
| 5 | $139 | $235 |
| 10 | $229 | $380 |

**Pro:** CRM, scheduling, quotes/invoices, offline crew app, time clock, Stripe payments, snow billing (per-push, seasonal, trigger, hybrid), GPS and photo proof of service, basic route ordering by drive time, "service complete" texts.

**Max (everything in Pro, plus):** route optimizer (drive time, priorities, fixed stops, deadlines), storm events with weather triggers and 3am dispatch, sub management (COI expiry, pay rules, no-photo/no-pay), QuickBooks two-way sync, marketing (review requests, renewal campaigns), roles/permissions, advanced reports.

**Trial:** 14 days with Max features unlocked so owners see the storm and routing wedge, then they pick a plan. Month-to-month with one-tap cancel.

**Comparison (Jobber's published prices):** Jobber Grow for 5 users is $299/mo month-to-month. Ridgeline Max for 5 crews is $235 with unlimited office seats and routing included. Housecall Pro MAX is $329/mo for up to 8 users (reported).

**Margins (assumptions, not measured):** roughly 75-85% gross on web billing, 60-70% when billed through the App Store at 15%. Max costs more to serve (live-traffic refreshes, SMS, weather), which the higher price covers.

**Billing note:** App Store subscriptions are fixed products, so "per-crew" pricing means selling bundles (for example 1, 3, 5 and 10 crews) there. Web billing (Stripe) handles per-crew pricing cleanly, so make it primary and re-check Apple's link-out rules before launch.

---

# Update: Beat competitors on price and on what's included

## Price changes
- **Pro base lowered from $39 to $29** (1 crew). Reason: Jobber's cheapest plan, Core, is $29/mo on annual prepay, so $39 would not have been cheaper at the entry level.
- Extra crews unchanged (Pro +$25 for crews 2-5, +$18 for 6+; Max +$39 and +$29).

| Crews | Pro /mo | Pro annual (per mo) | Max /mo | Max annual (per mo) |
|---|---|---|---|---|
| 1 | $29 | $24 | $79 | $66 |
| 3 | $79 | $66 | $157 | $131 |
| 5 | $129 | $108 | $235 | $196 |
| 10 | $219 | $183 | $380 | $317 |

Annual = 2 months free.

## Against Jobber (official pricing page, per month; Jobber charges per user, we charge per crew with free office seats)
| Size | Jobber Connect (monthly / annual prepaid) | Ridgeline Pro | Jobber Grow (monthly / annual prepaid) | Ridgeline Max |
|---|---|---|---|---|
| 1 | $139 / $99 | $29 / $24 | $199 / $149 | $79 / $66 |
| 5 | $199 / $149 | $129 / $108 | $299 / $229 | $235 / $196 |
| 10 | $299 / $229 | $219 / $183 | $399 / $299 | $380 / $317 |

Notes:
- Cheaper at every size in the table, but the gap at 10 crews is small for Max (about $19-$30/mo less than Grow). Honest pitch for big fleets is "same price or less, with far more included", not "half price".
- Jobber's Core ($29-$49) is a stripped-down plan, so it isn't a like-for-like match for Pro.
- Real savings are bigger than shown, because Jobber charges $29 for each extra user including office staff, and ours are free.
- Jobber's Marketing Suite add-on is $99/mo; ours is included in Max.

## What we include that competitors charge extra for or lack
| Feature | Jobber | Ridgeline Ops |
|---|---|---|
| Unlimited office seats | $29/user | Free |
| Marketing (review requests, renewals) | $99/mo add-on | Included in Max |
| Snow billing (per-push, seasonal, trigger, hybrid) | Not found in their pages | Included in Pro |
| GPS and photo proof of service | Not found as a built-in snow feature | Included in Pro |
| Storm triggers and a route optimizer | Not found | Max |
| Cancellation | Complaints about annual plans | Month-to-month, one-tap cancel, data export |

("Not found" means absent from Jobber's own pages and the sources we saw, not proof it's missing. Re-check Jobber's current feature list before putting it in marketing.)

## Payments must not undo the price advantage
The earlier idea of "processor rate plus about 0.3%" would make us dearer than Jobber (2.9% + 30¢ card, 2.7% + 30¢ Tap to Pay, 1% ACH). Instead:
- Card: match Jobber, 2.9% + 30¢.
- ACH: beat Jobber, pass through Stripe's reported 0.8% capped at $5 (unverified, confirm Connect pricing).
- Earn the margin from subscriptions, not payments. Any Stripe Connect revenue share is a bonus.
- Publish payout timing and holds policy.

## Margin check (assumptions)
At $29 for one crew: estimated cost about $4.50 (hosting, routing, support). About 85% gross on web billing, about 70% through the App Store at 15%. Still healthy. Max at 10 crews has the thinnest absolute margin per crew because of the $29 crew rate, so watch SMS and live-traffic costs there.

---

# Update: No built-in payment processing for now (supersedes earlier payment notes)

**Decision:** Ridgeline Ops will not process payments in v1. Too much ongoing work (merchant onboarding and identity checks, payouts and holds, disputes, support) for the first release. The payments page stays "in progress".

**What replaces it in v1 (Pro and Max):**
- Invoices include a payment link to the owner's own Stripe, Square or PayPal account, or a note with Venmo/Zelle/cash/check instructions.
- Mark invoices paid manually (cash, check, other), with partial payments.
- Seasonal contracts: scheduled invoices and reminders, with no autopay for now.
- QuickBooks sync (Max) matches one deposit to many invoices.

**Removed or deferred from the plan:** Stripe Connect, Tap to Pay on iPhone, ACH pricing, any payments revenue, and the card/ACH comparison against Jobber.

**Pitch advantage:** "We never touch your money. No holds, no forced processor, no payment fees from us." Jobber, Housecall Pro and Square draw complaints about holds and forced processors.

**Pricing impact:** none to the plan prices. They were always subscription-based and payments revenue was only a bonus. Slightly lower costs (no payments support). The comparison against Jobber still holds on subscription price. Keep the "payments are included" row off marketing pages.

**Revisit later (phase 3):** Stripe Connect Standard accounts (owners keep their own Stripe account, we only create payment links and read status) is the lightest version. Confirm Stripe's current Connect terms and fees first. Tap to Pay needs Apple's entitlement, so apply early if you plan it.

---

# Update: Launch strategy and founding-member promise

**v1 strategy:** ship without payment-processing risk, at a lower price than competitors, with the 14-day free trial, and fix the top complaint areas first (billing/cancellation friction, price creep, reliability/offline, snow-specific workflows, proof of service).

**Founding-member promise (draft):** everyone subscribed during the founding period gets the future payments feature added at no extra subscription cost, and joins its beta first ("part of the trial").

Draft terms to settle before advertising it:
- **Wording:** "Founding members get Ridgeline payments at no extra subscription cost." We can waive our own platform fee. We cannot waive the payment processor's card/ACH fees, so say that plainly.
- **Who qualifies:** subscribers who join before a stated date, or the first N accounts, and who stay subscribed.
- **Time limit:** decide whether it is "forever" or a set number of years. Open-ended promises are hard to honour if costs change, so pick the term you can afford.
- **No date promised:** say "planned", not a delivery date, until the payments work is scoped.
- **Beta first:** founding members get early access and can shape the feature.
- Have a lawyer glance at the final text before it goes on the website or App Store listing.

**Research round 2 (running):** owner voices from forums, App Store review text analysis with counts, customer-side (homeowner/property manager) complaints, verified vendor pricing, and market size. Outputs: `research/07` to `research/11`.

---

# Update: Verified pricing and revised prices (supersedes earlier price tables)

Source: `research/10-verified-pricing.md`, fetched from official vendor pages on 2026-11-16 (spot-check key figures before using them in marketing).

**Correction to my earlier comparison:** I said we were cheaper than Jobber at every size. On annual billing, Max at 10 crews ($317/mo) was actually above Jobber Grow ($299/mo annual prepaid). Prices below fix that.

## Revised prices (per crew; office seats free)
| | Pro | Max |
|---|---|---|
| Base (1 crew) | $29 | $79 |
| Extra crew, 2-5 | +$19 | +$29 |
| Extra crew, 6+ | +$12 | +$19 |
| Annual | 20% off | 20% off |

| Crews | Pro /mo | Pro annual (per mo) | Max /mo | Max annual (per mo) |
|---|---|---|---|---|
| 1 | $29 | $23 | $79 | $63 |
| 3 | $67 | $54 | $137 | $110 |
| 5 | $105 | $84 | $195 | $156 |
| 10 | $165 | $132 | $290 | $232 |

## Verified competitor prices (official pages, per month, monthly / annual)
- Jobber: Core 1 user $49 / $29. Connect 5 users $199 / $149, 10 users $299 / $229. Grow 5 users $299 / $229, 10 users $399 / $299. Extra user $29. 14-day trial.
- Housecall Pro: Basic $79 / $59 (1 user). Essentials $189 / $149 (5). Max $329 / $299 (8, +$35 per extra user). 14-day trial.
- Service Fusion: Starter $259 / $220, unlimited users, no trial.
- GorillaDesk: $49 / $99 / $149, unlimited users, extra routes cost more. 14-day trial.
- Kickserv: $60 (5 users), $119 (10), $199 (20). 30-day trial.
- LMN: Starter $297 plus onboarding fee.
- Route planners: Upper $50 per user ($40 yearly), Route4Me $199-$349, OptimoRoute about $35-$44 per driver.
- **Snow-specific, direct competitors:** Plow360 (Solo $20 for 25 sites, Team from $40, Pro from $140 with storm dispatch, time clock and QuickBooks, 14-day trial); Yeti Snow ($66.50/mo annual for 1-25 sites, no trial).
- Not public: Workiz, FieldPulse, Aspire.

## Where we win and lose (monthly vs monthly, then annual vs annual)
- Pro beats every full field-service product with a published price at 1, 3, 5 and 10 crews, including on annual billing.
- Max beats Jobber Grow at every size on both monthly and annual billing after the cut (10 crews: $290 vs $399 monthly, $232 vs $299 annual).
- We do not beat Kickserv ($60 for 5 users) or the site-capped snow tools (Plow360, Yeti) on raw price at 3-10 crews. Compete on features and no site caps instead.
- Free office seats are a real edge only against per-user vendors (Jobber, Housecall Pro, Kickserv). Service Fusion and GorillaDesk already include unlimited users.
- Gap: no built-in payments in v1, which Service Fusion, LMN, GorillaDesk and Kickserv offer.

## Margin check (assumptions)
Pro at 10 crews ($165): cost roughly $40 (hosting, routing, support) gives about 75% web margin, about 60% through the App Store at 15%. Max at 10 crews ($290) assumes higher routing/SMS costs, about 70% web. Watch the 6+ crew rate if usage costs run higher than assumed.

## New to watch
Plow360 and Yeti Snow are direct snow-specific competitors we had not found in round one. Do a hands-on trial of both before launch.

---

# Update: Round 2 synthesis (what to build and how to pitch it)

Sources: `research/07` (owner voices), `08` (App Store review text, 3,055 reviews, 1,362 coded 1-3 star), `09` (customer-side complaints), `10` (verified pricing), `11` (market size).

**Evidence limits:** owner voices are search excerpts (PlowSite/LawnSite redirected to bot-gating domains and Reddit was refused, so no Reddit data), mostly old and lawn-leaning. The App Store sample is the newest 500 reviews per app, keyword-coded with an estimated 65-80% precision, so counts are indicative. Snow-specific voice is almost absent (3 core-app reviews mention snow). Interviews with real snow operators are the missing piece.

## What the App Store data says (core software apps, 778 coded reviews)
| Rank | Theme | Share |
|---|---|---|
| 1 | Bugs, crashes, slowness | 28% |
| 2 | Support | 20% |
| 3 | Billing and cancellation | 18% |
| 4 | Price | 16% |
| 5 | Missing features | 16% |
| 6 | UI and usability | 11% |
| 7 | Routing | 10% (mostly Route4Me) |
| 8 | Sync/offline and time clock/GPS | 5% each |
| 10 | Payment holds and payout delays | 4% |

Takeaways:
- **Reliability and support beat everything.** The strongest promise is an app that does not crash, does not force re-logins, uploads photos in the background and works offline.
- **Billing and cancellation** is the third-biggest complaint (cancel-by-phone, charges after cancelling, annual lock-in, trial-to-paid surprises). Our one-tap cancel, export and clear trial ending are real differentiators.
- **Skipping payments in v1 removes a complaint category** (only 4% of reviews, but a high-anger one).
- Most requested missing features: estimate/invoice editing, customer text/email/phone, photo upload, push notifications, recurring jobs and calendar control, search, offline mode, live crew location, adjustable missed punches.
- Workyard complaints: "always" location permission and auto clock-out. Keep our time clock prompt-based and low-power.

## Changes to the feature plan
**Add or raise priority (Pro unless noted):**
1. Bulk and recurring-route rescheduling (change a route's day or crew in one action). Owners report editing each customer one by one.
2. Invoices with one line per storm or season, flexible due dates, late fees, and billing within minutes of a storm ending. Quick post-storm billing is the bar set by existing snow billing tools.
3. Photo capture with background upload, retries and never losing a photo.
4. Customer notifications (scheduled, en route, delayed, skipped with reason) and a client link with timestamped photo timeline.
5. Immutable visit log (time, geofence, before/after photos, material quantities) with exportable dispute packet. Wanted for insurance and claim defense, not marketing.
6. Sub pay by percentage of job, hourly or per-push, with payment status visible to subs.
7. Stability work as a feature: no forced re-login, offline-first, update regression testing.

**Reposition routing (Max):** present it as dispatcher-controlled re-sequencing, not an autopilot. Owners distrust auto-routing ("zero faith"). Include a "next stop" driver view, shared-driveway consecutive stops, and keep the storm-speed and priority controls editable. Freeze the next stops so routes never reshuffle under a driver.

**Lower priority until validated:** marketing tools, all-in-one breadth and "Apple-native" as selling points. No owner asked for them in our sample. Test with real owners before building around them.

## Pitch (draft)
"Snow-ready crew software that doesn't crash, never loses a photo, never holds your money, and cancels in one tap. From $29 a month."

## Market sizing reality check
Mid-case Apple-only market is about 58,000 businesses. Most are solos averaging about $36k a year, and most firms run 1-2 crews, so average revenue per account is closer to about $70 a month than $100. At 1% of the market that is roughly 580 accounts. iPhone share among contractors is the biggest unvalidated assumption (45-65% estimated).

## Biggest remaining risks
1. No first-hand snow-operator interviews yet. Do 10-15 before building much beyond the MVP.
2. Direct snow competitors (Plow360, Yeti Snow) not tried hands-on.
3. iPhone share among target customers and the Android crew-member gap.
4. Founding-member payments promise terms not yet settled.
5. Name trademark and domain checks for Ridgeline Ops.

## Suggested next steps
1. Interview 10-15 snow and landscaping owners (script: what do you use, what do you hate, what did you switch from, iPhone or Android, what would you pay).
2. Trial Plow360 and Yeti Snow.
3. Run a trademark and domain check for Ridgeline Ops.
4. Build the MVP: offline-first crew app, scheduling with bulk reschedule, proof-of-service log, snow invoicing, 14-day trial billing.

---

# Decision: push counting
Per-push and hybrid contracts have a per-contract setting. Default `perStorm` (one push per storm, however many return trips, fewest billing disputes); owners can switch a contract to `perVisit`. Implemented and tested in `Sources/RidgelineCore/SnowBilling.swift`.

---

# Build status (latest)
Core logic is built and tested (59 tests): pricing and trial gating, snow billing, storm triggers, dispatcher-controlled route ordering, bulk rescheduling, tamper-evident proof-of-service log, time clock, customer notices, sub pay, offline store. SwiftUI screens (Crew, Storm, Customers, Invoices, Proof, Plans) are written but not yet compiled, since that needs Xcode. See `README.md` for the full list and known placeholders.

---

# Decision: routing uses Apple Maps and Google Maps plus our own weather layer
Google Routes API gives traffic-aware batch drive times (server-side, key never in the app). Apple MapKit gives live per-leg ETAs on the device and Apple Maps handles next-stop navigation; Google Maps handles whole-route navigation links. Neither knows about snow, so the weather layer and the optimizer are ours. Weather factors are starting guesses to be calibrated from logged drives. Terms of service, cost and the server are open items (see README, "How routing works"). Built and tested: 86 tests.

---

# Build status: routing server
Built `server/` (zero-dependency Node proxy for Google's Routes API with per-token auth, rate and daily-cost caps, cache, request splitting) and the Swift `ProxyMatrixSource` client. 16 server tests and 91 Swift tests pass; the real Swift client was run against the real server with a stand-in for Google. Not yet tested with a real Google key, not deployed, not wired into the screens. Open items: Google terms on caching and non-Google maps, hosting and budget alerts, a real-key smoke test.

---

# Build status: weather feed
Built the National Weather Service client (forecast and winter alerts) with tests (103 total), checked against the live service. Wired into the Storm screen (unverified UI): set yard location, load the next 24 hours, inputs fill automatically, winter alerts show. Open: real snowfall total not yet seen live (no snow in the forecast that day), Apple WeatherKit as a second source (needs Xcode and a developer account), NWS contact in the user agent.

---

# Build status: invoicing
Built editable invoices, manual payments, late fees applied only on the owner's say-so, installment splits, CSV export and a double-billing guard (121 tests). Wired into the Invoices screen (unverified UI). Not built: payment links, PDF invoices, QuickBooks sync (CSV only), emailing invoices.

---

# Build status: quotes and job costing
Quotes (expiry, accept or decline once, contract from accepted quote), season-cost estimates with a mild-to-heavy range, and per-site job costing. 130 tests. Core only, no screens yet.

---

# Build status: app complete as code, awaiting a Mac
All screens (Crew, Storm, Customers, Quotes, Invoices, Routes, Time clock, Job costs, Proof, Plans, Settings), camera and location and address lookup, Keychain token, live-route wiring, Xcode project generator and App target are written. Core logic has 144 tests; the screens and Apple-only code have never been compiled. `SETUP.md` lists what the owner must do.

---

# Decision: Apple Maps is the default drive-time source
Apple MapKit on the device (free, live traffic, no key). Because Apple answers one leg per request and throttles, the app measures the most important legs and estimates the rest, and reports how many were measured. Google via the routing server stays as an option, and the offline estimate as a fallback. Apple's terms were read in part: the fleet management ban is worded for MapKit JS on non-Apple hardware, results may be kept only briefly, and Apple can limit access at any time. Open: confirm with Apple developer support or a lawyer that crew route planning in a native app is allowed. 160 tests.

---

# Decision: routes use drive time only, not weather
Routes are ordered by drive time (Apple Maps, or the routing server, or the offline estimate), with strict priorities, fixed stops and deadlines. They are **not** adjusted for weather. Weather still decides which sites need service: the forecast fills the snowfall slider, and each site's trigger depth decides who is listed. The weather model stays in the code, tested but unused, in case it is wanted later. Reasons: no maps service has snow-aware routing, the slowdown factors were unvalidated guesses, and owners in the research distrusted automatic routing. Earlier mentions of "conditions-aware routing" in this file, including the pitch and the competitor comparison, are superseded by this decision. Apple's live traffic still reflects slowdowns that appear in traffic data.
