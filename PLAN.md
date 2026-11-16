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

**Max (everything in Pro, plus):** conditions-aware route optimizer (traffic, storm speed factors, priorities, time windows), storm events with weather triggers and 3am dispatch, sub management (COI expiry, pay rules, no-photo/no-pay), QuickBooks two-way sync, marketing (review requests, renewal campaigns), roles/permissions, advanced reports.

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
| Storm triggers and conditions-aware routing | Not found | Max |
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
