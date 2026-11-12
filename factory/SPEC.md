# Supperwise (working name)

the market        plan a week of dinners to a grocery budget, with one priced shopping list · 21 apps charting in food-drink, US, 2026-11-11 · 13 open doors, 5 in the top 15 (all released Jun–Jul 2026)
the model         TapCook: Budget Meal Plans · #3 top grossing food-drink · 7,312 ratings (4.8) · released 2026-07-17 · seller has 1 app · id 6769601354
others studied    mise #5 (4,835 ratings) · Potto #13 (2,378) · Whipp #8 (751) · NeatEat #15 (1,457)
revenue           not checked

## what it does (same as the model)
Tags: [all] = every app studied has it · [model] = only TapCook (as far as the listings show)

**Setup / Plan screen**
- ZIP or postal code, then pick the grocery chain you actually shop at; US and Canada [all]
- number of people you're feeding; servings adjustable per recipe [all]
- choose which nights you cook (M–S toggles, e.g. "5 dinners a week") [model]
- shopping day, suggested automatically ("before your first dinner"), changeable [model]
- weekly grocery budget slider, with a "just build the cheapest week" toggle [model]
- diet: anything / pescatarian / vegetarian / vegan; meat nights stepper [all]
- "won't eat" list and allergies [all]
- kitchen equipment you have ("what you can cook with") [all]

**Home: this week's dinners**
- week tabs: this week, next week, past weeks [model]
- one card per cook night: day and date, photo, dish name, cost per serving, total time, community thumbs-up count, cuisine, "new" tag [model]
- swap a dinner; the grocery list updates [all]
- more menu per dinner (remove, etc.) [all]

**Recipe detail**
- photo, total time, difficulty, number of ingredients, cleanup level [model]
- thumbs up / down rating [model]
- servings adjuster [all]
- ingredients, then directions; text size option for directions [model]
- share and print recipe; save/bookmark [model]
- "I cooked it" button [model]

**Grocery list**
- weekly total, priced at your chosen store; items left; "how we price this" explainer (estimates, not live prices) [model]
- grouped by aisle (produce, etc.), each item with pack size and price, tap to check off [all]
- "storing it" tab: how to store what you bought [model]
- share list; send to Instacart, DoorDash, Walmart [model]

**Kitchen (pantry)**
- staples checklist by category; ticked items come off this week's bill and stay off [model]
- running total of "$ off your list"; search any ingredient [model]

**Other**
- dinner reminder notification showing tonight's dish with its photo [model]
- You tab: profile, preferences, subscription (not seen)

## first run
From TapCook's listing (no screen recording, so the order and the questions are "not seen" first-hand):
1. ZIP/postal code → pick your store
2. household size, which nights you cook, budget
3. → paywall. "Building and viewing your weekly meal plans requires a subscription."
4. → a week of dinners + one grocery list totalled at your store

Paywall (TapCook, prices from its App Store page, 2026-11-11): **$9.99/month, $29.99/year, 7-day free trial on the yearly plan only.** No free tier.
Market range for comparison: monthly $9.99–$12.99; yearly $19.99–$59.99; some sell weekly at $6.99–$9.99 (Potto, NeatEat, mise).

## what the reviews say to get right
Read: 50 recent reviews, 10 each from TapCook, mise, Potto, Whipp and NeatEat. Apple's review feed returned nothing for any app on 2026-11-11, so these came from the App Store web pages, which show 10 each.
31 of the 50 are 3 stars or lower. Counts are reviews mentioning the issue, out of 50.

1. **Diet, allergy and equipment settings ignored or too narrow (12 of 50).** Allergens still served (fish, shrimp). Air fryer or grill recipes after saying "none". Only one restriction allowed. No mixed household (1 vegetarian + 3 meat eaters). Keto and paleo give 3–4 meals on repeat.
   Build: multiple restrictions, per-person tags, and hard filters that never break.
2. **Recipes bland, repetitive, vague, or obviously AI (11 of 50).** The same five meals recycled. "Cook according to package." No prep steps ("how should the bok choy be cut?"). Unclear ingredients ("cooked chicken", "mozzarella"). Instructions that don't scale with servings. Fake-looking AI food photos.
   Build: specific, tested recipes with prep steps, buyable ingredient names, instructions that scale, and real variety across the week.
3. **Paywall and trial feel like a trick (10 of 50).** "Free trial" but charged upfront or after cancelling the same day. "Free version" that doesn't exist. One recipe before the wall. $10/week called outrageous.
   Build: show the price before the questions end; let people see their first week's plan before paying; a plain, honest trial; Apple's standard subscription sheet.

Close fourth: **the bill doesn't match the store (7 of 50).**
- Pricing by fraction ("1 tbsp of salsa" priced, not the jar you have to buy).
- 0.64 eggs, 7.94 oz chicken.
- Meat prices off.
- The list not updating after a swap (3 more).

Pricing whole packages is the fix. It is also core to the job.

## ours
the twist         none: same job as the model (no idea of the person's own)
name              Supperwise · Weeknight Table · Kitchen Tally (all "free" on the US store 2026-11-11; not a trademark search)
not used          the model's name, icon, screenshots, listing text, in-app wording, colours, art, sounds and screen designs
design            left to App Designer: a look of our own

## build notes (for step 3)
- **Recipes:** a curated set, specific and tested. The reviews punish AI-generated recipes and photos. An AI model may pick and arrange the week, but not invent the dishes.
- **Prices:** estimates from a reference price table per ingredient, adjusted by chain and region, as TapCook's own disclaimer describes. Price whole packages, not fractions. Say plainly that prices are estimates.
- **Store integrations** (Instacart, Walmart, DoorDash) depend on their partner programmes. Start with share/export and add these later.
- **Payments:** StoreKit 2 subscriptions (monthly + yearly with trial), set up by you in App Store Connect.
