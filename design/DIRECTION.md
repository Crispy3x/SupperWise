# Supperwise (working name) · direction

## Brief (self-authored: the person said "just do it")
1. **What and who.** A weekly dinner planner for households cooking on a budget, mostly parents feeding 2–5 people. It plans the week's dinners and one grocery list priced at their store.
2. **Core action.** Open it at 5pm and see tonight's dinner, what it costs, and how the week's bill sits against the budget. Then start cooking, or swap.
3. **Feel.** Generous, unfussy, a little showy. References from outside apps: a Saturday-morning TV cooking show, a farmers' market stall at opening, a seasoned cast-iron pan.
4. **Existing assets.** None. The name is not chosen yet (Supperwise / Weeknight Table / Kitchen Tally).
5. **Need.** The core screens and an icon, then SwiftUI (step 3) and App Store panels (step 4).
6. **Image generation.** None used. The mockups use free Unsplash food photos as stand-ins for the recipe photography the real app needs.

## Category default being refused
The top meal planners (TapCook, mise, Potto, Whipp, NeatEat) share:
- a white ground
- a stack of rounded food-photo cards, one per day
- a small orange or green accent
- SF or Inter at one weight
- the budget tucked away on another tab

Category colour clichés: food orange and health/money green. All three directions avoid them.

## Concepts
- **A · Market stall at 7am** (place). A light, cool off-white ground. Bricolage Grotesque. Real dish photography as the hero. A cobalt hand-written price tag on the photo.
- **B · A seasoned cast-iron pan** (object). A warm iron-black ground. Barlow Condensed numerals. The dish seen top-down in a round pan bleeding off the edge. Yolk-yellow enamel marks "tonight".
- **C · A Saturday cooking-show title card** (media). A saturated colour field that changes with the weekday (Wednesday is tomato). Instrument Serif set like a title card. The dish on a round plate among cut-paper ingredient shapes. "Episode 3 of 5."

| | source | ground | type | accent hue | richness |
|---|---|---|---|---|---|
| A | place | light | grotesque | blue | photo |
| B | object | dark | condensed | yellow | colour-material |
| C | media | colour-field | serif | red | shape |

Rendered: `shots/explore/sheet.png`. The scan is clean apart from one shadow warning on B: its rings are drawn as shadows, and they become borders if B wins.
Fonts: this is a Linux machine, so where SF Pro is called for, a fallback renders. The display faces (Bricolage, Barlow Condensed, Instrument Serif) are the real ones.

## Pick (recommended, waiting for the person)
**C · title card.** It is the one an editor would remember. The weekday ground is colour that means something: you know what day it is before you read. It shares nothing with the category default.
Merged in from B: the five-day strip, as a row under the title card. Without it the week's progress is invisible.

- **A lost:** it is the category default done well. A white ground plus a photo hero plus a list is what TapCook already looks like.
- **B lost:** strong, but a near-black ground with a big money number drifts toward the "dark fintech" look. It also puts the bill ahead of the food, and the reviews say the food is what disappoints.

History check: the history file is empty, so there is no clash.

## Decision (2026-11-11)
The person picked **C · title card** and the name **Supperwise**. The five-day strip from B is merged in.

## Tokens
**Weekday grounds** (the colour field; the ground tells you the day).
- Ink `#FFF5EC` and ink-2 `#FFE3D6` on every ground, each measured at 4.5:1 or better.
- Mon ochre `#84520C` · Tue aubergine `#5E2A4F` · Wed tomato `#AD321C` · Thu olive `#4D581C` · Fri teal `#1E4D5C` · Sat chestnut `#6B3A1C` · Sun bottle `#2E4A36`
- `deep`: the ground darkened about 35%, used for the cut-paper shapes (Wed `#741A0E`).

**Paper** (list screens: groceries, plan, paywall).
- ground `#FBF3EA` · raised `#FFFFFF` · ink `#2B1611` · ink-2 `#6B5148` · ink-3 `#8C7369` · rule `#E7D8CC`
- accent = today's weekday colour (Wed `#AD321C`). Its one role is today and the primary action, and the system tint follows it. On ochre and olive days, the accent text uses the ground's deep value.

**Dark**
- The weekday ground deepens (Wed `#4A160C`, deep `#2E0B05`). Ink stays.
- Paper becomes `#1D1311`, raised `#2A1C19`, ink `#F6E9DF`, ink-2 `#C9B2A7`, rule `#3B2A25`. The accent lifts to `#E2654B`.

**Type**
- Instrument Serif for display only. SF Pro for UI.
- Scale: 92 day name · 46 dish and screen hero · 34 screen title (serif) · 17 body (SF) · 15 secondary · 13 meta · 11 tab labels.
- Serif tracking −2 to −3% at 46 and up. Tabular numbers for every price.

**Shape**
- Round plates with an 8pt ink rim (the plate is the object).
- Pills for actions (radius = height / 2). Sheets with a 28pt radius.
- Side margin 22.
- Spacing: 4 / 8 / 12 / 22 / 32 / 48.

## Richness
Two sources:
- **Photography:** overhead, one plate, daylight, no hands, no props beyond a napkin edge. The shipping app needs real recipe photography; the reviews punish AI food images.
- **Cut-paper shapes:** chilli, lime wedge, leaf, garlic. Flat, cut in the day's deep tone, never outlined. They surround the plate like a title-card set.

## Signature: spin the plate (on Swap)
1. **Trigger.** Tap Swap, or flick the plate sideways.
2. **0–120ms.** The plate rotates 40° with a light impact haptic and the dish title fades.
3. **120–420ms.** The old dish spins out to the left (rotation 160°). The new dish spins in from the right on the same rim, like a lazy Susan.
4. **At the same time.** The price rolls digit by digit (numericText) from $1.96 to $2.14 a plate, and the "under budget" figure at the top rolls with it.
5. **420–520ms.** The plate settles with a soft spring (no overshoot). A success haptic plays, and the new title rises 8pt into place.
6. **Reduced motion.** The plate and title cross-fade. The price still rolls.

## Content (Wed 11 Nov 2026, 17:42 · family of four · Hillside Market, Cincinnati · budget $95)
Mon Shakshuka with crusty bread $1.84 (cooked) · Tue Turkey meatballs, arugula and orzo $2.61 (cooked) · **Wed Chickpea tikka masala, basmati, charred red onion $1.96 a plate, 40 min** · Thu Penne arrabbiata with garlic broccoli $1.52 · Fri Skillet lemon chicken $2.88.
Week $83.40 of $95, so $11.60 under. Swap candidate: Red curry noodle soup $2.14.
Household: Dana (vegetarian), Marcus (no shellfish), Ari, 7 (not spicy), June, 4. Equipment: oven, stovetop, sheet pan. No air fryer, no grill.
Paywall (placeholder prices; the person decides at launch): 7-day trial, then $29.99 a year, or $7.99 a month.
