# App Factory skills: working notes

The skills live in /home/user/app-factory/app-factory/skills/. They aren't installed in ~/.claude, so Claude reads them from that folder.
Run their scripts with `NODE_USE_ENV_PROXY=1` in this cloud session, or Node's fetch can't reach the App Store.

## The one rule
Same job, own everything else. Copy the features, the first-run steps and the free/paid split. Never copy the name, icon, colours, words, pictures, sounds or screen designs (App Store guidelines 4.1 and 4.3).

## The four decisions that belong to the person
1. The market (end of scout)
2. The name and the look (design)
3. Anything submitted or paid for (launch)
4. The first post (content)

## 1 · app-scout → factory/SPEC.md
- `scout.mjs idea "<words>"` checks the person's own idea against the store.
- `scout.mjs chart <cat|all>` writes factory/scout/chart-*.md and open-doors.md.
- `scout.mjs app <id>` writes the listing, saves the screenshots and pulls up to 500 reviews.
- `scout.mjs names "A" "B" "C"` checks whether names are free on the store.
- A **market** is 3 or more charting apps doing one job.
- An **open door** was released in the last 24 months, by a seller with 5 apps or fewer.
- Drop: big companies, and anything needing a licence, a content catalogue, two sides or hardware.
- Shortlist at most 3 markets, with numbers exactly as the files print them.
- Revenue: "not checked", or a figure with its source and date.
- Reviews: count the complaints and write numbers; the top 3 failures go in "what the reviews say to get right".
- Spec sections: market, model, revenue, features tagged [all]/[model]/[ours], first run + paywall, reviews to get right, ours (twist, 3 free names, not used).

## 2 · app-designer → DIRECTION.md, explore.html, mockup.html
- Step 0, the brief: what and who, the core action, 3 feeling words + references from outside apps, existing assets, what's needed, image-generation consent.
- Read slop.md, including "The overcorrection", and check ~/.app-designer/history.md.
- Three concepts from different source families (printed/object/place/media/nature/play).
  - They must differ in ground (light/dark/colour-field), type family, richness source and accent hue.
  - Render the real core screen in explore.html, pick one, and write why the other two lost.
- The new look must differ on 3 of 5 history columns. Name the category default being refused.
- Write tokens, the richness art direction and the signature interaction storyboard.
- Content first: the exact copy and realistic data for every screen.
- 5–8 screens + icon in mockup.html, using assets/device.css and device.js (402x874, iPhone 17 Pro).
- `shoot.mjs mockup.html --out shots/rN`, plus a 375x667 small-phone run. Fix every FAIL, answer every warn.
- One fresh critic agent scores against critique.md. 2–4 rounds, then append a row to history.
- Optional: SwiftUI (swiftui.md), App Store panels (appstore.md).

## 3 · build (no skill)
- SwiftUI on a Mac. Expo if there's no Mac or Android is wanted.
- Order: the one screen that does the job, with real data → first run → spec features (tick [x] once each has run) → paywall last.
- Payments through StoreKit 2 / RevenueCat only. The 3 review failures must be fixed.
- Capture every screen into launch/captures/iphone/.

## 4 · app-launcher → launch/
- doctor.mjs → audit.mjs, which flags blockers/risks/checks.
  - Build first, then confirm or clear each finding and do the reviewer walk.
  - Fix until zero blockers.
- Write review-notes.txt, privacy-label.md, age-rating.md and connect-checklist.md.
- Positioning (store.mjs search/shelf/app): 3 angles, and the person picks one.
- Listing: listing.json → `meta.mjs check` → fastlane folder. Limits: name 30, subtitle 30, keywords 100 bytes.
- Screenshots:
  - Research: benchmark, inspo, STORY.md (the first 3 panels carry the pitch).
  - Images: real captures, then imagegen + composite or the CSS templates.
  - Directions: 3 for panel 1.
  - Render: `screens.mjs render`.
  - Check: search.png 2-second test, then a critic.
- Preview video: preview.mjs. Launch kit, then README.md + READY.md (GO or NOT YET).
- Grow path for live apps: ads.mjs, onboarding/paywall rewrite, ASO loop, review replies.

## 5 · app-marketer → factory/content/
- ANGLES.md: 5 angles (pain/curiosity/list/story/demo) × 6 hooks. Hooks are ≤12 words, lowercase, about the viewer's problem.
- A batch is 10 decks (decks/<id>.json), 2 per angle, 5–8 slides each.
  - Looks: bold/note/chat/photo/screen.
  - The app appears on the second-to-last slide.
- `content.mjs render <deck>` stops with !! on safe-area overflow. Open every sheet.png.
- Log with `posted` / `numbers`. `winners` needs 5 posts; 3x the median gets remade 3 ways.
- Never invent results or testimonials. Never post for the person.
