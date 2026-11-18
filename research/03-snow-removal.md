# 03 - Snow Removal Research

Date: 2026-11-16. Labels: [E] = evidence from a cited source; [I] = inference.
IMPORTANT LIMITATION: Web search returned almost exclusively vendor marketing/blog pages. No PlowSite, Reddit, or Facebook threads were retrievable, so operator pain points below are vendor-described, NOT first-hand operator voices. Direct forum research (manual browsing of plowsite.com, r/snowplow) is still needed before finalizing priorities.

## 1. Competitive landscape
- Aspire: positioned as the commercial snow platform, estimating to crew mgmt to invoicing; one roundup says best for snow-only commercial >$1M revenue [E, vendor/affiliate]. https://www.youraspire.com/industries/snow-removal-management-software
- LMN: landscape+snow, ProSnow module (estimating, budgeting, pre-season contracts); Starter listed ~$297/mo in one table [E, secondary; pricing sources conflict $59-$648/mo across tools]. https://sourceforge.net/software/snow-removal
- Others named: Upper Crew (routing; Pro tier $48/user/mo yearly claimed), Plow360, SnowBossPro, Yeti Snow (GPS proof/sub tracking), SnowLink, Smart Service, Contractor+, QuoteIQ, Jobber, Plowz & Mowz (on-demand marketplace) [E, vendor-ranked]. 
  - https://www.upperinc.com/blog/best-snow-plow-tracking-app-for-contractors.md
  - https://yetisoftware.com/
  - https://contractorplus.app/blog/9-best-snow-removal-software-platforms-in-2026
  - https://www.smartservice.com/blog/snow-removal-contracts-guide
- SnowPro, Snow Wizard, Snow Dragon: no usable results found.
- [I] Market is split: enterprise-heavy (Aspire/LMN) vs. light route/GPS tools. A native Apple, owner-operator-to-mid-size all-in-one with snow-first billing logic appears to be a gap, but unverified without user reviews.

## 2. Pain points / needs (vendor-described)
Sources: https://contractorplus.app/blog/snow-removal-software-buyers-guide-features-that-win-seasonal-profit ; https://www.youraspire.com/blog/snow-risk-management-subs-slips-salt ; https://www.raftlabs.com/blog/how-to-build-snow-removal-management-software
- Contract types: per-push (trigger depth), seasonal flat, per-inch/event, time-and-materials, hybrids (seasonal base + per-push over a storm-count cap). Seasonal bills on calendar regardless of snow; per-push bills per event [E].
- Missed/under-billed pushes; seasonal caps tracked manually; late invoices after events [E].
- Chaotic storm response: group texts, mid-storm re-routing [E].
- Slip-and-fall: need timestamped GPS + before/after photos; claims can arrive ~18 months later; property camera footage may overwrite in 30-90 days; evidence pack per visit; trigger log (temp, precip type, depth, start/end) [E, Aspire - recommendations not research].
- Subs: insurance ($2M GL / $1M auto / workers comp / additional-insured; flag expiry 30 days out), backup sub per route, check-ins at start/50%/finish, "no-photo/no-pay", post-storm scorecards (on-time %, proof completeness, callbacks), mid-storm rate renegotiation, sub can't start truck at 2am [E].
- Salt/material: per-site default rates, quick logging, inventory deduction, cost by account/route/storm, mid-storm shortages [E].
- Clients/property managers want screenshots/timestamps; portal for status [E].
- NOT found (gap): "did you come?" call volume, no-show claim data, driver pay norms (hourly vs per-push vs per-lot), breakdown handling. Treat as [I] from founder experience.

## 3. Weather data
- NWS api.weather.gov: free, "open data, free for any purpose"; undisclosed rate limits (retry ~5s); User-Agent required (API key planned); 2.5km grid forecasts, alerts (7 days), observations (7 days, up to 20 min delay); GeoJSON; US only; no SLA [E]. https://www.weather.gov/documentation/services-web-api
- Apple WeatherKit: 500k calls/mo included with Developer Program; paid 1M/mo $49.99 up to 200M/mo $9,999.99; no rollover; attribution required [E]. https://developer.apple.com/weatherkit/get-started/ . Snowfall-accumulation forecast fields exist [I - verify in docs].
- Tomorrow.io: free tier ~500 calls/day, reported non-commercial only; paid tiers unclear/sales-led [E, secondary]. https://support.tomorrow.io/hc/en-us/articles/23554984091156-Tomorrow-io-Pricing-Overview
- OpenWeather One Call 3.0: ~1,000 free calls/day then pay-per-call [E, secondary; verify].
- [I] Recommended: WeatherKit (native, covered by dev membership) for forecast snowfall + NWS alerts (winter storm warnings) as free backup/alert layer. Cache per-region, not per-site, to stay within limits. Forecasts are guidance; actual trigger depth should be crew-/sensor-confirmed and logged.

## 4. Market size
- US+Canada private snow & ice mgmt ~ $23B (Landscape Architect; undated) and SIMA-cited $16.8B private contract (older). Global ~$17.1B in 2026 (Research and Markets) - definitions conflict. https://landscapearchitect.com/landscape-articles/special-section-snow-and-ice-management ; https://www.researchandmarkets.com/reports/6243941/snow-removal-services-market-outlook-market
- US business count / typical revenue: NOT reliably found (a blog cites 300k+ workers, unsourced). Needs IBISWorld/Census NAICS 561730/561790 lookup. Do not cite figures above without verification.

## 5. Prioritized snow-specific features
| # | Feature | Evidence | MVP? |
|---|---|---|---|
| 1 | Timestamped GPS+photo proof of service per visit, organized by site/storm, exportable evidence pack, long retention | [E] all vendors; Aspire risk guide | MVP |
| 2 | Contract billing engine: per-push, seasonal, per-inch/trigger, hybrid with cap/overage, T&M; auto invoice per event/season | [E] ContractorPlus, Smart Service | MVP |
| 3 | Storm event object: trigger depth per site, weather snapshot logged (WeatherKit/NWS), storm-type presets (plow/salt/both) | [E]+[I] | MVP |
| 4 | Fast crew mobile flow: route list, one-tap arrive/depart (geofence), offline-tolerant, 3am dispatch push notifications | [I]+[E] | MVP |
| 5 | Dispatch map and mid-storm reassignment, backup sub/driver swap | [E] | MVP (basic), later (optimization) |
| 6 | Salt/material logging with per-site default rates and cost per storm | [E] | MVP-lite, later: inventory |
| 7 | Sub management: COI/insurance expiry tracking, no-photo/no-pay, scorecards, pay per hour/push/lot | [E] Aspire | Later (COI+pay basic MVP) |
| 8 | Customer notifications/portal ("we came" with photos) to cut status calls | [E] ContractorPlus; [I] call volume | MVP-lite (auto text/email), portal later |
| 9 | Weather-trigger alerts to owner ("2-4 in forecast, these 30 sites hit trigger") | [E]+[I] | Later |
| 10 | Equipment/breakdown tracking, fuel, truck assignment | [I] | Later |
| 11 | Seasonal contract renewals, pre-season quoting by lot size | [E] LMN | Later |

## 6. Open items
Verify via manual forum review; confirm Apple WeatherKit snowfall fields/terms; get real US business count; check Aspire/LMN user reviews (G2/Capterra) for complaints.
