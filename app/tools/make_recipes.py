#!/usr/bin/env python3
"""Adds the extended recipe catalog. Run after make_catalog.py, make_holiday.py and make_lunch.py.

Recipes live in tools/recipes/*.json (one list per file). This script:
  1. adds the extra ingredients below to ingredients.json,
  2. checks every recipe (python3 tools/make_recipes.py --check to only check),
  3. works out allergens, vegetarian and pescatarian FROM THE INGREDIENTS (never trusted from the author),
  4. appends the recipes to recipes.json.
Amounts are for the recipe's servings (4), in the ingredient's unit: g, ml, or count (cans, eggs, cloves...).
"""
import json, os, re, sys, glob
ROOT = os.path.dirname(__file__)
RES = os.path.join(ROOT, "..", "Supperwise", "Resources")

# id: (name, aisle, packSize, unit, packLabel, refPrice USD, keepsDays, allergens, kind)  kind: m meat, f fish, s shellfish
EXTRA = {
 # Produce
 "zucchini": ("Zucchini","produce",1,"count","each",0.99,7,"",""),
 "eggplant": ("Eggplant","produce",1,"count","each",1.79,7,"",""),
 "cauliflower": ("Cauliflower","produce",1,"count","1 head",3.49,7,"",""),
 "kale": ("Kale","produce",280,"g","1 bunch",2.49,5,"",""),
 "romaine": ("Romaine hearts","produce",3,"count","3-pack",3.49,7,"",""),
 "jalapeno": ("Jalapeños","produce",1,"count","each",0.25,10,"",""),
 "poblano": ("Poblano peppers","produce",1,"count","each",0.79,7,"",""),
 "asparagus": ("Asparagus","produce",454,"g","1 lb bunch",3.99,4,"",""),
 "shallots": ("Shallots","produce",227,"g","8 oz bag",2.99,30,"",""),
 "leeks": ("Leeks","produce",2,"count","2-pack",2.99,10,"",""),
 "mango": ("Mangoes","produce",1,"count","each",1.29,5,"",""),
 "pineapple": ("Pineapple","produce",1,"count","each",2.99,5,"",""),
 "tomatoes_roma": ("Roma tomatoes","produce",454,"g","about 1 lb",1.79,7,"",""),
 "potatoes_russet": ("Russet potatoes","produce",2270,"g","5 lb bag",4.49,30,"",""),
 "mint": ("Mint","produce",21,"g","0.75 oz pack",2.49,5,"",""),
 "dill": ("Dill","produce",21,"g","0.75 oz pack",2.49,5,"",""),
 "snap_peas": ("Sugar snap peas","produce",227,"g","8 oz bag",3.49,5,"",""),
 "bok_choy": ("Baby bok choy","produce",454,"g","1 lb",2.99,5,"",""),
 "red_cabbage": ("Red cabbage","produce",900,"g","1 head",2.49,21,"",""),
 "corn_cobs": ("Corn on the cob","produce",1,"count","each",0.69,4,"",""),
 "radishes": ("Radishes","produce",170,"g","1 bunch",1.49,10,"",""),
 "lettuce_butter": ("Butter lettuce","produce",1,"count","1 head",2.99,5,"",""),
 # Meat
 "chicken_breast": ("Boneless chicken breasts","meat",680,"g","1.5 lb pack",7.49,2,"","m"),
 "chicken_wings": ("Chicken wings","meat",1360,"g","3 lb pack",9.99,2,"","m"),
 "ground_pork": ("Ground pork","meat",454,"g","1 lb pack",4.49,2,"","m"),
 "pork_tenderloin": ("Pork tenderloin","meat",680,"g","about 1.5 lb",6.99,3,"","m"),
 "pork_chops": ("Boneless pork chops","meat",680,"g","1.5 lb pack",6.49,3,"","m"),
 "pork_shoulder": ("Pork shoulder, boneless","meat",1360,"g","about 3 lb",10.49,3,"","m"),
 "bacon": ("Bacon","meat",340,"g","12 oz pack",5.99,7,"","m"),
 "flank_steak": ("Flank steak","meat",680,"g","about 1.5 lb",13.49,3,"","m"),
 "sirloin": ("Sirloin steak","meat",454,"g","1 lb",9.99,3,"","m"),
 "beef_chuck": ("Beef chuck, stew cuts","meat",907,"g","2 lb pack",13.99,3,"","m"),
 "chorizo": ("Mexican chorizo","meat",340,"g","12 oz pack",3.99,7,"","m"),
 "ground_lamb": ("Ground lamb","meat",454,"g","1 lb pack",8.99,2,"","m"),
 "kielbasa": ("Smoked kielbasa","meat",397,"g","14 oz rope",4.49,14,"","m"),
 "ham_diced": ("Diced cooked ham","meat",227,"g","8 oz pack",3.99,7,"","m"),
 # Seafood
 "cod": ("Cod fillets","seafood",454,"g","1 lb pack",9.49,2,"fish","f"),
 "tilapia": ("Tilapia fillets","seafood",454,"g","1 lb pack",6.49,2,"fish","f"),
 "tuna_canned": ("Canned tuna","cans",1,"count","5 oz can",1.49,365,"fish","f"),
 "scallops": ("Sea scallops, frozen","seafood",454,"g","1 lb bag",16.99,90,"shellfish","s"),
 # Dairy, eggs and chilled
 "mozzarella": ("Mozzarella, shredded","dairy",227,"g","8 oz bag",2.99,21,"dairy",""),
 "mozzarella_fresh": ("Fresh mozzarella","dairy",227,"g","8 oz ball",4.49,10,"dairy",""),
 "ricotta": ("Whole-milk ricotta","dairy",425,"g","15 oz tub",3.99,10,"dairy",""),
 "cream_cheese": ("Cream cheese","dairy",227,"g","8 oz block",2.49,30,"dairy",""),
 "monterey_jack": ("Monterey Jack, shredded","dairy",227,"g","8 oz bag",2.99,21,"dairy",""),
 "goat_cheese": ("Goat cheese","dairy",113,"g","4 oz log",3.99,14,"dairy",""),
 "greek_yogurt": ("Plain Greek yogurt","dairy",907,"g","32 oz tub",5.99,14,"dairy",""),
 "half_and_half": ("Half-and-half","dairy",473,"ml","1 pint",2.49,10,"dairy",""),
 "paneer": ("Paneer","dairy",340,"g","12 oz block",5.99,14,"dairy",""),
 "tofu_firm": ("Extra-firm tofu","dairy",397,"g","14 oz block",2.29,14,"soy",""),
 "gnocchi": ("Potato gnocchi","dry",454,"g","1 lb pack",2.99,180,"gluten,egg",""),
 "tortellini": ("Cheese tortellini, refrigerated","dairy",567,"g","20 oz pack",6.49,14,"gluten,egg,dairy",""),
 "pizza_dough": ("Pizza dough","dairy",454,"g","1 lb ball",2.99,5,"gluten",""),
 # Cans, jars and sauces
 "kidney_beans": ("Kidney beans","cans",1,"count","15 oz can",0.89,365,"",""),
 "pinto_beans": ("Pinto beans","cans",1,"count","15 oz can",0.89,365,"",""),
 "tomato_sauce": ("Tomato sauce","cans",425,"g","15 oz can",0.99,365,"",""),
 "marinara": ("Marinara sauce","cans",680,"g","24 oz jar",2.99,365,"",""),
 "salsa": ("Salsa","cans",454,"g","16 oz jar",2.79,365,"",""),
 "enchilada_sauce": ("Red enchilada sauce","cans",283,"g","10 oz can",1.79,365,"",""),
 "chipotle_adobo": ("Chipotles in adobo","cans",198,"g","7 oz can",1.99,365,"",""),
 "green_chiles": ("Diced green chiles","cans",113,"g","4 oz can",1.29,365,"",""),
 "peanut_butter": ("Peanut butter","cans",454,"g","16 oz jar",2.99,180,"nuts",""),
 "tahini": ("Tahini","cans",454,"g","16 oz jar",6.99,180,"sesame",""),
 "fish_sauce": ("Fish sauce","cans",200,"ml","6.8 oz bottle",3.49,365,"fish","f"),
 "hoisin": ("Hoisin sauce","cans",240,"ml","8 oz jar",2.99,365,"soy,gluten",""),
 "sriracha": ("Sriracha","cans",481,"g","17 oz bottle",3.99,365,"",""),
 "sesame_oil": ("Toasted sesame oil","staples",148,"ml","5 oz bottle",3.99,365,"sesame",""),
 "rice_vinegar": ("Rice vinegar","cans",355,"ml","12 oz bottle",2.49,365,"",""),
 "cider_vinegar": ("Apple cider vinegar","cans",473,"ml","16 oz bottle",2.29,365,"",""),
 "maple_syrup": ("Maple syrup","cans",355,"ml","12 oz bottle",7.99,365,"",""),
 "mayo": ("Mayonnaise","cans",887,"ml","30 oz jar",4.49,90,"egg",""),
 "worcestershire": ("Worcestershire sauce","cans",296,"ml","10 oz bottle",2.99,365,"fish","f"),
 "capers": ("Capers","cans",99,"g","3.5 oz jar",2.99,365,"",""),
 "olives_kalamata": ("Kalamata olives","cans",170,"g","6 oz jar",3.49,180,"",""),
 "roasted_peppers": ("Roasted red peppers","cans",340,"g","12 oz jar",2.99,180,"",""),
 "pesto": ("Basil pesto","cans",170,"g","6 oz jar",3.99,30,"dairy,nuts",""),
 "miso": ("White miso","dairy",400,"g","14 oz tub",4.99,180,"soy",""),
 "gochujang": ("Gochujang","cans",500,"g","17.6 oz tub",5.99,365,"soy,gluten",""),
 "green_curry_paste": ("Thai green curry paste, vegan (no shrimp paste)","cans",113,"g","4 oz jar",3.29,60,"",""),
 "beef_broth": ("Beef broth","cans",946,"ml","32 oz carton",2.49,365,"","m"),
 "artichokes": ("Artichoke hearts","cans",1,"count","14 oz can",2.79,365,"",""),
 "pumpkin_seeds": ("Pepitas","dry",142,"g","5 oz bag",3.49,180,"",""),
 # Dry goods, bread and grains
 "lentils_brown": ("Brown lentils","dry",454,"g","1 lb bag",1.79,365,"",""),
 "lentils_green": ("French green lentils","dry",454,"g","1 lb bag",2.99,365,"",""),
 "quinoa": ("Quinoa","dry",340,"g","12 oz bag",3.99,365,"",""),
 "couscous": ("Couscous","dry",283,"g","10 oz box",2.49,365,"gluten",""),
 "egg_noodles": ("Egg noodles","dry",340,"g","12 oz bag",1.99,365,"gluten,egg",""),
 "udon": ("Udon noodles","dry",567,"g","3-pack, 20 oz",3.49,180,"gluten",""),
 "soba": ("Soba noodles","dry",270,"g","9.5 oz pack",3.49,365,"gluten",""),
 "lasagna_noodles": ("Lasagna noodles","dry",454,"g","1 lb box",1.99,365,"gluten",""),
 "fettuccine": ("Fettuccine","dry",454,"g","1 lb box",1.39,365,"gluten",""),
 "rigatoni": ("Rigatoni","dry",454,"g","1 lb box",1.39,365,"gluten",""),
 "brown_rice": ("Brown rice","dry",907,"g","2 lb bag",2.99,365,"",""),
 "arborio": ("Arborio rice","dry",907,"g","2 lb bag",4.99,365,"",""),
 "panko": ("Panko breadcrumbs","dry",227,"g","8 oz box",2.49,180,"gluten",""),
 "cornstarch": ("Cornstarch","dry",454,"g","16 oz box",1.99,365,"",""),
 "cornmeal": ("Cornmeal","dry",680,"g","24 oz bag",2.49,365,"",""),
 "peanuts": ("Roasted peanuts","dry",454,"g","16 oz jar",3.49,180,"nuts",""),
 "cashews": ("Roasted cashews","dry",255,"g","9 oz bag",5.99,180,"nuts",""),
 "almonds_sliced": ("Sliced almonds","dry",170,"g","6 oz bag",4.49,180,"nuts",""),
 "sesame_seeds": ("Sesame seeds","spices",62,"g","2.2 oz jar",2.99,365,"sesame",""),
 "tortilla_chips": ("Tortilla chips","dry",369,"g","13 oz bag",3.49,60,"",""),
 "corn_tortillas": ("Corn tortillas","bakery",30,"count","30 count",2.49,21,"",""),
 "burger_buns": ("Hamburger buns","bakery",8,"count","8 count",2.99,6,"gluten",""),
 "hoagie_rolls": ("Hoagie rolls","bakery",6,"count","6 count",3.49,4,"gluten",""),
 "naan": ("Naan","bakery",4,"count","4 count",3.99,7,"gluten,dairy",""),
 "baguette": ("Baguette","bakery",1,"count","each",2.49,2,"gluten",""),
 "raisins": ("Raisins","dry",340,"g","12 oz box",3.49,365,"",""),
 # Frozen
 "frozen_corn": ("Frozen corn","frozen",340,"g","12 oz bag",1.79,180,"",""),
 "frozen_edamame": ("Frozen shelled edamame","frozen",340,"g","12 oz bag",2.99,180,"soy",""),
 "frozen_spinach": ("Frozen chopped spinach","frozen",283,"g","10 oz box",1.69,180,"",""),
 "frozen_stir_fry_veg": ("Frozen stir-fry vegetables","frozen",454,"g","16 oz bag",2.49,180,"",""),
 # Spices
 "turmeric": ("Ground turmeric","spices",45,"g","1.6 oz jar",2.99,365,"",""),
 "coriander": ("Ground coriander","spices",35,"g","1.25 oz jar",2.99,365,"",""),
 "garlic_powder": ("Garlic powder","spices",87,"g","3.1 oz jar",2.49,365,"",""),
 "onion_powder": ("Onion powder","spices",74,"g","2.6 oz jar",2.49,365,"",""),
 "italian_seasoning": ("Italian seasoning","spices",21,"g","0.75 oz jar",2.49,365,"",""),
 "bay_leaves": ("Bay leaves","spices",4,"g","0.15 oz jar",2.99,365,"",""),
 "rosemary": ("Dried rosemary","spices",21,"g","0.75 oz jar",2.49,365,"",""),
 "cayenne": ("Cayenne pepper","spices",45,"g","1.6 oz jar",2.99,365,"",""),
 "ground_ginger": ("Ground ginger","spices",40,"g","1.4 oz jar",2.99,365,"",""),
 "nutmeg": ("Ground nutmeg","spices",31,"g","1.1 oz jar",3.49,365,"",""),
 "paprika": ("Sweet paprika","spices",62,"g","2.2 oz jar",2.49,365,"",""),
 "five_spice": ("Chinese five-spice","spices",48,"g","1.7 oz jar",3.49,365,"",""),
 "dried_basil": ("Dried basil","spices",14,"g","0.5 oz jar",2.49,365,"",""),
}

# Allergens and kind for the ingredients that already exist (base catalog, holidays, lunches).
BASE_TAGS = {
 "yogurt":("dairy",""),"milk":("dairy",""),"butter":("dairy",""),"parmesan":("dairy",""),"cheddar":("dairy",""),
 "feta":("dairy",""),"sour_cream":("dairy",""),"heavy_cream":("dairy",""),"evaporated_milk":("dairy",""),
 "string_cheese":("dairy",""),"eggs":("egg",""),
 "penne":("gluten",""),"spaghetti":("gluten",""),"orzo":("gluten",""),"elbow_pasta":("gluten",""),"tortillas":("gluten",""),
 "bread_crusty":("gluten",""),"breadcrumbs":("gluten",""),"flour":("gluten",""),"stuffing_cubes":("gluten",""),
 "pie_crust":("gluten,dairy",""),"puff_pastry":("gluten,dairy",""),"dinner_rolls":("gluten,dairy,egg",""),
 "sandwich_bread":("gluten",""),"crackers":("gluten",""),"pita":("gluten",""),"oats":("gluten",""),
 "soy_sauce":("soy,gluten",""),"hummus":("sesame",""),"rice_noodles":("",""),
 "salmon":("fish","f"),"shrimp":("shellfish","s"),
 "chicken_thighs":("","m"),"chicken_drumsticks":("","m"),"ground_turkey":("","m"),"ground_beef":("","m"),
 "pork_sausage":("","m"),"turkey_whole":("","m"),"ham_spiral":("","m"),"deli_turkey":("","m"),"chicken_broth":("","m"),
}

# The same dish written in two batches: the later copy is left out.
DUPLICATES = set(["04-indian-middle-eastern.json:baked_falafel_pitas", "04-indian-middle-eastern.json:lamb_kofta_herbed_couscous", "06-seafood-vegetarian.json:baked_eggplant_parmesan", "06-seafood-vegetarian.json:baked_falafel_pitas", "06-seafood-vegetarian.json:black_bean_burgers", "06-seafood-vegetarian.json:coconut_fish_curry", "06-seafood-vegetarian.json:huevos_rancheros", "06-seafood-vegetarian.json:lentil_sloppy_joes", "06-seafood-vegetarian.json:matar_paneer", "06-seafood-vegetarian.json:miso_salmon_soba", "06-seafood-vegetarian.json:miso_udon_tofu_soup", "06-seafood-vegetarian.json:moroccan_chickpea_stew", "06-seafood-vegetarian.json:mushroom_cheddar_strata", "06-seafood-vegetarian.json:smoky_shrimp_cheesy_grits", "06-seafood-vegetarian.json:spinach_feta_puff_pastry_pie", "06-seafood-vegetarian.json:spinach_ricotta_lasagna_rolls", "06-seafood-vegetarian.json:sweet_potato_pinto_enchiladas", "06-seafood-vegetarian.json:tilapia_fish_tacos", "06-seafood-vegetarian.json:tomato_soup_grilled_cheese", "06-seafood-vegetarian.json:tuna_caper_tomato_spaghetti", "06-seafood-vegetarian.json:tuna_melt_sandwiches"])

PROTEINS = {"chicken","beef","pork","turkey","lamb","fish","shellfish","eggs","legumes","tofu","none"}
EQUIP = {"oven","stovetop","sheet_pan","air_fryer","grill","slow_cooker"}
DIFF = {"Easy","Medium"}

def tags(ingredients):
    out = {}
    for i in ingredients:
        if i["id"] in EXTRA: e = EXTRA[i["id"]]; out[i["id"]] = (e[7], e[8])
        else: out[i["id"]] = BASE_TAGS.get(i["id"], ("", ""))
    return out

def main():
    check_only = "--check" in sys.argv
    ing_path = os.path.join(RES, "ingredients.json")
    ings = json.load(open(ing_path))
    known = {i["id"] for i in ings}
    for k, e in EXTRA.items():
        if k not in known:
            ings.append(dict(id=k, name=e[0], aisle=e[1], packSize=e[2], unit=e[3], packLabel=e[4], refPrice=e[5], keepsDays=e[6], staple=False))
    # Many Thai curry pastes contain shrimp paste: the list tells shoppers to buy a vegan one, so dishes stay
    # vegetarian and shellfish-free as planned.
    for i in ings:
        if i["id"] in ("red_curry_paste", "green_curry_paste") and "vegan" not in i["name"]:
            i["name"] = i["name"] + ", vegan (no shrimp paste)"
    by_id = {i["id"]: i for i in ings}
    T = tags(ings)
    credits_path = os.path.join(RES, "photo-credits.json")
    photo_ids = set(json.load(open(credits_path))) if os.path.exists(credits_path) else set()
    rec_path = os.path.join(RES, "recipes.json")
    recipes = json.load(open(rec_path))
    base = [r for r in recipes if not r.get("extended")]
    seen = {r["id"] for r in base}
    errors, added = [], []
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    for f in sorted(glob.glob(os.path.join(ROOT, "recipes", "*.json"))):
        if only and os.path.basename(f) != os.path.basename(only): continue
        try: batch = json.load(open(f))
        except Exception as ex: errors.append(f"{os.path.basename(f)}: not valid JSON: {ex}"); continue
        for n, r in enumerate(batch):
            if f"{os.path.basename(f)}:{r.get('id')}" in DUPLICATES: continue
            where = f"{os.path.basename(f)}[{n}] {r.get('id', '?')}"
            def err(m): errors.append(f"{where}: {m}")
            for k in ("id","name","side","cuisine","minutes","difficulty","protein","equipment","spice","ingredients","steps"):
                if k not in r: err(f"missing {k}")
            if any(k not in r for k in ("id","ingredients","steps")): continue
            if not re.fullmatch(r"[a-z][a-z0-9_]{2,48}", r["id"]): err("id must be snake_case")
            if r["id"] in seen: err("duplicate id")
            seen.add(r["id"])
            if r.get("protein") not in PROTEINS: err(f"protein must be one of {sorted(PROTEINS)}")
            if r.get("difficulty") not in DIFF: err("difficulty must be Easy or Medium")
            if not set(r.get("equipment", [])) <= EQUIP or not r.get("equipment"): err(f"equipment must be a non-empty subset of {sorted(EQUIP)}")
            if not (10 <= r.get("minutes", 0) <= 480): err("minutes out of range")
            if r.get("spice") not in (0, 1, 2): err("spice must be 0, 1 or 2")
            if r.get("spice", 0) > 0 and not r.get("mildNote"): err("spicy dishes need a mildNote (how to make it mild)")
            if len(r["steps"]) < 3: err("needs at least 3 steps")
            if r.get("servings", 4) != 4: err("servings must be 4")
            ids = []
            for ri in r["ingredients"]:
                i = by_id.get(ri.get("ingredient"))
                if not i: err(f"unknown ingredient {ri.get('ingredient')!r}"); continue
                a = ri.get("amount", 0)
                if not isinstance(a, (int, float)) or a <= 0: err(f"{i['id']}: amount must be > 0")
                elif a > i["packSize"] * 6: err(f"{i['id']}: {a} {i['unit']} is more than 6 packs for 4 servings")
                elif i["unit"] == "count" and a != int(a) and a not in (0.25, 0.5, 0.75) and a % 0.5: err(f"{i['id']}: count amounts should be whole or halves")
                if not ri.get("text"): err(f"{i['id']}: text (the human amount, e.g. '2 tbsp') is required")
                ids.append(i["id"])
            if len(set(ids)) != len(ids): err("an ingredient is listed twice; combine it")
            if len(ids) < 4: err("needs at least 4 ingredients")
            # Derive the safety facts from the ingredients.
            allergens, kinds = set(), set()
            for i in ids:
                a, k = T.get(i, ("", ""))
                allergens |= {x for x in a.split(",") if x}
                if k: kinds.add(k)
            veg = not kinds
            pesc = kinds <= {"f", "s"}
            swap = r.get("vegetarianSwap")
            if swap:
                for si in swap.get("ingredients", []):
                    if si.get("ingredient") not in by_id: err(f"swap: unknown ingredient {si.get('ingredient')!r}")
                    elif T.get(si["ingredient"], ("", ""))[1]: err(f"swap: {si['ingredient']} isn't vegetarian")
                    if not si.get("text"): err("swap ingredient needs text")
                if veg: err("vegetarian dish shouldn't have a vegetarianSwap")
            meat_word = {"m": {"chicken","beef","pork","turkey","lamb"}, "f": {"fish"}, "s": {"shellfish"}}
            if r.get("protein") in {"chicken","beef","pork","turkey","lamb"} and "m" not in kinds: err("protein says meat but no meat ingredient")
            if r.get("protein") == "fish" and "f" not in kinds: err("protein says fish but no fish ingredient")
            if r.get("protein") == "shellfish" and "s" not in kinds: err("protein says shellfish but no shellfish ingredient")
            added.append(dict(id=r["id"], name=r["name"], side=r["side"], cuisine=r["cuisine"], minutes=r["minutes"],
                              difficulty=r["difficulty"], protein=r["protein"], allergens=sorted(allergens),
                              equipment=r["equipment"], spice=r["spice"],
                              ingredients=[dict(ingredient=x["ingredient"], amount=x["amount"], text=x["text"], note=x.get("note", "")) for x in r["ingredients"]],
                              steps=r["steps"], vegetarian=veg, pescatarian=pesc,
                              photo=(f"rp_{r['id']}.jpg" if r["id"] in photo_ids and os.path.exists(os.path.join(RES, "photos", f"rp_{r['id']}.jpg")) else None),
                              mildNote=r.get("mildNote"),
                              vegetarianSwap=(dict(note=swap["note"], ingredients=[dict(ingredient=x["ingredient"], amount=x["amount"], text=x["text"], note=x.get("note", "")) for x in swap["ingredients"]]) if swap else None),
                              servings=4, extended=True))
    if errors:
        print("\n".join(errors[:200])); print(f"\n{len(errors)} problems"); sys.exit(1)
    if check_only:
        print(f"ok: {len(added)} recipes check out"); return
    json.dump(ings, open(ing_path, "w"), indent=1, ensure_ascii=False)
    json.dump(base + added, open(rec_path, "w"), indent=1, ensure_ascii=False)
    print(f"ok: {len(base)} base + {len(added)} extended recipes, {len(ings)} ingredients")

if __name__ == "__main__":
    main()
