# 04 - Routing / Dispatch Competitors and Build-vs-Buy Technical Options

Research date: 2026-11-16. Labels: **[E]** = evidence from a fetched/searched source (URL given), **[I]** = my inference, **[G]** = gap, not verified.
Source-quality warning: many "review" pages in the results are written by competing vendors (Upper, Circuit/Spoke, AirPinpoint, GPS Insight, NextBillion). Those are flagged **[vendor-biased]**. I did not find usable Reddit/Trustpilot/App Store threads on most products via search; the review evidence below is mostly Capterra/G2/Software Advice summaries. Snow-specific routing complaints from real users were essentially not findable (see gaps).

## 1. Competitor table (pricing model)

| Product | Pricing model | Figures found | Source / confidence |
|---|---|---|---|
| Route4Me | Per user/plan; public pricing opaque | Older: ~$80/user/mo or $400/mo for 5 users; other page lists $199/$299/$349 tiers (unit unclear). "Not publicly available as of Jan 2026" per one source | upperinc.com blog, softwareadvice [vendor-biased, conflicting] |
| OptimoRoute | Per driver per month | Lite ~$35.10 (annual) to $39 monthly; Pro ~$44.10 to $49; Pro ~1,000 orders cap | https://www.upperinc.com/blog/optimoroute-pricing/ [vendor-biased] |
| Routific | Per order volume, unlimited drivers | Free under ~100 orders/mo; flat ~$150 up to ~1,000 orders/mo (one source says vehicle-based; conflict) | routific.com blog / upperinc comparison [conflicting] |
| Circuit / Spoke | Solo app: free/Lite/Standard; Teams renamed Spoke Dispatch (Oct 2025) | Free $0, Lite ~$10, Standard ~$20 | https://softwarefinder.com/fleet-management-software/circuit-route-planner , NextBillion post [secondary] |
| Onfleet | Plan tiers (delivery-centric) | ~$500-$619/mo entry | g2.com/products/onfleet/pricing, toolradar [sources differ] |
| Tookan | Plan tiers | ~$49-$99/mo entry | g2, toolradar [sources differ] |
| Upper | Per user | ~$40-47/user/mo | g2 listing |
| Badger Maps | Per user (sales-visit focus) | ~$58/user/mo annual | upperinc.com [vendor-biased] |
| Zeo | Not found | - | [G] |
| Jobber (built-in routing) | Included in field-service plans, reportedly tier-gated; routing overhauled Oct 2025 | Capterra feature rating route optimization 3.8 vs OptimoRoute 4.7 | https://www.capterra.com/compare/127994-161579/Jobber-vs-OptimoRoute ; getjobber.com/route-optimization |
| Workiz | Not found | - | [G] |
| Samsara / Verizon Connect / Motive | Quote-based, per-vehicle/device, multi-year contracts (telematics, not planners) | Verizon est. $20-45/vehicle/mo, 3-yr term (third-party estimate); Samsara auto-renew uplift up to 5%/yr claimed | airpinpoint, gpsinsight [vendor-biased] |
| Mapbox / Google fleet tools | Usage-based APIs (see section 4) | - | official docs |

Takeaway [I]: the market splits into (a) cheap solo apps (Spoke $10-20), (b) per-driver planners ($35-50/driver), (c) quote-based telematics with contract pain, and (d) field-service suites with "basic" routing (Jobber). No product found that is snow-specific and routes on weather/conditions.

## 2. Top complaint themes (evidence)

Ratings are generally high (Route4Me ~4.5 Capterra/411; Routific 4.9 Capterra/144; OptimoRoute 4.6 Capterra/268; Spoke 4.8 Capterra/105), so complaints are a minority signal. [E]

1. **Poor address/geocoding and map mismatch.** Route4Me: difficulty finding/correcting addresses, slow with many stops (Software Advice); "cannot find locations Google Maps handles" (competitor claim). Routific: address errors if not perfectly formatted, pin mapping issues (Capterra reviewers). OptimoRoute: its map data gives different travel times than Google Maps (GetApp reviewer). Sources: https://www.softwareadvice.com/fleet-management/route4me-profile/reviews/ , https://www.capterra.com/p/142530/Routific/reviews/ , https://www.getapp.ca/reviews/107281/optimoroute
2. **In-app navigation not trusted; drivers jump to Google/Apple Maps.** Route4Me: roughly seven reviewers mention using other nav apps; in-app nav "not always accurate" (roundup via Circuit blog [vendor-biased] + Software Advice). https://getcircuit.com/teams/blog/route4me-reviews
3. **Pricing opacity, per-driver escalation, add-ons, sudden increases.** Route4Me hidden add-ons; OptimoRoute per-driver costs escalate with team size; Spoke "sudden price increases" (rfp.wiki; Upper) [mostly vendor/aggregator]. https://www.rfp.wiki/supply-chain-logistics-transportation/transportation-management-systems/last-mile-delivery-technology-solutions/circuit/route4me , https://www.upperinc.com/blog/circuit-pricing/
4. **Rigid / re-optimizes disruptively.** OptimoRoute: copying multi-day routes changes whole route without notice; cannot cancel a stop mid-route; no toll avoidance (GetApp reviewers). Routific: adding a stop to an in-progress route re-optimizes everything and confuses drivers [vendor-biased, Circuit]. https://getcircuit.com/teams/blog/routific-reviews
5. **Ignores real-world conditions.** Spoke: ignored traffic/tolls, crossing routes (Upper review page [vendor-biased]). Routific: overlapping routes, only one break period per driver profile, can't "close the border" (Capterra + Circuit blog). No source found where a planner uses weather/road-condition data. [E for the complaints, G for conditions]
6. **Basic routing inside field-service suites.** Jobber: described as basic, fine for 1-2 crews, falls short at 4+ crews; no auto-resequence on drive time (affiliate-style review sites, low reliability); Capterra feature score 3.8 vs 4.7. https://www.capterra.com/compare/127994-161579/Jobber-vs-OptimoRoute
7. **Support gaps and data loss (Route4Me).** Missed callbacks, unresolved issues; some reports of completed stops erased (Software Advice/Capterra). BBB: 1 complaint in 3 yrs. https://prod.bbb.org/us/fl/tampa/profile/computer-software/route4me-inc-0653-90452050/complaints
8. **Telematics contract/billing pain (Samsara, Verizon, Motive).** Auto-renewal, termination fees, billing errors; Capterra value-for-money 2.8 for Verizon Connect; Capterra reviewers rate Samsara contract terms poorly. Relevant mainly as a "no long contracts" positioning angle. https://www.capterra.com/p/72551/Fleetmatics-Work/pricing/ , https://www.capterra.com/p/167543/Samsara-for-Fleets-0-00-6-23/reviews/
9. **Learning curve / mobile limits.** OptimoRoute: laborious at start, mobile app can't edit in field, thin location analytics (Upper's 290-review analysis [vendor-biased]; Capterra UK).
10. **Snow-specific.** Only weak evidence: MPR 2023 notes many cities don't use optimization software and some never updated routes (https://www.mprnews.org/story/2023/03/16/the-secret-to-making-snowplowing-more-efficient-let-a-computer-figure-it-out); FHWA-linked reports cite tooling gaps (rosap.ntl.bts.gov dot_72307, dot_63224); a 2014 Capterra review asking Jobber for snow-route features. [G] No real contractor-forum complaint threads retrieved.

## 3. What "optimized for conditions" could concretely mean

Inputs [I unless noted]:
- Drive-time matrix with live/predictive traffic (Google TRAFFIC_AWARE_OPTIMAL and Mapbox driving-traffic profile exist [E]).
- Weather: NWS/Apple WeatherKit forecasts (snow start/stop time, accumulation, ice) to decide trigger thresholds (e.g., plow at >=2 in) and sequencing.
- Per-site attributes: priority tier, SLA/time window (e.g., hospital lots by 6am), trigger depth, service duration scaled by accumulation, equipment need (plow vs salt vs shovel crew), access constraints.
- Truck constraints: height/weight/length, turning/dead-end, vehicle capacity (salt load, refill depot), hours-of-service/shift length.
- Road state: closures/restrictions, speed degradation factor during storm (multiplier on free-flow times by snowfall rate), plow-route vs arterial preference.
- Live changes: stop added/skipped, truck breakdown, site completion.

Algorithm approach: this is a Vehicle Routing Problem with time windows, priorities, multiple depots/refills and heterogeneous fleet. Pipeline: (1) cluster/zone sites by crew; (2) build travel-time matrix from engine (with storm speed multiplier); (3) solve with VROOM or OR-Tools using soft time windows, priority-weighted penalties for lateness, skills (vehicle/service type), max shift; (4) cheap re-optimization on events, locking in-progress/next stop to avoid the "whole route reshuffles" complaint (theme 4) [I]; (5) simulate-then-explain: show ETA risk per site.

Feasible MVP (3-4 months, small team) [I]:
- Heuristic storm model: storm-time speed factor + service-time factor from forecast accumulation, user-editable.
- Static-traffic-by-time-of-day matrix (not live) plus optional live ETA refresh for the next few stops only.
- VROOM-based solve with priorities, time windows, skills, vehicle capacity; per-truck dimensions only as a warning/avoid-flag in v1 (true truck restrictions via Valhalla costing).
- Re-optimize remaining stops with a "freeze next N stops" setting; fixed per-driver stop order on repeat lawn routes.
- Native handoff to Apple Maps/Google Maps for turn-by-turn (addresses complaint 2: drivers use their nav anyway), plus MapKit for in-app display.
- Defer: learned service times, plow-path coverage (arc routing), offline solve.

## 4. Routing tech and cost

### Facts gathered
- **Apple MapKit / MKDirections (native iOS):** no official numeric limit published; devs report throttling errors around ~50 requests (anecdotal, Apple forums, e.g. https://developer.apple.com/forums/thread/90152). Source-destination per request, no optimization or truck profile, so unsuitable as the matrix engine. [E anecdotal]
- **MapKit JS / Apple Maps Server API:** up to 25,000 service calls/day per developer team (shared), 250,000 map views/day, HTTP 429 beyond, increased capacity by request form. ETA API exists. https://developer.apple.com/mapkitjs/ [E] Good for map display and light ETA; no optimization.
- **Google Routes API (USD per 1,000, first 100k tier)** [E, fetched https://developers.google.com/maps/billing-and-pricing/pricing.md.txt]: Routes/Matrix Essentials $5 (10k free); Pro $10 (5k free; triggers traffic-aware, 11-25 waypoints, optimizeWaypointOrder); Enterprise $15 (1k free; large-vehicle, tolls, traffic polylines). Matrix is billed per element (n x n).
- **Google Route Optimization API** [E]: per shipment. Single-vehicle: $10/1k (first 100k), falls to $4, $2, $0.80, $0.70. Fleet (>1 vehicle): $30/1k, then $14, $6, $2.40, $2.10. Free 5k/1k per month. So ~$10-30 per 1,000 stops at small scale.
- **Mapbox Optimization:** third-party guides list $2.00/$1.60/$1.20 per 1,000 requests, 100k free (not verified on Mapbox pages). Optimization v2 is Public Beta, up to 1,000 locations/problem, time windows, capacity, shifts, driving-traffic profile, 300 submissions/min; v2 billing not confirmed [E docs, G on price]. Note "per request" not per stop, which would be very cheap if true. Beta = risk. Truck profile not listed (driving, driving-traffic, cycling, walking).
- **HERE:** Routing v8 supports trucks (dimensions/weight); truck routing roughly EUR 2.20/1k after a small free band per a garbled official snippet; Tour Planning price not found. [E partial, G] https://developers.here.com/pricing
- **Open source:** Valhalla (truck costing: height/weight etc, costing changeable per request without graph rebuild; tile graph; planet ~100 GB disk, lots of RAM, a self-hoster bought 128 GB RAM) [E, secondary]. OSRM/GraphHopper also options (no firm cost data found). VROOM (C++ solver on top of matrix) solved a 1,060-pt TSP in ~328 ms in the author's 2018 slides; OR-Tools ~5-8% gap vs best-known at 800-1000 customers after 1 min (Hexaly vendor benchmark [vendor-biased]). No live traffic natively in Valhalla/OSRM; you would feed historical speed profiles or your own traffic overlay. Offline: you can self-host tiles on-device only with significant engineering (Valhalla has mobile builds; not evaluated here) [G].

### Cost per 1,000 stops (inference from list prices)
- Google Route Optimization, single vehicle: ~$10 per 1,000 stops; fleet: ~$30 per 1,000 (first tier). Route-level with 25 stops/route = 40 routes ~ $400-1,200 for 1,000 stops/day-equivalent: expensive if used daily on thousands of stops.
- Google DIY via Matrix Pro: a 25-stop route needs 625 elements = ~$6.25/route at $10/1k, so ~$250 per 1,000 stops (25-stop routes). Matrix cost scales n squared; avoid for big clusters.
- Mapbox Optimization (if $2/1k requests holds): ~cents per 1,000 stops. Verify, beta risk.
- Self-hosted Valhalla + VROOM on a regional (North America) extract: [I] fixed cost of a few tens to low hundreds of dollars per month (RAM-heavy instance), near-zero marginal per stop. Exact sizing unverified; North America extract is much smaller than planet.

### Recommendation (cost-efficient, healthy margins) [I]
1. **Client/display and handoff:** MapKit (native) for maps/markers and Apple Maps/Google Maps deep links for turn-by-turn. Do not use MKDirections as an engine (throttle, no optimization).
2. **Core engine (owned):** Valhalla (truck costing) for matrix + route geometry, VROOM (or OR-Tools for custom constraints) for solving, on a small cloud cluster with regional OSM extracts. Marginal cost ~0, so pricing can be flat per seat without per-stop metering; this is also the answer to the complaint theme "per-driver escalation / hidden add-ons".
3. **Live conditions layer (pay only where it matters):** use a commercial API selectively, e.g. Google Routes Pro traffic-aware ETA (about $10/1k) or Mapbox driving-traffic, only for refreshing the next few stops of active routes, plus a caching layer. Combine with NWS/WeatherKit for storm factors (free/low cost; verify terms).
4. **Fallback/abstraction:** put a matrix-provider interface in front so Google/Mapbox/HERE can be swapped per region or for premium truck needs (HERE truck).
5. **Margin sanity [I]:** if a contractor has 10 trucks x 40 stops x ~15 storm days/season, commercial optimization at $10-30/1k would be pennies to low dollars per day; the real risk is matrix element growth and live-ETA polling loops, so cap and cache. Self-hosting removes the variable risk but adds ops burden and no native live traffic.
6. **Validate before committing:** confirm Mapbox v2 pricing/GA, HERE Tour Planning pricing, Valhalla/VROOM memory sizing on a North America extract, and benchmark real solve times on 200-1,000 stop instances.

## Gaps / not verified
- No Reddit, Trustpilot, or App Store review text retrieved for Route4Me/OptimoRoute/Routific/Spoke/Zeo/Badger/Onfleet/Tookan/Workiz; most complaint evidence is Capterra/Software Advice/GetApp snippets or competitor blogs.
- No snow- or lawn-specific routing-product complaints from actual contractors found; no evidence of any competitor using weather/conditions in optimization.
- Zeo and Workiz pricing/routing not found. Official Route4Me current pricing unclear.
- Mapbox v2 price, HERE Tour Planning price, Apple MKDirections official limits, and self-host sizing are unconfirmed.
