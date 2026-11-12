# Adds lunchbox ingredients to ingredients.json and writes Supperwise/Resources/lunches.json.
# Run after make_catalog.py and make_holiday.py. Every lunch is nut-free (many schools require it):
# sunflower seed butter stands in for peanut butter. Amounts are per lunch, in the ingredient's unit.
import json, os
R = os.path.join(os.path.dirname(__file__), "..", "Supperwise", "Resources")
ING = os.path.join(R, "ingredients.json")
ings = json.load(open(ING)); have = {i["id"] for i in ings}
new = [  # id, name, aisle, pack size, unit, pack label, reference price USD, keeps days
 ("sandwich_bread", "Whole-wheat sandwich bread", "bakery", 20, "count", "20-slice loaf", 3.29, 7),
 ("deli_turkey", "Sliced turkey breast", "meat", 255, "g", "9 oz pack", 4.99, 5),
 ("sunbutter", "Sunflower seed butter", "cans", 454, "g", "16 oz jar", 4.49, 90),
 ("jam", "Strawberry jam", "cans", 510, "g", "18 oz jar", 3.29, 180),
 ("hummus", "Hummus", "dairy", 283, "g", "10 oz tub", 3.99, 7),
 ("cucumber", "Cucumbers", "produce", 1, "count", "each", 0.79, 7),
 ("grapes", "Seedless grapes", "produce", 907, "g", "about 2 lb", 4.49, 7),
 ("bananas", "Bananas", "produce", 1, "count", "each", 0.29, 5),
 ("string_cheese", "String cheese", "dairy", 12, "count", "12 count", 4.99, 21),
 ("crackers", "Whole-grain crackers", "dry", 255, "g", "9 oz box", 3.29, 90),
 ("pita", "Pita bread", "bakery", 6, "count", "6 count", 2.99, 7),
]
for n in new:
    if n[0] not in have:
        ings.append(dict(id=n[0], name=n[1], aisle=n[2], packSize=n[3], unit=n[4], packLabel=n[5], refPrice=n[6], keepsDays=n[7], staple=False))
json.dump(ings, open(ING, "w"), indent=1, ensure_ascii=False)
known = {i["id"] for i in ings}

def i(ing, amt, text): return {"ingredient": ing, "amount": amt, "text": text}
L = [  # id, name, how to pack, ingredients, allergens, vegetarian, needs a thermos
 ("turkey_cheddar", "Turkey and cheddar sandwich", "Apple slices on the side; a squeeze of lemon keeps them from browning.",
  [i("sandwich_bread",2,"2 slices bread"), i("deli_turkey",60,"2 oz sliced turkey"), i("cheddar",20,"2 thin slices cheddar"), i("apples",1,"1 apple")], ["gluten","dairy"], False, False),
 ("sunbutter_jam", "Sunflower butter and jam sandwich", "Nut-free for school. Banana and carrot sticks alongside.",
  [i("sandwich_bread",2,"2 slices bread"), i("sunbutter",32,"2 tbsp sunflower butter"), i("jam",20,"1 tbsp jam"), i("bananas",1,"1 banana"), i("carrots",60,"a handful of carrot sticks")], ["gluten"], True, False),
 ("hummus_box", "Hummus snack box", "Pita triangles, cucumber, cherry tomatoes and a little cheese to dip.",
  [i("pita",1,"1 pita"), i("hummus",60,"1/4 cup hummus"), i("cucumber",0.5,"half a cucumber"), i("tomatoes_cherry",60,"a handful of cherry tomatoes"), i("string_cheese",1,"1 string cheese")], ["gluten","dairy"], True, False),
 ("cheese_crackers", "Cheese, crackers and grapes", "Cut grapes in quarters lengthwise for children under 4.",
  [i("crackers",40,"a handful of crackers"), i("string_cheese",1,"1 string cheese"), i("grapes",90,"a handful of grapes"), i("carrots",60,"carrot sticks")], ["gluten","dairy"], True, False),
 ("turkey_pinwheels", "Turkey and spinach pinwheels", "Roll tight, slice into rounds. An orange on the side.",
  [i("tortillas",1,"1 tortilla"), i("deli_turkey",50,"2 slices turkey"), i("cheddar",15,"a little grated cheddar"), i("spinach",10,"a few spinach leaves"), i("orange",1,"1 orange")], ["gluten","dairy"], False, False),
 ("bean_quesadilla", "Bean and cheese quesadilla wedges", "Cook the night before; good cold. Grapes on the side.",
  [i("tortillas",1,"1 tortilla"), i("black_beans",0.25,"1/4 can black beans"), i("cheddar",30,"1/4 cup grated cheddar"), i("grapes",90,"a handful of grapes")], ["gluten","dairy"], True, False),
 ("egg_box", "Hard-boiled egg box", "Boil a batch on Sunday; they keep 7 days in the fridge, in the shell.",
  [i("eggs",2,"2 eggs"), i("crackers",30,"a few crackers"), i("cucumber",0.5,"cucumber rounds"), i("grapes",90,"a handful of grapes")], ["egg","gluten"], True, False),
 ("yogurt_parfait", "Yogurt and oat parfait", "Pack the oats separately so they stay crunchy. Pack with an ice pack.",
  [i("yogurt",170,"3/4 cup plain yogurt"), i("honey",10,"a drizzle of honey"), i("oats",25,"1/4 cup toasted oats"), i("bananas",1,"1 banana")], ["dairy"], True, False),
 ("pasta_salad", "Pasta salad", "Make on Sunday for two days. Tomatoes, cucumber and feta.",
  [i("penne",60,"1 cup cooked penne"), i("tomatoes_cherry",60,"cherry tomatoes"), i("cucumber",0.5,"diced cucumber"), i("feta",20,"crumbled feta"), i("olive_oil",10,"2 tsp olive oil")], ["gluten","dairy"], True, False),
 ("chickpea_wrap", "Smashed chickpea wrap", "Chickpeas mashed with lemon and olive oil, carrot and spinach. Dairy-free.",
  [i("tortillas",1,"1 tortilla"), i("chickpeas",0.33,"1/3 can chickpeas"), i("lemon",0.25,"a squeeze of lemon"), i("carrots",40,"grated carrot"), i("spinach",10,"spinach")], ["gluten"], True, False),
 ("thermos_mac", "Thermos mac and cheese", "Fill the thermos with boiling water for 5 minutes first, then pack it piping hot.",
  [i("elbow_pasta",70,"2/3 cup elbows"), i("cheddar",40,"1/3 cup grated cheddar"), i("milk",60,"1/4 cup milk"), i("butter",10,"2 tsp butter"), i("bananas",1,"1 banana")], ["gluten","dairy"], True, True),
 ("thermos_fried_rice", "Thermos egg fried rice", "Use day-old rice. Pack piping hot in a preheated thermos.",
  [i("jasmine",70,"1/3 cup rice"), i("eggs",1,"1 egg"), i("frozen_peas",40,"peas"), i("carrots",30,"diced carrot"), i("soy_sauce",10,"2 tsp soy sauce")], ["egg","soy","gluten"], True, True),
 ("chicken_rice_bowl", "Chicken, rice and broccoli bowl", "Pack piping hot in a preheated thermos.",
  [i("chicken_thighs",90,"3 oz chicken"), i("jasmine",60,"1/3 cup rice"), i("broccoli",70,"broccoli florets"), i("olive_oil",5,"1 tsp olive oil")], [], False, True),
 ("bean_rice_bowl", "Black bean and rice bowl", "Warm in a preheated thermos, or eat cold as a salad.",
  [i("jasmine",60,"1/3 cup rice"), i("black_beans",0.33,"1/3 can black beans"), i("cheddar",20,"grated cheddar"), i("tomatoes_cherry",50,"cherry tomatoes")], ["dairy"], True, True),
 ("turkey_cracker_stack", "Build-your-own cracker stacks", "Turkey, cheese and crackers to stack. Apple slices on the side.",
  [i("crackers",35,"a handful of crackers"), i("deli_turkey",50,"2 slices turkey"), i("string_cheese",1,"1 string cheese"), i("apples",1,"1 apple")], ["gluten","dairy"], False, False),
 ("veggie_pita", "Hummus and veggie pita pocket", "Spread hummus inside, then stuff with cucumber, carrot and spinach.",
  [i("pita",1,"1 pita"), i("hummus",50,"3 tbsp hummus"), i("cucumber",0.5,"sliced cucumber"), i("carrots",40,"grated carrot"), i("spinach",10,"spinach"), i("orange",1,"1 orange")], ["gluten"], True, False),
]
out = []
for (id_, name, note, items, allergens, veg, thermos) in L:
    for x in items: assert x["ingredient"] in known, x
    out.append(dict(id=id_, name=name, note=note, ingredients=items, allergens=allergens, vegetarian=veg, thermos=thermos))
json.dump({"lunches": out, "notes": [
  "Every lunch here is nut-free; sunflower seed butter stands in for peanut butter.",
  "Keep cold lunches cold: an ice pack, or a frozen water bottle, in an insulated bag. Perishable food shouldn't sit above 40°F for more than 2 hours.",
  "Hot lunches: fill the thermos with boiling water for 5 minutes, empty it, then add food piping hot.",
  "Hummus contains sesame. Check every label if someone has an allergy."]},
  open(os.path.join(R, "lunches.json"), "w"), indent=1, ensure_ascii=False)
print(len(out), "lunches;", len(ings), "ingredients")
