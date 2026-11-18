# 13. Onboarding, Profile/Settings, Sign-in and UI principles for Ridgeline Ops

Labels: **[E]** = evidence (URL given, fetched/searched 2026-11-18). **[I]** = inference / recommendation. Nothing is quoted unless it was returned verbatim by a fetch of the cited page.

## 0. Blocked / unverified
- Workiz help article `help.workiz.com/en/articles/4130602-getting-started-with-workiz` returned HTTP 403 to fetch. Not circumvented. Workiz facts below come only from search-result summaries (weaker evidence).
- No fetch of GorillaDesk, LMN, Service Fusion or Square help-center pages succeeded in giving step lists; only search summaries. Those are labelled "summary".
- Jobber sign-in methods: no Jobber help article found that confirms Google/Apple sign-in. Treat as unverified.
- Competitor App Store descriptions (Jobber via iTunes search API) do not mention sign-in.
- Apple's Guidelines page fetch covered the first 100,000 of ~114,000 characters; items quoted below were all inside that range. Apple revises guidelines, so re-check the live page before submission.

## 1. What competitors ask during setup

### Jobber [E]
Basic setup, 7 steps, admin only, under gear > Settings (https://help.getjobber.com/en/articles/first-steps-basic-account-set-up/): Company settings (name, phone, email, address as clients see them, ~5 min); Business profile (logo, quote/invoice/job templates, ~10); Personal settings; Tax rates (~10); Add your team; Jobber App (team sees schedules, logs time); Jobber Payments (~10).
"Just for Core" guide adds Customize templates (email/text messages) and Products and services (import list) (https://help.getjobber.com/en/articles/first-steps-just-for-core/). That guide does not cover client import. Each step carries a time estimate. App Store listing (https://apps.apple.com/us/app/jobber-field-service-software/id1014146758) lists quotes, scheduling/dispatch, invoicing/payments, client communication, QuickBooks Online/Gusto/Stripe integrations; trades named include landscaping.
Payments: two steps, verify business details then bank account for deposits; only owners can do it (search summary of Jobber help).

### Housecall Pro [E]
Getting started (https://help.housecallpro.com/en/articles/11115983-getting-started-with-housecall-pro), in order: 1 Company profile (name, address, support email, website, industry, description, logo, invoice/receipt/estimate messages, terms); 2 Add employees (roles/permissions); 3 Add or import customers (one at a time, CSV, QuickBooks, phone contacts); 4 Price book (services, materials); 5 Bank account for payouts (Plaid or manual, verify business and owners); 6 Custom SMS number registration; 7 Estimate, invoice, payment settings.

### Others (summary-level evidence only)
- Workiz [E-weak, search summary of help.workiz.com]: company name, address, website, email, phone, logo; customize job types, ad groups, tax rates; service areas.
- GorillaDesk [E-weak, https://gorilladesk.com/academy/getting-started/settings/assign-schedules/ summary]: after signup, first step is customizing account settings; ships a preloaded, editable materials list; billing is per route; 14-day trial, no card.
- Service Fusion [E-weak, search summary of its help center]: implementation specialist reviews company info, preferences, payments, QuickBooks, workflow; checklist = company info/settings, logo, employees and permissions, payment gateway, email notifications; add taxes/fees/discounts during setup; Data Import Wizard for customers, service locations, service agreements.
- LMN [E-weak, golmn.com summaries]: free account, link QuickBooks Desktop/Online to import customers and leads; paid "Starter Launch" guided group session. Reviewers describe the software as complex [E-weak, Capterra]. Landscape estimating is cost/budget-driven.
- Square [E-weak, https://squareup.com/help/us/en/article/5123-square-get-started-guide summary]: business name, type and category early; identity verification; "Set up your team" late (Step 8).

### Cross-vendor pattern [I, from the above]
Common order: company identity > logo/templates > tax > team > customers/price list > payments > messaging. Heavy items (bank verification, SMS registration, QuickBooks, imports) are separated from the identity questions. Nobody found asks "what do you do" via a long questionnaire; they use a checklist after signup, plus human onboarding for larger plans. Our guided 10-step welcome is a deliberate step above that, so it must be shorter per screen than their forms.

## 2. Profile and settings areas (competitors)
Housecall Pro settings [E] (https://help.housecallpro.com/en/articles/7919484-settings-page-overview): Global (Company incl. business hours and service area zip codes, Billing, Notifications, Refer a Friend, Login Authentication = 2FA); Feature configs (Booking, Customer Intake, Customer Portal, Estimates, Inbox, Invoices, Jobs incl. time tracking and job costing, Job Inbox, Leads, Marketing Center, Pipeline, Price Book incl. tax rates and labor rates, Schedule incl. route templates and crew assignments, Service Plans); Tags and Tools (Checklists, Job Fields, Lead Sources, Tags).
Jobber [E]: gear icon: company settings, business profile/templates, personal settings, tax rates, team and permissions, payments (from first-steps article above).
Observation [I]: web-era settings have 20+ sections; on iPhone this needs grouping and search. Per-person profile is split from company settings in Jobber; copy that.

## 3. Sign-in
### Competitors
- Housecall Pro [E, search summary of https://help.housecallpro.com/en/articles/6390055-how-to-log-in-to-housecall-pro]: email+password always; "Continue with Google" on mobile; Apple sign-in mentioned but article wording is inconsistent; 2FA exists in settings. Field techs mobile-only; admin/office on web and mobile.
- Jobber: troubleshooting article implies email+password; Google/Apple not confirmed [E-weak].
- Others: not verified.

### Apple rules (verbatim from https://developer.apple.com/app-store/review/guidelines/)
**4.8 Login Services:** "Apps that use a third-party or social login service (such as Facebook Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon, or WeChat Login) to set up or authenticate the user's primary account with the app must also offer as an equivalent option another login service with the following features: the login service limits data collection to the user's name and email address; the login service allows users to keep their email address private as part of setting up their account; and the login service does not collect interactions with your app for advertising purposes without consent."
Exceptions include: "Your app exclusively uses your company's own account setup and sign-in systems." and "Your app is an education, enterprise, or business app that requires the user to sign in with an existing education or enterprise account."
**5.1.1(v) Account Sign-In:** "If your app doesn't include significant account-based features, let people use it without a login. If your app supports account creation, you must also offer account deletion within the app."
(The Guidelines text links the deletion clause to https://developer.apple.com/support/offering-account-deletion-in-your-app/.)

Account deletion page [E] (https://developer.apple.com/support/offering-account-deletion-in-your-app/): "Apps submitted to the App Store that support account creation must also let people initiate deletion of their account within the app." Also: "Make the account deletion option easy to find in your app. Typically, it's included in the app's account settings."; "only offering to temporarily deactivate or disable an account is insufficient."; apps "should not require people to make a phone call, send an email, use a chat support flow"; for Sign in with Apple use the REST API to "revoke user tokens"; for subscriptions, tell people billing continues through Apple; scheduled deletion allowed if immediate deletion is also offered.

HIG Managing accounts [E] (https://developer.apple.com/design/human-interface-guidelines/managing-accounts.md): "Delay sign-in for as long as possible."; "If you don't use Sign in with Apple in your iOS, iPadOS, macOS, or visionOS app, prefer using a passkey."; "Avoid using the term passcode to refer to account authentication."; "In general, avoid offering an app-specific setting for opting in to biometric authentication."; deletion: "you must also help them delete it, not just deactivate it."
Note: the user's brief lists "passcode" as a sign-in option. HIG says avoid that word for account auth. Use "Face ID / Touch ID app lock" via system biometrics only if needed, not a custom passcode.

### Recommendation [I]
1. Sign in with Apple (primary button, first position), plus email + one-time code or passkey. Skip Google at launch: if Google is added, 4.8 requires Sign in with Apple be offered too (we would anyway). Since Ridgeline would use its own account system plus Apple, the 4.8 exception for "exclusively your company's own" is not needed to rely on.
2. Passkeys instead of passwords where possible (HIG preference); email OTP as fallback for crew members on shared devices.
3. Owner creates the business account; crew join by invite link/code and role (no business questionnaire for them). Client portal: separate magic-link sign-in, no app account.
4. Delete account lives at Settings > Profile > Delete account (in app). Owner deletion must explain what happens to the business data, crew, invoices retained for tax/legal reasons, and active subscriptions; offer export first; revoke Sign in with Apple tokens; show completion time. Legal retention must be described to the user (HIG managing accounts).
5. Per 5.1.1(v), let people explore (sample route, demo data) before account creation if feasible; account is justified because data syncs and crew/clients share it.
6. Mac: same Apple ID sign-in; Settings via Command-comma.

## 4. HIG points that apply [E]
All from developer.apple.com/design/human-interface-guidelines/ (.md pages fetched).
- Onboarding: "design a flow that's fast, fun, and optional."; "design a brief, enjoyable experience that doesn't require people to memorize a lot of information."; "Postpone nonessential setup flows or customization steps. Provide reasonable default settings so most people can immediately start interacting with your app or game without performing additional configuration."; permissions: request in onboarding only "if your app or game needs access to private data or resources before it can function"; otherwise ask at first use; "Avoid displaying licensing details within your onboarding flow."; if a tutorial is skipped "don't present it again", keep it findable in help/account/settings. (onboarding.md)
- Settings: "Minimize the number of settings you offer."; "Aim to provide default settings that give the best experience to the largest number of people."; "Avoid using settings to ask for setup information you can get in other ways."; do not duplicate system settings (accessibility, authentication); put task-specific options in the screens they affect; macOS: Settings item in App menu, Command-Comma, panes in a toolbar, restore last pane. (settings.md)
- Layout: "Order content by relative importance."; "Group related items"; "Use progressive disclosure to make layouts cleaner"; use size classes not device type; "Keep functionality the same as size classes change", tab bar can become sidebar on larger spaces; support Dynamic Type; respect safe areas; macOS: "Avoid placing controls or critical information at the bottom of a window." (layout.md)
- Liquid Glass (layout.md, current 2026 text): use it for controls, "Instead of applying a solid or semi-opaque background color beneath controls, use a scroll edge effect".
- Not fetched/verified: Typography, Color, Sign in with Apple button-spec pages (a search summary said the button must be no smaller than other sign-in buttons; unverified at source).

## 5. Patterns that make onboarding feel short [mix]
- [E] HIG: optional, defaults, postpone nonessential (above). Jobber shows per-step time estimates (~5/10 min) [E].
- [I] Show "Step 3 of 10" plus a thin bar; each screen one question; primary button bottom, Skip as text button; Back always works; answers autosave so quitting resumes.
- [I] Prefill from what we know: Apple name/email, device locale (currency, units, tax region), time zone, season (October-March = snow-forward).
- [I] Big tappable choice cards instead of keyboards (gloves, truck cab, cold hands). Minimize typing: 3 typed fields in the whole flow (business name, tax rate if not detected, optional phone).
- [I] Defer heavy items to a "Finish setup" checklist on Home: bank verification, SMS registration, QuickBooks, bulk import, logo polish (Housecall Pro and Jobber both make these separate steps [E]).
- [I] Required vs skippable: only business name and services-type are required; everything else has a default.
- [I] End on a working screen (sample route or first-client prompt), not a summary.

## 6. Recommended 10-step onboarding (snow and landscaping owner)
Screen 0 (not counted): Sign in with Apple / email / passkey. Welcome headline one line.

| # | Question | Answer type | Why we ask | Configures | Skip? |
|---|---|---|---|---|---|
| 1 | What is your business called? (prefill from Apple name) | Text; optional phone, optional "your name" | Appears on quotes, invoices, portal, storm texts | Company profile, document headers, portal title | No (only required field) |
| 2 | What do you do? | Multi-select cards: Snow plowing, Salting/de-icing, Shoveling/walks, Lawn mowing, Landscaping/install, Cleanups, Other | Drives terminology and the template library | Service catalog, default quote templates, seasonal Home layout, dashboard widgets | No (default: Snow + Lawn) |
| 3 | Who do you serve? | Multi-select: Homes, Commercial/lots, HOAs, Municipal | Sets pricing models and storm-trigger rules | Client types, default contract/trigger templates, invoice terms | Yes (default: Homes+Commercial) |
| 4 | How do you charge for snow? | Multi-select: Per push/visit, Per inch bracket, Seasonal flat, Hourly, Per event | Snow billing differs from lawn | Pricing models, snowfall trigger (inches) and depth-tier fields, seasonal contract invoicing | Yes (default: per visit) |
| 5 | Where do you work? | Home base address (autocomplete), service radius slider; optional "use current location" | Route start/end, dispatch distances, tax region | Depot for route optimization, service area, tax/time-zone/units defaults | Yes (skip: set later) |
| 6 | Who works with you? | Stepper: Just me / 2-5 / 6-15 / 16+; optional "invite crew" share sheet | Turns on crews, roles, per-person time clock | Team mode on/off, role defaults, crew routes, time-clock visibility | Yes (default: just me) |
| 7 | Do you have existing customers? | Choice: Import from contacts / CSV or spreadsheet / QuickBooks / Start fresh | Fastest value is a loaded client list | Client import, property records; heavy import deferred to Finish-setup checklist | Yes |
| 8 | How do you get paid? | Multi-select: Card, ACH/bank, Check, Cash, e-transfer; terms (Due on receipt / Net 15 / Net 30) | Invoice and portal pay options | Invoice defaults, payment methods shown, reminder cadence; Stripe-style payout verification deferred to checklist | Yes (default: Card+Check, Net 15) |
| 9 | Sales tax and rates | Detected rate from address with edit; toggle "Taxable services" per category; optional "I do not charge tax" | Wrong tax is costly; many snow services are tax-exempt in some jurisdictions [I, unverified, confirm per state] | Tax rates, per-service tax flags, invoice totals | Yes (default: detected rate; flag to review) |
| 10 | Look and notifications | Logo upload (camera/photos/skip), one accent color from 6 swatches, then notification toggles: storm alerts, new request, payment received, crew clock-in; system permission prompt shown here with reason | Brand on client-facing items; permissions requested with context (HIG) | Brand theme on quotes/invoices/portal, push/SMS prefs, notification permission | Yes (default: no logo, standard accent, all alerts on) |

Finish: "You're set" screen with 3 next actions (add first client, build today's route, send a test storm message) and a persistent "Finish setup" checklist (bank/payout verification, SMS number registration, QuickBooks link, invite crew, import list, invoice templates). Personal profile (photo, phone) is reachable from Profile, not asked here.
Rationale [I]: steps follow the cross-vendor order (company, taxes, team, customers, payments, templates) from section 1 but compress to answer-type cards, with the snow-specific additions (billing model, trigger depth, home base). Steps 2-4 are the only snow/landscape-specific questions and they unlock templates, so keep them first.
Time budget [I]: aim under 3 minutes with all skips; 10 screens at ~15 seconds each.

## 7. Recommended Profile and Settings sections [I, informed by section 2]
Profile (person): photo, name, email, phone, sign-in methods (Apple, passkey, email) and linked methods, role, personal notification overrides, appearance (follows system), Sign out, Delete account (in-app; see section 3).
Settings, grouped (iPhone: one grouped list with search; iPad/Mac: sidebar with panes, Command-Comma on Mac):
1. Business: name, logo/brand, address and hours, service area, license/insurance number.
2. Services and Pricing: service catalog, snow pricing models and trigger depth, materials (salt, mulch), labor rates, markups.
3. Quotes and Invoices: numbering, terms, due dates, late fees, templates, default messages, signature.
4. Payments and Taxes: payment methods, payout/bank verification, tax rates and exemptions, tips/deposits.
5. Team and Time Clock: members, roles/permissions, crews, pay rates, geofence/clock rules, overtime.
6. Schedule and Routes: home base, route start/end, work hours, season dates, weather/trigger sources.
7. Clients and Portal: portal branding, what clients can see/do, approval and pay options, intake/request form.
8. Messaging and Notifications: storm message templates, SMS sender registration, quiet hours, push/email toggles.
9. Data and Integrations: import/export, QuickBooks, calendar, backup.
10. Subscription and Billing (our plan).
11. Privacy and Security: 2FA/passkeys, devices, data requests.
12. Help, Legal, About: contact, replay tips (HIG: tutorials findable later), terms, privacy, version.
Rules: keep per-task options inline (route filters, job view options live on those screens, per HIG); do not duplicate system-level options like accessibility or Face ID toggles; a "Finish setup" card at the top until the checklist is done.

## 8. UI principles for a clean, sleek look [I, tied to HIG evidence where noted]
1. One job per screen, one primary action, bottom-anchored for thumb reach. (HIG: order by importance [E])
2. Use native components and system materials (SwiftUI lists, sheets, NavigationSplitView, Liquid Glass for controls) rather than custom chrome; do not put solid fills under toolbars. [E layout.md]
3. Restrained palette: neutral surfaces, one brand accent (cool "ridge" blue or slate) and semantic colors for status only (green paid, amber due, red overdue, ice-blue for storm). Verify contrast in light and dark.
4. Generous whitespace and grouped inset lists; separate sections by space and headers, not heavy borders. [E: group with negative space]
5. Type: SF system font, 3 sizes visible per screen, large title on top-level screens, full Dynamic Type support with stacking layouts. [E]
6. Big touch targets (at least 44 pt, prefer 52 pt for primary buttons) and card choices; design for gloves and glare; avoid small toggles in dense rows. (44 pt figure is from general Apple practice, not re-verified in this pass.)
7. Progressive disclosure: summary rows, details on tap; advanced settings collapsed. [E]
8. Adaptive layout via size classes: tab bar on iPhone, sidebar on iPad/Mac, same functionality everywhere, multi-column on wide windows; Mac gets menus, keyboard shortcuts, Command-comma settings; avoid key controls at window bottom. [E]
9. Status at a glance: a Today screen with the next stop, storm banner, unpaid total; use SF Symbols and numerals, not charts, for the busy owner.
10. Meaningful empty and loading states with one action ("Add your first client"); skeletons instead of spinners; offline-friendly indicators for rural routes.
11. Motion and haptics sparse: subtle transitions, a success haptic on "route done"/"payment received"; respect Reduce Motion.
12. Copy: short, plain trade language ("push", "salt run", "visit"), no jargon, no marketing in setup screens.

## 9. Open items to verify before build
- Per-state sales tax on snow removal and landscaping (not researched).
- Current Sign in with Apple button spec page and passkey implementation notes.
- Confirm Jobber/Workiz/GorillaDesk/Service Fusion sign-in methods by trial signups (not allowed here; public docs did not confirm).
- Typography, color and accessibility HIG pages (touch target sizes) not fetched this pass.
