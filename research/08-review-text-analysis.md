# 08 - App Store review text analysis (US store)

Date of collection: 2026-11-16. Source: Apple's public customer-reviews RSS/JSON feed (`/us/rss/customerreviews/page=N/id=<ID>/sortby=mostrecent/json`, pages 1-10) and the public iTunes Search API for app IDs. Nothing else was used: no WebSearch/WebFetch, no scraping tools, no mirrors. Requests were sequential with a 2 s pause. The only throttle encountered was one HTTP 429 from the Search API (waited, then continued); nothing was blocked with 403/login/captcha.

## Method and limits (read first)
- **US App Store only, most recent reviews only.** The feed returns at most 10 pages x 50 = 500 reviews per app, newest first. Jobber (500) reaches back to 2021-12, Housecall Pro (500) only to 2023-12, Route4Me (500) to 2023-03, so samples are not equal time windows. Small apps returned everything the feed offered (often far fewer than the app's total rating count, since many ratings have no text).
- **Total analyzed: 3,055 reviews across 19 apps, of which 1,362 were 1-3 star and coded.** (3,411 fetched; 356 reviews from "Aspire Account Center" were dropped because it is a credit-card app, not Aspire Software.)
- **Coding is keyword/regex based, multi-label** (one review can hit several themes). From hand-reading about 8 random hits per theme I estimate precision at roughly 65-80% (e.g. "support" and "billing" are cleaner; "price", "missing features" and "time clock" pick up some false positives such as "free trial", "can't add", "clock out" in a billing complaint). Counts are indicative, not exact; recall is also incomplete. Quote theme labels are the keyword match, so a few quotes fit a neighbouring theme better.
- The sample is **biased toward unhappy and heavy users** (we only code 1-3 star); average rating of the sample is for the fetched window, not the store's lifetime rating (e.g. Jobber lifetime 4.81 vs 3.68 in its latest 500).
- Quotes are lightly truncated; dates are review dates. Reviewer names omitted.
- Raw data: `/home/user/snow-app/research/data/appstore_reviews_us_coded.csv` (all 3,055 analyzed reviews, text capped at 700 chars, ~0.9 MB). Theme column is filled for 1-3 star rows only.

## Coverage and gaps
| Requested app | Result |
|---|---|
| Jobber, Housecall Pro, Service Fusion, GorillaDesk, Workiz, FieldPulse, Route4Me, Workyard | Found (main app), analyzed |
| Aspire | Only "Aspire Mobile" (crew app, 15 reviews, ID 1637098541) analyzed; thin sample |
| LMN | Only "LMN Crew" (12 reviews) exists in the US store; LMN's main product is web |
| OptimoRoute | Only "OptimoRoute Driver" (12 reviews); the planner is web |
| Plow360 | App found (ID 6740414156) but 1 rating and no review text; **not analyzable** |
| Yeti Snow | No clearly matching app. "Yeti Software" (2 reviews) is the nearest hit; unconfirmed it is the same product. Treat as no data |
| Other snow/lawn apps added | Lawn Buddy (software), plus contractor-side marketplaces LawnStarter for Providers, GreenPal Pro, Lawn Love for Providers, LawnGuru Pro, Shovler (on-demand snow), Quikplow (mostly consumer side, 15 reviews). Marketplaces are kept in a separate ranking because their complaints are about job supply and payouts, not software |
| Not searched | Service Autopilot, Real Green, Arborgold-type products: search API rate-limited briefly and I did not retry; not covered |

## Cross-app theme ranking (share of 1-3 star reviews carrying the theme)
**Core operations/FSM/routing/time apps (13 apps, 1,995 reviews, 778 coded 1-3 star):**
| Rank | Theme | Count | Share |
|---|---|---|---|
| 1 | Bugs / crashes / slowness | 218 | 28% |
| 2 | Support | 153 | 20% |
| 3 | Billing / cancellation | 141 | 18% |
| 4 | Price | 128 | 16% |
| 5 | Missing features | 123 | 16% |
| 6 | UI / usability | 82 | 11% |
| 7 | Routing / maps | 77 | 10% (40 of them Route4Me) |
| 8 | Sync / offline / uploads / notifications | 40 | 5% |
| 8 | Time clock / GPS | 40 | 5% |
| 10 | Payments holds / payout delays | 33 | 4% |
| 11 | QuickBooks | 18 | 2% |

**Contractor marketplaces (6 apps, 1,060 reviews, 584 coded):** price/low pay 156 (27%), support 108 (18%), billing/cancellation/deactivation 94 (16%), missing features 90 (15%), payout holds/delays 83 (14%), bugs 76 (13%).

**All apps combined (1,362 coded):** bugs 294, price 284, support 261, billing/cancel 235, missing features 213, payments holds 116, UI 103, routing 92, sync/offline 48, time clock/GPS 42, QuickBooks 18.

Reading across apps:
- Reliability of the mobile app (crashes, lag, photo upload failures, forced re-login, update regressions) is the top complaint for field-crew apps; it dominates LMN Crew, Aspire Mobile, Service Fusion, GorillaDesk, Lawn Buddy.
- The big-FSM apps (Housecall Pro, Workiz, FieldPulse, Jobber) are hit hardest on **billing/cancellation and support**: cancelling requires a phone call, charges after cancellation, annual-plan lock-in, "free trial" conversions, sales-rep promises, slow or unreachable support. Workiz: support 23 and billing 21 of 59 coded.
- Payments holds/payout delays are a real but second-tier theme in Jobber (18 of 184) and Housecall Pro (13 of 276, incl. card reader and onboarding underwriting); they are the main marketplace complaint. Ridgeline Ops skipping payments in v1 avoids this risk category but also forgoes a thing contractors compare on.
- QuickBooks is rare (18 mentions, mostly Jobber/HCP, e.g. duplicated invoice numbers breaking QBO sync). Not a loud complaint but a visible one.
- Snow-specific signal is very thin: only 3 core-app reviews mention snow/plow at all (an Aspire Mobile user saying the forced re-login "is not effective for snow plowing", a Route4Me user whose combined driveway for two addresses is not routed consecutively, and the Yeti one). Snow contractors do not appear as a distinct voice in this data.

## Most requested missing features / pain-points (core apps, 1-3 star, mentions with request or complaint language; rough counts)
Noisy keyword counts across 778 reviews: estimates/quotes/invoice editing issues 76; customer comms (text, email, phone features) 49; photo upload/attachments 43; push notifications/alerts 30; recurring/repeat job and calendar control 24; home-screen widget / faster mobile UX 19; search of jobs, customers, work orders 16; inventory/materials/equipment 11; live GPS tech tracking 10; QuickBooks/accounting 10; offline mode 9; route optimization/multi-stop 8; time-clock edits 4; bulk actions 4; weather/snow triggers 4. Broad terms like "estimate" and "invoice" also capture generic complaints, so the top counts overstate pure feature requests. Concrete requests quoted verbatim in reviews: offline mode (Jobber, Service Fusion), live location tracking (Jobber), widget to clock in and change job status (Service Fusion), cancellation option on job status (Service Fusion), searchable work order history (Housecall Pro), flexible recurring events on mobile (Housecall Pro), adjust hours for missed clock in/out and a customer map view (Housecall Pro), photos on equipment records (Housecall Pro), background photo upload, optional inactivity timeout (Aspire Mobile), CarPlay and trucking-aware routing (Route4Me), consecutive stops for shared driveways (Route4Me), per-role price visibility (Jobber).

## Takeaways for Ridgeline Ops (evidence-based)
1. Reliable offline-first capture with background photo upload, and no forced re-logins, is the most credible differentiator against crew apps.
2. Transparent pricing and a self-serve in-app cancel/export are directly answering the second and third biggest complaints against large FSM vendors.
3. Real support access is a recurring wedge (Workiz, FieldPulse, Housecall Pro, Lawn Buddy).
4. Time clock/GPS complaints are about battery/"always" location permission and auto clock-out (Workyard) and missed-punch edits; design permissioning carefully.
5. Do not over-read snow demand from this data; it is a gap to fill through interviews.

## Per-app results
For each app: reviews fetched, average rating of the sample, count of themes among 1-3 star reviews, and the most recent matching quotes for the top themes.

### Jobber Field Service Software
- Reviews fetched: 500 (dates 2021-12-21 to 2026-11-14); average rating of sample 3.68; 1-3 star reviews coded: 184 (36%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 43, price 40, billing/cancellation 36, support 35, missing features 29, UI/usability 21
- Dated quotes:
  - (bugs/crashes/slow) 2026-10-21, 1-star: "Terrible Slow and inconvenient - Don’t start your business with Jobber like we did. So many inconveniences and quirks that delay our payouts and leave us starving for our pay. Get Quickbooks. It’s a CRM (client relations..."
  - (price) 2026-10-09, 1-star: "WORST APP - The app does not let you in fully after you’ve entered your business information. Then they talk about “you’ve entered a free trial” without showing you the price of the trial . Bare foolishness. Do not download and..."
  - (billing/cancellation) 2026-08-22, 2-star: "Owner stronger plumbing - The app actually seems great. Unfortunately in my case I was promised by a salesman trying to close a deal that I would be omramoed by them. After days of hard work and months on the program I’m still..."

### Housecall Pro: Field Service
- Reviews fetched: 500 (dates 2023-12-12 to 2026-11-12); average rating of sample 2.98; 1-3 star reviews coded: 276 (55%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 72, support 66, missing features 50, billing/cancellation 50, price 41, UI/usability 28
- Dated quotes:
  - (bugs/crashes/slow) 2026-11-02, 1-star: "Terrible - Terrible, from the bugs, to the customer service. They make things so complicated and their prices are ridiculous."
  - (support) 2026-08-18, 1-star: "Absolute terrible support - They have a phone support. Called them two times regarding the same issue. Non of two people knew anything about their own policies and Housecall’s programs. I also spent two days with their email..."
  - (missing features) 2026-08-31, 3-star: "Meh - The website software is great, but the mobile app is seriously lacking in functionality for techs.  Recurring events don’t work well. They require a lot of manual work to copy and paste and are not flexible at all. You..."

### Service Fusion (id 1042544405)
- Reviews fetched: 68 (dates 2015-12-14 to 2026-11-03); average rating of sample 2.54; 1-3 star reviews coded: 48 (70%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 21, missing features 15, UI/usability 6, routing/maps 5, sync/offline/uploads/notifications 5, time clock/GPS 3
- Dated quotes:
  - (bugs/crashes/slow) 2026-11-03, 1-star: "Fix uploading photos - Trash app wont let us upload pictures now. Fix this now or were changing services and the other company too were gonna knock it down if you dont fix this. Such a god awful trashy garbage app."
  - (missing features) 2025-03-07, 3-star: "Not a bad app - This app works great for the most part. The one thing I wish they would add on a job status option screen they had a cancellation option."
  - (UI/usability) 2021-04-16, 1-star: "Freezes up - New update does not open resetting phone don’t help need help to fix this issue"

### GorillaDesk
- Reviews fetched: 77 (dates 2015-08-24 to 2026-09-30); average rating of sample 4.08; 1-3 star reviews coded: 19 (24%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 6, missing features 3, support 2, billing/cancellation 2, routing/maps 1, price 1
- Dated quotes:
  - (bugs/crashes/slow) 2026-09-01, 1-star: "Terrible app - I hate this app, they are constantly updating adding terrible buggy features that dont work trying to keep up."
  - (missing features) 2025-01-24, 3-star: "Update errors - If they could do an update and not screw something else up every single time that would be great!"

### Workiz Field Service Software
- Reviews fetched: 94 (dates 2019-09-04 to 2026-08-04); average rating of sample 2.55; 1-3 star reviews coded: 59 (62%).
- Top themes (count of 1-3 star reviews, multi-label): support 23, billing/cancellation 21, bugs/crashes/slow 15, price 14, UI/usability 7, missing features 7
- Dated quotes:
  - (support) 2026-06-25, 1-star: "Don’t even attempt - This is by far the worst platform and service out there ! There is absolutely no help or onboarding ! Save your time and find something else !"
  - (billing/cancellation) 2026-05-08, 1-star: "Can’t cancel my subscription, stupid rules. - Workiz took our money for an annual plan even though we asked to cancel our account.  We would like to request a refund. Your team hasn't been responding to us since April 28th..."
  - (bugs/crashes/slow) 2025-04-21, 1-star: "Worst app- terrible customer support - This app never works and has been the worst decision our business has made. So glitchy and causes interruptions to our daily operations constantly. Support and customer service is terrible."

### FieldPulse
- Reviews fetched: 29 (dates 2022-03-13 to 2026-08-31); average rating of sample 3.24; 1-3 star reviews coded: 13 (44%).
- Top themes (count of 1-3 star reviews, multi-label): support 7, bugs/crashes/slow 3, billing/cancellation 3, UI/usability 2, price 2, missing features 2
- Dated quotes:
  - (support) 2025-11-13, 1-star: "Terrible service - The customer service is worse than the actual software and phone service and that’s saying a lot. Do not waste your time."
  - (bugs/crashes/slow) 2025-06-26, 1-star: "Poor software - The app has all the basics of what could be a good field service app. The app is constantly closing out, constantly glitching and deleting my data, and I’ve had to delete the app and sign back in just to load a..."
  - (billing/cancellation) 2025-01-27, 1-star: "Custom service - I emailed them 5 days before renewal to cancel and they still held the payment out on renewal date. I have contacted customer service about the renewal and receiving a refund. They called me to find out why I was..."

### Aspire Mobile (Aspire Software crew app)
- Reviews fetched: 15 (dates 2024-12-03 to 2026-09-25); average rating of sample 1.73; 1-3 star reviews coded: 13 (86%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 8, sync/offline/uploads/notifications 2, time clock/GPS 1, routing/maps 1, UI/usability 1, price 1
- Dated quotes:
  - (bugs/crashes/slow) 2026-09-25, 1-star: "Don’t download - 10/10 wouldn’t recommend auto logs you put doesn’t save any Of your progress or photos if you clock in and for get to close the app it will just clock you out app suck slow laggy and photos don’t upload"
  - (sync/offline/uploads/notifications) 2026-01-27, 2-star: "Time out - The inactivity timeout sucks. I now have to login before and after each job. Either remove it or make it optional!!! Might gain some stars if things are made more user friendly on both the mobile and desktop ends"
  - (routing/maps) 2026-01-31, 1-star: "Bugs bugs bugs - Can’t stand this app it always kicks me out when I’m in route and after every job making me log back into it everytime and this is not effective for snow plowing or any job for that matter this app sucks look at..."

### LMN Crew
- Reviews fetched: 12 (dates 2024-04-02 to 2026-08-27); average rating of sample 2.58; 1-3 star reviews coded: 10 (83%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 9, UI/usability 3, routing/maps 2, time clock/GPS 2, missing features 2, billing/cancellation 1
- Dated quotes:
  - (bugs/crashes/slow) 2026-08-27, 1-star: "Update is trash - After the recent update the app is now super slow and lags trying to do anything. Scrolling through pages or adding parts went from a 1minute task too a 10min task"
  - (UI/usability) 2025-04-09, 1-star: "New update - Ever since the new update my app keeps crashing and overloading my phone"
  - (routing/maps) 2025-06-09, 1-star: "My guys hate the app - Terribly buggy and laggy. Trouble loading a long route with anything over 20 stops.  Issues with sensing guys to go get materials as they have to clock into the job tomorrow be able to track what materials..."

### Route4Me Route Planner
- Reviews fetched: 500 (dates 2023-03-13 to 2026-11-12); average rating of sample 4.24; 1-3 star reviews coded: 97 (19%).
- Top themes (count of 1-3 star reviews, multi-label): routing/maps 40, bugs/crashes/slow 21, billing/cancellation 17, price 16, UI/usability 10, missing features 9
- Dated quotes:
  - (routing/maps) 2026-10-21, 1-star: "Efficiency, but… - This app saves time and gas. However, there way better route apps for free. This is a rip off!!"
  - (bugs/crashes/slow) 2026-08-14, 1-star: "No Trucking/ RV Guidance in Newer Versions - Bought the app not knowing my friends were grandfathered in to the trucking routes.   Paid for a year and now they won’t let me out.    ***App does not work with CarPlay!!! So you’ll..."
  - (billing/cancellation) 2026-09-03, 3-star: "Good - Great for routes, but I have to renew my subscription every month it’s annoying but other then that works great"

### OptimoRoute Driver
- Reviews fetched: 12 (dates 2018-02-13 to 2026-06-18); average rating of sample 3.08; 1-3 star reviews coded: 9 (75%).
- Top themes (count of 1-3 star reviews, multi-label): routing/maps 5, time clock/GPS 3, support 2, sync/offline/uploads/notifications 1, missing features 1, bugs/crashes/slow 1
- Dated quotes:
  - (routing/maps) 2025-03-26, 2-star: "It’s ok - Dropping pins in the wrong location makes the start navigation button not worth using most of the time so I just type the name of the place in an actual gps and save myself a complete headache as this app has flaws ...."
  - (support) 2021-01-12, 2-star: "Support? - What support. Called hours ago with questions how to use the application and haven’t yet to hear back from anyone. No phone number to be found. Looked promising but no support doesn’t work for us."

### Workyard GPS Time Tracking
- Reviews fetched: 84 (dates 2021-01-14 to 2026-08-24); average rating of sample 4.20; 1-3 star reviews coded: 17 (20%).
- Top themes (count of 1-3 star reviews, multi-label): time clock/GPS 6, bugs/crashes/slow 4, billing/cancellation 3, UI/usability 2, missing features 2, price 2
- Dated quotes:
  - (time clock/GPS) 2026-07-07, 3-star: "Working Man - Needs improvement ,seems to not let you put in time off unless you go in and clock in. The part of the app that questions when it can track, you does not like to work unless you have ,always tracking selected."
  - (bugs/crashes/slow) 2026-04-01, 2-star: "Not a fan - It's frustrating to have to switch tracking off each time. "Location only when using" doesn't work. You have to select "always" in order to use. I don't like the idea of constantly being tracked and having to remember..."
  - (billing/cancellation) 2025-04-24, 1-star: "They will keep charging you after cancellation - I have been charged for nearly 2 years now after cancellation, do not sign up with this company, they have billed me nearly 2400.00 after cancellation,"

### Yeti Software (possibly Yeti Snow; unconfirmed)
- Reviews fetched: 2 (dates 2021-11-22 to 2024-10-06); average rating of sample 1.50; 1-3 star reviews coded: 2 (100%).
- Top themes (count of 1-3 star reviews, multi-label): support 1, bugs/crashes/slow 1, routing/maps 1, time clock/GPS 1
- Dated quotes:
  - (support) 2021-11-22, 2-star: "Does not support IPhone XS or Iphone 11 - Having issues wouldn’t allow me click map direction by address location. Only works other stuffs as photo, weather, etc. expect won’t work click of address location guide of gps doesn’t..."

### Lawn Buddy Management Software
- Reviews fetched: 102 (dates 2017-09-28 to 2026-09-01); average rating of sample 3.85; 1-3 star reviews coded: 31 (30%).
- Top themes (count of 1-3 star reviews, multi-label): bugs/crashes/slow 14, support 8, price 8, billing/cancellation 6, routing/maps 3, missing features 3
- Dated quotes:
  - (bugs/crashes/slow) 2026-07-01, 1-star: "Bugs in the app, unreachable customer service - Do not use this app if you are a professional. The app has countless bugs that will slow you down and make a mess of any you try to keep organized. Nothing but problems. Customer..."
  - (support) 2024-06-09, 1-star: "DONT USE WILL RIP YOU OFF - Even after canceling my subscription they still charged me. Customer service is a joke."
  - (price) 2026-01-12, 2-star: "Not worth it - I had high hopes for this app but it’s super basic and very expensive. There’s software not even 10% more that has EVERYTHING this app doesn’t. Have to delete it"

### LawnStarter for Providers (marketplace)
- Reviews fetched: 276 (dates 2015-08-10 to 2026-11-14); average rating of sample 2.44; 1-3 star reviews coded: 187 (67%).
- Top themes (count of 1-3 star reviews, multi-label): price 57, support 46, payments holds/payout delays 36, billing/cancellation 25, missing features 23, bugs/crashes/slow 16
- Dated quotes:
  - (price) 2026-05-07, 2-star: "Professional - As a professional landscaper,etc. the pay out for these gigs are just sooo low. I like to app just wish they would payout what the jobs be truly worth. 0.016 acres is not small so at least pay out $65 for front and..."
  - (support) 2026-06-21, 1-star: "You won’t get your money - I have waited and contacted support multiple times and I haven’t gotten my first pay even though they say they will pay me"
  - (payments holds/payout delays) 2026-08-15, 1-star: "Tip baiting - They allow customers to remove tips that you have already received in payouts from several weeks before. Then they deduct from your current payouts."

### GreenPal Pro for Vendors (marketplace)
- Reviews fetched: 145 (dates 2018-05-29 to 2026-10-30); average rating of sample 2.22; 1-3 star reviews coded: 108 (74%).
- Top themes (count of 1-3 star reviews, multi-label): price 25, support 24, payments holds/payout delays 19, missing features 18, bugs/crashes/slow 17, billing/cancellation 11
- Dated quotes:
  - (price) 2026-10-30, 2-star: "Low priceS - It has very low prices for areas, you need to update your prices by postal codes"
  - (support) 2026-07-13, 1-star: "Tips - This app owner loves keeping part of the tips  They are so money hungry   Unlike LawnStarter they let you keep 100% tips  I’m probably going to tell the customers from GreenPal, if they want to continue lawn service, they..."
  - (payments holds/payout delays) 2026-06-08, 1-star: "Stripe sucks - The app is okay but they make you use stipe to get your money. You are more likely to get scammed by stipe than you are to get your money. They should be you the option to use Apple Pay,  Venmo or PayPal. You know..."

### Lawn Love for Providers (marketplace)
- Reviews fetched: 109 (dates 2022-02-25 to 2026-11-02); average rating of sample 2.36; 1-3 star reviews coded: 74 (67%).
- Top themes (count of 1-3 star reviews, multi-label): payments holds/payout delays 13, price 13, support 12, missing features 7, bugs/crashes/slow 6, billing/cancellation 4
- Dated quotes:
  - (payments holds/payout delays) 2026-08-31, 1-star: "Deactivated without reason - Woke up to the not working 2 days later I called to find out what’s going on and he couldn’t tell me anything other than I was deactivated and not able to reactivate. I asked about my payouts her said..."
  - (price) 2026-09-08, 1-star: "Do not partner up with them at all. Warning. - Man, I did two jobs. The first job. It looks like the yard hasn't been cut for about a whole year and they only charge them $38. I was out there for four hours straight, just for the..."
  - (support) 2025-06-07, 1-star: "Scam - Wasted my time and gas showing up to customer houses just for them to cancel without notifying me. Then when I call customer support they say no reimbursement for time/gas"

### LawnGuru Pro (marketplace)
- Reviews fetched: 97 (dates 2020-02-07 to 2026-10-30); average rating of sample 3.46; 1-3 star reviews coded: 37 (38%).
- Top themes (count of 1-3 star reviews, multi-label): billing/cancellation 13, price 11, bugs/crashes/slow 9, support 7, payments holds/payout delays 5, missing features 3
- Dated quotes:
  - (billing/cancellation) 2025-12-03, 1-star: "Unprofessional - Listen up Contractor. These people run this business from their , they are for one charging double the price for what they're offering as a contract to contractors. They deduct your money when they want without..."
  - (price) 2026-02-13, 1-star: "As a company - This simply drives down market pricing for services. If you’re an established company. Don’t waste your time"
  - (bugs/crashes/slow) 2025-02-08, 1-star: "Poor business practices - Providers be aware, this app pays Pennie’s on the dollar to what they’re receiving. Further, this app often experiences bugs and issues preventing the work. They also unassign jobs without a reason or..."

### Shovler: Snow Removal OnDemand (marketplace)
- Reviews fetched: 418 (dates 2016-10-22 to 2026-03-04); average rating of sample 3.48; 1-3 star reviews coded: 169 (40%).
- Top themes (count of 1-3 star reviews, multi-label): price 48, billing/cancellation 39, missing features 37, bugs/crashes/slow 27, support 16, payments holds/payout delays 9
- Dated quotes:
  - (price) 2026-02-24, 1-star: "Horrible! - Different scheduled shovelers canceled three times and each time the price went up by $80 to $100. This app wants over $200 to shovel a small driveway. Even then,  nobody would probably show up. Absolute insanity."
  - (billing/cancellation) 2026-01-27, 3-star: "Works most of the time - The service has worked most of the time. Had a problem once but the company refunded the excess amount paid. Work however was not completed leaving me snowed in and frustrated."
  - (missing features) 2026-02-24, 1-star: "Shovler never showed - Terrible reliability.  Shovler assured me that they would come over chat and never showed up.  No way to talk to support in real time.  Missed a medical appointment as a result.  Do not use."

### Quikplow (on-demand plowing, mostly customer side)
- Reviews fetched: 15 (dates 2022-01-05 to 2025-01-22); average rating of sample 2.60; 1-3 star reviews coded: 9 (60%).
- Top themes (count of 1-3 star reviews, multi-label): support 3, missing features 2, billing/cancellation 2, price 2, sync/offline/uploads/notifications 1, payments holds/payout delays 1
- Dated quotes:
  - (support) 2023-05-03, 1-star: "No responses - Made several requests throughout the winter for plowing and never heard anything. Deleted the app."
  - (missing features) 2024-01-13, 1-star: "I keep getting a grey screen very frustrating - I requested service however I am not able to see any update on the app because the app is grey.  No way to see if request is pending or accepted this is very frustrating."
  - (billing/cancellation) 2023-03-13, 1-star: "Scam - I tried to use this once and got no response to my job until a day later when I had already found someone to shovel my drive. It was critical because I just had surgery and needed a way for the nurse to visit. I was..."
