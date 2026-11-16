# 05 - Marketing, Time Clock/Payroll, Payments (research)

Date: 2026-11-16. Method: web search summaries only (no direct page fetches). Labels: [E] = evidence from a cited source; [I] = my inference. Most pricing comes from third-party aggregators/blogs that disagree with each other; verify on vendor pages before committing. No verbatim quotes are used; complaints are paraphrased.

## A. Marketing / email / reviews

### Complaint themes
1. Contracts, cancellation, billing surprises on enterprise-style reputation tools (Podium especially). [E] Capterra reviewers cite hard cancellation, unresponsive support, ongoing charges; terms reportedly annual. https://www.capterra.com/p/164285/Podium/reviews/2500812/ and https://wisernotify.com/blog/podium-alternatives/ (blog, vendor-competitor, lower reliability).
2. Add-on/fee stacking. [E] Birdeye per-location pricing plus per-user, 10DLC, phone-number and AI add-ons (figures from a competitor blog, treat cautiously). https://www.truereview.co/post/birdeye-vs-podium-vs-nicejob-vs-truereview-an-honest-comparison
3. Pay-per-lead marketplaces. [E] FTC action vs HomeAdvisor (alleged overstated lead quality/conversion; $7.2M settlement, refunds to contractors; no admission of wrongdoing). https://techcrunch.com/2023/01/23/the-ftc-fines-homeadvisor-up-to-7-2m-for-lying-about-lead-quality-and-other-matters ; FTC complaint PDF https://www.ftc.gov/system/files/ftc_gov/pdf/D9407HomeAdvisorComplaintProvisionallyRedacted.pdf . Anecdote of same lead sold to several contractors is a trade-site comment, not a finding.
4. Jobber Marketing Suite itself: little specific criticism found; [E] G2 users report campaigns reactivating old leads. Main complaints are cost stacking (add-on + per-user + processing). https://www.g2.com/products/jobber/ (not fetched; via search summary). Evidence on Housecall Pro / ServiceTitan Marketing Pro / Mailchimp / Constant Contact / Thryv / Thumbtack: NOT gathered (gap).

### Pricing benchmarks
- Jobber Marketing Suite add-on: $79/mo (Reviews, Campaigns, Referrals), not on Lite. [E] https://help.getjobber.com/hc/en-us/articles/26197554098967
- NiceJob: ~$75 Reviews, ~$125 Pro; reportedly month-to-month. [E, third-party] https://www.g2.com/compare/nicejob-vs-podium
- Podium ~$399-599/mo; Birdeye ~$299-449/location/mo. [E, estimates; vendors don't publish]

### Must-have vs nice-to-have
Must (MVP): automated review request after job completion (SMS+email, Google link); quote follow-up reminders (auto nudge for unaccepted quotes); seasonal/renewal reminders (snow contract renewal, spring cleanup, aeration); templated SMS/email to segmented customers; opt-out/consent handling (TCPA/10DLC) [I].
Nice: referral program, review widgets, AI replies, drip campaigns, postcards, competitor insights, lead marketplaces integration.
Skip: lead-gen marketplace, full CRM-marketing builder, social posting [I].

### Recommendation
Bundle review requests + quote follow-up + renewal/seasonal SMS/email into base tier (or cheap add-on well below $79). Differentiator [I]: snow-specific triggers (pre-season contract renewal, "storm complete" messages with timestamp/photo). Send via a transactional provider; budget SMS cost and 10DLC registration [I]. No contracts.

## B. Time clock / crew / payroll

### Complaint themes
1. Battery drain from GPS tracking. [E] Capterra Workyard reviews: https://www.capterra.com/p/215558/Workyard/reviews/6424328/ ; ClockShark: https://g2.com/products/clockshark/reviews?page=13 . Competitor critique (biased): https://www.jibble.io/reviews/clockshark/5-reasons-clockshark-sucks
2. Unwanted automatic clock-ins/outs and geofence gaps. [E] Workyard reviewer reports auto clock-in when driving past a site off-hours (Capterra link above); ClockShark reportedly doesn't auto clock-out on leaving geofence (review summaries via search; secondary source).
3. Per-user + base-fee pricing creep. [E, aggregator] QuickBooks Time base fee + per-user; figures uncertain. https://www.capterra.com/compare/151722-153140/TSheets-vs-Connecteam
4. Buddy punching, offline reliability, prevailing wage: NOT verified with sources [I: expect as real concerns; photo/selfie punch and offline queueing are standard asks].
Homebase/Connecteam/Gusto-specific complaints: not found (gap).

### Pricing benchmarks (aggregators, approximate)
Workyard ~$6-13+/user/mo; QuickBooks Time ~$8-10/user + $20-40 base; Connecteam ~$29/mo flat up to 30 users (sources conflict); Homebase free basic, ~$24/location. https://www.capterra.com/p/215558/Workyard/pricing/ ; https://costbench.com/compare/connecteam-vs-homebase/

### Must vs nice
Must: per-job clock in/out tied to scheduled job; offline-first punches syncing later; timesheet approval and export (CSV, QuickBooks, Gusto/payroll file); low-power location (significant-change / region monitoring, not continuous GPS) [I]; manual edit with audit trail; overtime rules.
Nice: GPS breadcrumbs for disputes (critical for snow: proof of service times), job costing (labor vs job revenue), geofence auto-prompts (prompt, not silent auto-punch), photo punch, mileage, prevailing wage, direct payroll.
[I] Use iOS region monitoring and notifications ("You arrived at X, start timer?") to avoid battery and false auto-punch complaints. Per-user fees are a pain point; consider crew-unlimited or cheap seats.

### Recommendation
MVP: per-job timer + shift clock, offline, prompted geofence, timesheet approval, export to payroll/QuickBooks, labor cost per job. Defer direct payroll (Gusto integration/export later), prevailing wage, breadcrumbs v1.5 (opt-in, snow-event mode).

## C. Payments / accounting

### Complaint themes
1. Payout holds/delays and account limits. [E] Housecall Pro help center: first payout up to 7 business days, some ACH under review up to 7 days, volume limits, Instapay +1%. https://help.housecallpro.com/en/articles/2046930 ; https://help.housecallpro.com/en/articles/8114232-payments-processing-limits ; BBB complaints on holds (64 complaints/3 yrs): https://prod.bbb.org/us/ca/san-diego/profile/marketing-software/housecall-pro-1126-1000067843/complaints . Jobber: weak AI-summary signal of holds (low reliability).
2. Fee opacity and stacking beyond the headline rate. [E] Housecall Pro notes monthly/PCI/chargeback/reader fees. https://www.housecallpro.com/learn/credit-card-processing-for-small-business
3. QuickBooks sync friction. [E] Jobber's own help documents duplicate-client/product errors and legacy limit on one payment covering multiple invoices; a community thread reports deposits not matching invoices. https://help.getjobber.com/hc/en-us/articles/10466688449431-Common-QuickBooks-Sync-Errors-and-How-to-Fix-Them ; https://community.getjobber.com/discussions/integrations/quickbooks-deposits-not-matching-invoices/2733/replies/5002 . Duplicate-invoice claim only from a consultancy sales page (weak).
4. Chargebacks: no source gathered (gap).

### Rate benchmarks
- Stripe: 2.9%+30c online; ACH 0.8% cap $5; Terminal 2.7%+5c; Tap to Pay on iPhone reported +10c/authorization on Terminal rate. Third-party aggregators, not stripe.com. https://www.nerdwallet.com/business/software/learn/stripe-fees ; Connect fees unverified.
- Jobber Payments: ~2.9%+30c online, ~2.5%+10c in-person (conflicting source says Tap to Pay 2.7%+30c), ACH ~1% (cap unconfirmed). https://paymentproviders.io/compare/stripe-vs-jobber-payments?focus=fees ; https://www.getjobber.com/features/field-service-credit-card-processing/
- Housecall Pro: advertised 2.59% (tiered up to ~2.99%/3.49% per third parties), ACH ~1%.

### Margin opportunity (inference, show-your-math)
Interchange-plus via a payfac/Stripe Connect: Stripe base ~2.9%+30c; if we charge merchants 2.9%+30c we earn ~0 on Stripe-standard pricing unless negotiated Connect/volume pricing or interchange+ gives wholesale cost ~2.3-2.6% [I, unverified]. Realistic take: 0.2-0.5% on card volume, and ACH at 1% vs 0.8% cost (cap $5 vs our cap) gives ~0.2% margin. Example: contractor processing $15k/mo, 60% card -> $9k*0.35% = ~$31 + ACH $6k*0.2% = ~$12 -> ~$40/mo/account (rough). Snow contracts skew to ACH/checks and invoices after storms; large commercial invoices make ACH cap valuable. Do not pursue payfac registration at MVP.

### Must vs nice
Must: card on file, pay link on invoice/text, Tap to Pay on iPhone, ACH, clear payout schedule (next-day standard), dispute handling UI, QuickBooks Online sync that maps one deposit to many invoices and avoids duplicates.
Nice: instant payout, autopay for seasonal contracts (snow flat-rate monthly billing), surcharging/convenience fees (check state law), financing, tipping.

### Recommendation
Use Stripe Connect (standard/express) with transparent flat rate, published payout timing; take small application fee; marketing line: "no holds beyond Stripe's standard." Build QuickBooks sync with batch deposit reconciliation as a headline feature. Autopay/recurring billing for snow contracts is high value [I].

## Gaps
No direct vendor page fetches; ServiceTitan Marketing Pro, Mailchimp, Constant Contact, Thryv, Thumbtack, Gusto, Homebase complaints, chargeback data, prevailing wage not researched. Pricing figures unverified against official sources.
