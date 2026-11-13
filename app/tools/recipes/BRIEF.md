# Writing recipes for Supperwise

Supperwise plans weeknight dinners for families on a budget, prices the grocery list by the whole pack, and must
never serve someone an allergen. Your recipes go straight into the app, so they must be **accurate, safe and cookable**.

## Format
One JSON file: a list of recipe objects. Example (copy the shape exactly):

```json
{
  "id": "black_bean_tacos",
  "name": "Black bean tacos",
  "side": "Lime slaw, avocado and cheddar.",
  "cuisine": "Mexican",
  "minutes": 25,
  "difficulty": "Easy",
  "protein": "legumes",
  "equipment": ["stovetop"],
  "spice": 1,
  "mildNote": "Halve the chili powder. It's mild enough for most kids.",
  "servings": 4,
  "ingredients": [
    {"ingredient": "tortillas", "amount": 8, "text": "8", "note": "8 in flour"},
    {"ingredient": "black_beans", "amount": 2, "text": "2 cans", "note": "drained, liquid kept"},
    {"ingredient": "cabbage", "amount": 300, "text": "¼ head", "note": "very thinly sliced"},
    {"ingredient": "cumin", "amount": 3, "text": "1 tsp", "note": ""},
    {"ingredient": "neutral_oil", "amount": 15, "text": "1 tbsp", "note": ""},
    {"ingredient": "salt", "amount": 4, "text": "¾ tsp", "note": ""}
  ],
  "steps": ["Toss the cabbage with half the lime juice ...", "..."],
  "vegetarianSwap": null
}
```

- `id`: snake_case, unique, descriptive. `name`: plain dish name. `side`: one short sentence on what's served with it.
- `protein`: one of chicken, beef, pork, turkey, lamb, fish, shellfish, eggs, legumes, tofu, none.
- `equipment`: what's needed, from oven, stovetop, sheet_pan, air_fryer, grill, slow_cooker. Most dinners: stovetop and/or oven (+ sheet_pan if one is used).
- `difficulty`: Easy or Medium. `minutes`: honest total time including prep (slow cooker: real total).
- `spice`: 0 none, 1 warm, 2 hot. Any dish with spice 1 or 2 MUST have `mildNote` saying how to make it mild for kids.
- `servings`: always 4. Every amount is for 4 people.
- **Do not** include allergens, vegetarian or pescatarian: the app works them out from the ingredients.
- `vegetarianSwap` (for meat or fish dishes, whenever it makes sense): how to make a vegetarian plate alongside, e.g.
  `{"note": "For vegetarians, cook a can of chickpeas with the same spices in a small pan.", "ingredients": [{"ingredient": "chickpeas", "amount": 1, "text": "1 can", "note": "drained"}]}`.
  Swap ingredients must be vegetarian. Amounts in the swap are for the vegetarian portions (about 1–2 people).

## Ingredients
Use ONLY ids from `tools/recipes/INGREDIENTS.md`, in that ingredient's unit:
- **g**: grams. **ml**: millilitres. **count**: whole items (cans, eggs, lemons, tortillas, bell peppers; garlic is CLOVES; scallions are stalks).
- `amount` is the real quantity used; `text` is what a home cook reads ("1 tbsp", "2 cups", "1 can", "3 cloves"); `note` is prep ("finely diced", "drained").
- Keep `amount` and `text` consistent. Conversions: 1 tsp salt ≈ 6 g; 1 tsp ground spice ≈ 2.5 g; 1 tbsp oil ≈ 14 ml (use ml when the unit is ml, grams when g: olive_oil and neutral_oil are ml);
  1 tbsp butter = 14 g; 1 cup flour = 125 g; 1 cup cooked-style grated cheese ≈ 100–113 g; 1 cup uncooked rice ≈ 190 g; 1 cup broth = 240 ml;
  1 medium onion ≈ 220 g; 1 carrot ≈ 70 g; 1 cup chopped broccoli ≈ 90 g; 1 lb = 454 g; 1 cup milk = 240 ml.
- Realistic portions for 4 adults: 450–700 g meat or fish; 300–400 g dry pasta; 280–380 g dry rice; 2 cans beans as a main.
- Each recipe uses 5–14 ingredients. Combine duplicates (one line per ingredient).
- The app prices whole packs, so favour ingredients other dinners use too; avoid one-off pricey items.

## Safety and accuracy (non-negotiable)
- Cook to safe internal temperatures and say so in the step: chicken and turkey 165°F; ground beef, pork and lamb 160°F; whole cuts of pork, beef and lamb 145°F with a 3-minute rest; fish 145°F or until it flakes; shrimp and scallops until opaque.
- Real times and heat levels (medium-high, 425°F). No vague "cook until done" without a sign of doneness.
- Steps: 4–8 numbered-style sentences (don't number them), clear for a beginner, in order, using every ingredient.
- Food-safety where it matters: refrigerate leftovers within 2 hours; don't wash raw chicken; slow cooker on LOW 7–8 h or HIGH 4 h for meat.
- Write in plain American English. No brand names. No health claims.

## Variety
- About 35–40% of your recipes vegetarian (eggs, beans, lentils, tofu, cheese, vegetables).
- Mostly 20–45 minute weeknight dinners; a few longer weekend or slow-cooker ones.
- Budget-friendly: most dinners should cost $8–$18 for 4 at a supermarket.
- Don't duplicate the existing dishes: chickpea tikka masala, penne arrabbiata, shakshuka, turkey meatballs with orzo, lemon-thyme skillet chicken,
  red curry noodle soup, sheet-pan salmon with potatoes, black bean tacos, red lentil and tomato soup, beef and mushroom ragù, oven-crisp drumsticks,
  egg fried rice, coconut red lentil dal, turkey and black bean chili, baked potatoes with broccoli and cheddar, garlic butter shrimp, sausage and peppers,
  spaghetti with garlic, white beans and spinach, chicken and spinach curry.

## Check your work
Run `python3 tools/make_recipes.py --check --only <your file name>` from `/home/user/mrr-app/app` and fix every problem it lists until it prints ok.
