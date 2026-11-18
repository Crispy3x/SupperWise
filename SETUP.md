# What you need to do

**Already have an Apple Developer account?** `CHROME-BRIEF-TESTFLIGHT.md` is a ready-to-paste brief for Claude in Chrome that does the clicking from the Apple and GitHub websites up to the upload, and stops for payments, agreements and secrets.

**Shortcut for the browser steps:** `CHROME-BRIEF.md` is a ready-to-paste brief for Claude in Chrome. It does the account clicking (Apple Developer, App Store Connect, Google Cloud, hosting, build results, name checks) but stops for payments, passwords, identity and legal agreements, which only you can do.

I built everything I could without a Mac, accounts or keys. These steps need you. Do them in order; each one says what to send me if it goes wrong.

## 1. Run the app on your Mac (about 30 minutes)
You need a Mac with **Xcode 16 or newer** (free in the Mac App Store).
1. `brew install xcodegen` (or download it from the XcodeGen GitHub page).
2. In this folder, edit `project.yml`: change `com.example` to your own identifier (two places) and put your Apple Developer team ID in `DEVELOPMENT_TEAM`. A free Apple ID works for running on your own devices.
3. Run `xcodegen`, then open `RidgelineOps.xcodeproj`.
4. Pick an iPhone simulator and press Run (Cmd+R). Then try "My Mac".
5. **Expect compile errors the first time.** The screens were written and reviewed but never compiled, because SwiftUI only builds on Apple platforms. **Copy the full list of errors (or a screenshot) and send it to me. I fix them and you pull again.**
6. On the Customers tab tap **Load demo data**, then try Storm, Crew, Invoices, Quotes, Routes, Time clock, Job costs, Proof.
7. Run the logic tests too: `swift test` (143+ should pass).
Send me: the build errors, then screenshots of each tab once it runs.

## 2. Apple Developer account (needed to put it on other phones and the App Store)
- Join the Apple Developer Program ($99 per year).
- In Xcode, Signing & Capabilities: pick your team. Turn on automatic signing.
- Add the app in App Store Connect with your bundle ID.
- For testers: archive and upload to TestFlight (Product > Archive > Distribute).

### Getting onto TestFlight (after step 1 builds cleanly)
What to have ready: Apple Developer Program membership; your bundle ID and team ID in `project.yml`; the app name (App Store names are unique, "Ridgeline Ops" may be taken, so have a second choice); a support email; a privacy policy web address (only for outside testers); the testers' email addresses.
1. App Store Connect > Apps > New App: platform iOS, name, language, bundle ID (it appears once the ID is registered, Xcode registers it with automatic signing), SKU (any text you like).
2. In Xcode choose "Any iOS Device (arm64)", then Product > Archive, then Distribute App > App Store Connect > Upload. The build shows in TestFlight after Apple finishes processing (minutes to an hour).
3. Internal testers (up to 100 people you add as App Store Connect users): no review, they can install as soon as processing ends. Start with these.
4. External testers (anyone with an email or a public link): needs a short Beta App Review (usually a day or two), a privacy policy address, a contact email, and notes on what to test. Add the group after internal testing works.
5. Testers install the TestFlight app, accept the invite, and need iOS 17 or newer.
The app icon is in `App/Assets.xcassets` (a first draft, replace it whenever you have a real logo; it must stay 1024 by 1024 with no transparency).

### TestFlight without a Mac: let GitHub build and upload it
`.github/workflows/testflight.yml` builds the iPhone and iPad app on GitHub's Mac machines and uploads it to TestFlight. **It has never been run.** The first run may fail on a compile error or a signing detail; send me the log.

Before the first run you need (in this order):
1. **Apple Developer Program membership** (step 2 above) and your **Team ID**.
2. **Register your bundle ID**: developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > + > App IDs. Use the prefix you chose plus `.ridgelineops` (for example `com.yourbusiness.ridgelineops`). **Tick the "Sign in with Apple" capability** for it: the app now offers it, so signing fails without it.
3. **Create the app in App Store Connect** (New App) with that bundle ID. The upload fails if this record does not exist.
4. **Create an App Store Connect API key**: appstoreconnect.apple.com > Users and Access > Integrations > App Store Connect API > Team Keys > Generate. Name it "GitHub builds" and give it the **Admin** role (it needs permission to manage signing certificates). Download the `.p8` file (Apple shows it **only once**) and note the **Key ID** and the **Issuer ID** shown at the top of that page. **This key can manage your Apple account: only ever put it in GitHub secrets, never in a chat, email or file in this repository, and never give it to me or to Claude in Chrome.** Delete the key in App Store Connect when you no longer need it.
5. **Add five secrets** in GitHub: your repository > Settings > Secrets and variables > Actions > New repository secret:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8_BASE64`: the `.p8` file turned into one line of text. On a Mac: `base64 -i AuthKey_XXXX.p8 | pbcopy`. On Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | Set-Clipboard`. On Linux: `base64 -w0 AuthKey_XXXX.p8`. Paste it only into the GitHub secret box.
   - `APPLE_TEAM_ID`: your 10-character Team ID
   - `BUNDLE_ID_PREFIX`: for example `com.yourbusiness` (the workflow adds `.ridgelineops`)
6. Check that the **CI** workflow is green first (the "Build the app project" job compiles the app the same way, without signing). If it is red, send me its log: the TestFlight run would fail the same way.
7. **Merge this branch into your repository's default branch first.** GitHub only shows the "Run workflow" button for a workflow file that is on the default branch. Then GitHub > Actions > **TestFlight** > Run workflow. It takes roughly 10 to 20 minutes. Then open App Store Connect > your app > TestFlight: the build appears after Apple finishes processing, and you can add internal testers.

If the app already exists in TestFlight, add a `BUNDLE_ID` secret with that app's exact full bundle ID (then `BUNDLE_ID_PREFIX` is not needed), and use that app's exact bundle ID and a version number (`MARKETING_VERSION` in `project.yml`) at or above the one there. The workflow numbers builds with a UTC timestamp, so the build number is always higher than earlier ones.

**Replacing the old Superwise app:** upload Ridgeline Ops as a new version of the existing Superwise app record. Find Superwise's exact bundle ID in App Store Connect > the app > App Information, put it in the `BUNDLE_ID` secret, and add an `APP_VERSION` secret set above Superwise's latest version (for example 2.0.0). You can rename the app in App Store Connect > App Information. Existing testers get the update through TestFlight. The Superwise bundle ID also needs the Sign in with Apple capability ticked.

Cost note: GitHub counts Mac minutes at 10 times the normal rate on private repositories, so a free account's monthly allowance covers only a handful of runs. Check your plan's limits.

## 3. Subscriptions (the 14-day free trial and Pro and Max)
**Not built yet: buying a plan.** The trial clock runs on the device only. To finish it I need these decisions from you:
- **Where to bill:** the App Store (Apple takes 15% to 30%, the trial is an "introductory offer") or your own website with Stripe (you keep more, Apple's rules for linking out are still changing). I suggested web billing as the main route.
- **App Store subscriptions are fixed products**, so per-crew pricing needs bundles: for example Pro for 1, 3, 5 and 10 crews, and the same for Max. Tell me which crew counts you want.
- Create the products in App Store Connect with a **14-day free introductory offer**, then send me the product IDs.
- Optional: RevenueCat can tie App Store and web purchases together.

## 4. Live traffic routing (Google) - OPTIONAL
**The app now uses Apple Maps on the device by default, which needs no account, key or hosting. Skip this whole step unless you want the Google option.** Before launch, ask Apple developer support or a lawyer whether using Apple Maps drive times for crew route planning fits Apple's terms (see the Apple Maps routing section of `README.md`); this step is your backup plan.
The routing server is built and tested against a stand-in, never against real Google.
1. Create a Google Cloud account and a project. **Set a budget alert first** (Billing > Budgets) so a mistake cannot run up a bill.
2. Turn on the **Routes API**.
3. Create an API key, restrict it to the Routes API only, and (if your host has a fixed address) restrict it by IP.
4. Read Google's current Maps Platform terms on caching and on using results without a Google map. If unsure, ask a lawyer. A free alternative (Valhalla) is possible; ask me.
5. Host `server/` somewhere that gives you HTTPS (Render, Fly.io, Railway, a small VPS). Set these as secrets there: `GOOGLE_MAPS_API_KEY`, `API_TOKENS` (make up a long random token per customer), and set `DAILY_ELEMENT_CAP` to what you can afford (the default is 3000 lookups a day, about $30 a day at the list price I found, so lower it for a quiet beta). Details are in `server/README.md`.
6. In the app: Settings > Live traffic routing > enter the server address and a token.
7. Test with a small route and check Google's billing page the next day.
Send me: any error from the server logs, and a screenshot of the Storm tab saying "Drive times from your routing server".

## 5. Weather
The free National Weather Service feed works with no key (US only). Before release open `Sources/RidgelineUI/AppModel.swift`, find `weatherUserAgent`, and put your app name and a contact email there, as the NWS asks. Do not use a personal email you want kept private; use a support address.

## 6. Legal, brand and store pages (before any customer pays)
- **Name:** run a trademark search for "Ridgeline Ops" (USPTO.gov, free) and check the domain and the App Store name. My web search found no software with that exact name, but that is not clearance.
- **Privacy policy and terms of service** pages (required by the App Store). Say plainly that: customer site locations go to your routing server and to Google; the yard location goes to the weather service; typed addresses go to Apple's lookup; photos stay on the device for now.
- **App Store privacy answers** (App Store Connect > App Privacy) and `App/PrivacyInfo.xcprivacy`: they must match what the app really does. I left the collected-data list empty on purpose. Fill it in with a lawyer or the App Store's own guide.
- **Founding-member promise** (free payments feature later): settle the wording, who qualifies, and for how long, then have a lawyer glance at it. Draft is in `PLAN.md`.
- **Support email and a way to cancel**: the plan promises one-tap cancel and data export. Cancel and export screens are not built yet.

## 7. Talk to owners (this decides what I build next)
Use `research/INTERVIEW-SCRIPT.md`. Aim for 10 to 15 snow and landscaping owners. Send me the notes or your top findings: which phone crews use, what they pay now, what they hate, what they would pay.

## What I still need from you, in one list
1. Xcode build errors and screenshots (step 1).
2. Your bundle ID and team ID (step 2), if you want me to set them in the files.
3. Billing choice and crew bundles (step 3).
4. Result of a real Google test (step 4).
5. Interview notes (step 7).

## How the screens were checked
They were never compiled. An independent reviewer read every new screen against the real core code, found no certain compile errors, and found logic problems that I fixed (a file that failed to load being overwritten, the routing token being deleted, demo data wiping everything, a stale map location, a hard-coded crew name, and others). A GitHub workflow (`.github/workflows/ci.yml`) builds the screens for macOS and iOS on every push, so the first real compile result will appear under the Actions tab of the repository, if Actions is enabled for it.

## Known gaps in the code
Buying a plan (and locking features after the trial, which only makes sense once buying works); cancel and export screens; messages to customers are previews only, nothing is sent; leftover photo files after cancelling a visit; PDF and emailed invoices; payment links; uploading photos to a server or cloud sync; accounts and teams; push notifications; Android. Photos stay on the phone and are not part of the backup file (Settings > Your data backs up all records but not the picture files).
