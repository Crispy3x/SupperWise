# Build progress against SPEC.md
Written in code. Not yet run: there's no Mac in the cloud session. Features are ticked in SPEC.md only once they've run in the simulator.

- Store and region, household size, cook nights, budget slider + cheapest week, diets, won't-eat/allergies per person, equipment: Plan + onboarding
- This week: weekday title card, cost per plate, swap (spin), day strip, next episode: Today
- Recipe: photo, time, difficulty, servings stepper (scaled amounts), ingredients with prep notes, numbered steps, bigger text, share, I cooked it, vegetarian plate, milder note: Recipe
- Grocery list: whole-pack totals at your store type/region, how we price this, aisles, check off, leftover notes, share list: Groceries
- Kitchen: pantry ticks come off the bill and stay off; savings total; search: Kitchen
- Dinner reminder notification at 4:30pm on cook nights: Settings
- Paywall after the first week is shown in full; first week kept free; StoreKit 2; restore; manage
- Not built: community thumbs-up counts and "new" tags (need a server); Instacart/Walmart/DoorDash hand-off (needs partner programmes; plain-text share instead); "storing it" tab (leftover notes cover part of it)

Review fixes, counted from the competitors' reviews:
1. Diet/allergy/equipment: hard filters per person, tested (PlannerTests).
2. Recipes: 19 written with specific prep steps and buyable ingredient names; no AI images.
3. Paywall: the plan is shown before any price, the free week is kept, the trial terms are spelled out, Apple's purchase sheet.
4. Bill accuracy: priced by the whole pack, shared packs bought once, leftovers noted.
