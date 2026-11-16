# 11 - Market size and industry facts for Ridgeline Ops

Date: 2026-11-16. Labels: [E] = evidence from a fetched/searched source (URL given); [I] = inference/estimate by me. Secondary sites are flagged; none of the Census tables were pulled directly (only via secondary summaries), so verify before external use.

## 1. Business counts and size
- [E] Employer landscaping establishments (NAICS 561730), 2023 CBP: 117,969; employment 802,899; payroll $41.2B; avg 6.8 employees/establishment; avg payroll ~$349k/establishment. https://startbusinessbystate.com/landscaping-industry-statistics/ (secondary, cites Census CBP). Count also at https://www.highergov.com/naics/561730-landscaping-services/
- [E] Nonemployer (solo) landscaping businesses, 2023: 516,572; avg receipts ~$36k; ~81% of all landscaping businesses are nonemployer (2022: ~82% of counts, 13.5% of revenue). https://startbusinessbystate.com/service-nonemployer-share-by-state/ (secondary, cites Census NES). Official: https://www.census.gov/data/developers/data-sets/nonemp-api.2004.html
- [E] BLS QCEW 124,018 landscaping establishments with employees (2026 Q1), per the same secondary page. Other dataset: 123,316 firms / 902,592 jobs (2024). https://smbdensity.sitesbytiff.workers.dev/industry/561730
- NOT FOUND: the employer size-class split (1-4, 5-9, 10-19, 20+) for 561730 and 561790. Census CBP table would give it. [I] Given mean 6.8 employees, the distribution is heavily skewed: my estimate is ~55-65% of employer establishments have <5 employees, ~10-15% have 10+. Treat as a range, not data.
- [E] Snow: SIMA's 2017 impact study: ~110,000 workers in private snow/ice, ~88,000 (~80%) sole practitioners; $16.8B private-contract market; top 4 firms <5% of revenue; segments residential 34%, retail 27%, industrial 26%. https://www.facilitiesnet.com/site/pressreleases/SIMA-Research-Shows-that-Removing-Snow-Under-Private-Contract-is-a-168-Billion-Industry--38875 ; https://www.buildings.com/articles/28533/private-snow-removal-168-billion-industry . Data is 2016-17 and counts workers, not businesses.
- Typical revenue: [E] solo ~$36k receipts (above). Employer revenue per establishment not found; [I] ~$0.5M-$0.9M (payroll $349k at an assumed 40-60% of revenue), so 1-3 crew shops are likely $100-500k.
- Share 1-3 crews vs 10+: NOT FOUND. [I] Of all businesses, ~95%+ are solo or 1-3 crews; 10+ crews is likely <2% of businesses but a large share of revenue.

## 2. Snow businesses that also do landscaping
- [E] SIMA: most snow operators work in other industries, landscaping the most common; only 8% do snow exclusively. https://landscapearchitect.com/landscape-articles/special-section-snow-and-ice-management (search summary; the exact landscaping % was not retrievable). Full report: https://sima.org/snow-industry-impact-report
- [E] NALP: snow is ~15-25% of revenue for landscapers in seasonal markets. https://blog.landscapeprofessionals.org/should-i-stay-or-should-i-snow-plow/
- [I] Implied: roughly 60-90% of snow operators also do landscaping or grounds work, so an all-in-one app is well aligned.

## 3. Tool adoption
- [E] 2017 Software Advice survey: 83% of landscaping companies use some software; 74% industry-specific. https://www.totallandscapecare.com/business/article/15040642/software-advice-notes-software-features-landscapers-want (old, vendor-sponsored). L&L: contractors adopt field tech faster than back-office; >67% give employees cell phones. https://www.lawnandlandscape.com/article/ll0814-landscapers-technology-research
- Vendor blogs say paper/spreadsheets/whiteboards "remain prevalent" with no percentage (https://www.youraspire.com/blog/manual-processes-in-landscaping). Aspire 2026 survey (510 commercial pros): https://www.youraspire.com/guides/2026-landscaping-tech-trends-report
- NOT FOUND: a current, neutral software vs spreadsheet vs paper split. [I] The 83% likely overstates small shops (solos count as "software" if they use QuickBooks or texting). Estimate: dedicated field-service software 25-40% of employer firms, <15% of solos; the rest spreadsheets/paper/texts. Competitors: Jobber, Housecall Pro, Aspire, Service Autopilot, Plowsite etc.

## 4. iPhone vs Android
- [E] US smartphone share 2025: iPhone ~57-60%, Android ~40-42% (StatCounter-based roundups). https://searchengineland.com/guide/iphone-vs-android-statistics ; https://backlinko.com/iphone-vs-android-statistics . Conflicting: eMarketer-sourced table lists more Android users (133M) than iPhone (118M); PhoneArena claims Apple 75% of Q1 2026 US sales (unclear measure). https://www.phonearena.com/news/us-smartphone-market-report-q1-2026-apple-clear-leader-motorola-closing-in-on-samsung_id180316
- NOT FOUND: iPhone share among trades/small-business owners. [I] Blue-collar and lower-income cohorts skew Android versus the general population; use 45-65% for trades, 55% central. Treat as the biggest unvalidated assumption; validate with a survey or Jobber/Housecall Pro data.

## 5. Seasonality
- [E] Mix guidance: ~60-70% seasonal, 20-30% per-event, ~10% other (adviser/vendor guidance, not a census); MSU extension notes the seasonal share is the key risk variable. https://www.youraspire.com/blog/snow-removal-contracts-pricing-volatility ; https://www.getjobber.com/academy/snow-removal/how-to-bid-snow-removal/
- NOT FOUND (not retrieved): authoritative season-length and snow-state counts. [I] Snow work is meaningful in ~25-28 northern/mountain states, roughly Nov-Mar (4-5 months); landscaping peaks Apr-Oct. Complementary seasons support a year-round subscription, but crew count differs by season (plow trucks and drivers vs mowing crews).

## 6. Insurance, contract, liability norms
- [E] Contracts commonly require additional-insured endorsements CG 2010 (ongoing ops) and CG 2037 (completed ops), primary/non-contributory wording, and indemnity/hold-harmless; subcontractors must carry equivalent coverage. https://resources.sima.org/snow-and-ice-resource-center/ongoing-services-and-additional-insured-liability-in-snow-removal ; https://www.sima.org/insurance ; https://www.getjobber.com/academy/snow-removal/insurance-for-snow-removal-contractors/
- [E] Slip-and-fall claims often arise after the plow leaves, so carriers and defense counsel value time-stamped records. Ordinary landscaping GL may exclude snow work. https://www.quotesweep.com/insurance-for/snow-removal ; https://www.nextinsurance.com:443/business/snow-plowing-insurance
- [I] Feature implications: geotagged and timestamped before/after photos per visit, GPS breadcrumb and truck-in-lot dwell time, salt/material logs, weather snapshot at service time, COI storage with expiry alerts, sub COI tracking, exportable per-site incident logs (retain 3+ years, since claim statutes are typically 2-3 years), tamper-evident records.

## 7. Bottom-up serviceable market (all [I], assumptions explicit)
Serviceable crew-based businesses (SAM-businesses): employer establishments (~118k) plus paying solo operators with a truck or crew. Low 60k / mid 100k / high 150k. Reasoning: solos at $36k receipts are unlikely buyers of $29/mo software; I count only a minority of the 517k nonemployers plus snow-only sole plow operators. SAM is limited to US, with snow or landscaping crews (not restricted to snow states because landscaping is included).
Apple-only share: low 50%, mid 58%, high 65%.
- Apple-only SAM: low 30k, mid 58k, high 97k businesses.

Pricing at average 3 crews: Pro = 29 + 2x25 = $79/mo; Max = 79 + 2x39 = $157/mo. Blended at 70% Pro / 30% Max = ~$102/mo per account. Caveat: the 6.8 average employees per employer establishment suggests most firms have 1-2 crews, not 3; at 2 crews, Pro = $54, Max = $118, blended ~$73.

| Case | Accounts @1% | MRR @1% | Accounts @3% | MRR @3% |
|---|---|---|---|---|
| Low (30k) | 300 | $30.7k | 900 | $92k |
| Mid (58k) | 580 | $59k | 1,740 | $178k |
| High (97k) | 970 | $99k | 2,910 | $298k |
Mid case ARR: ~$0.7M at 1%, ~$2.1M at 3%. Mid case all-Pro: $45.8k / $137k MRR; all-Max: $91k / $273k MRR.

## Gaps to close
Census CBP size classes for 561730/561790 (query the API); SIMA full impact report (landscaping overlap, business count); a neutral device-share survey of trades; a current software-adoption survey. Do not quote the [I] figures externally as facts.
