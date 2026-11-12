# Adds holiday ingredients to ingredients.json and writes Supperwise/Resources/holiday-thanksgiving.json.
# Turkey times follow USDA's roasting table (325°F, unstuffed) and thawing guidance (fridge: about 1 day per 4–5 lb).
import json, os
R = os.path.join(os.path.dirname(__file__), "..", "Supperwise", "Resources")
ING = os.path.join(R, "ingredients.json")
ings = json.load(open(ING))
have = {i["id"] for i in ings}
new = [
 # id, name, aisle, packSize, unit, packLabel, refPrice, keepsDays
 ("turkey_whole", "Whole turkey, frozen", "meat", 454, "g", "per lb", 1.59, 4),
 ("green_beans", "Green beans", "produce", 454, "g", "1 lb", 2.49, 6),
 ("cranberries", "Fresh cranberries", "produce", 340, "g", "12 oz bag", 2.99, 30),
 ("orange", "Oranges", "produce", 1, "count", "each", 0.89, 21),
 ("sweet_potato", "Sweet potatoes", "produce", 454, "g", "per lb", 1.29, 21),
 ("butternut_squash", "Butternut squash", "produce", 1, "count", "each, about 2 lb", 3.49, 30),
 ("stuffing_cubes", "Unseasoned bread cubes", "bakery", 340, "g", "12 oz bag", 3.29, 60),
 ("pie_crust", "Frozen pie crust, 9 in", "frozen", 2, "count", "2-pack", 3.99, 90),
 ("pumpkin_puree", "Pumpkin purée", "cans", 425, "g", "15 oz can", 2.29, 365),
 ("evaporated_milk", "Evaporated milk", "cans", 354, "ml", "12 oz can", 1.49, 365),
 ("pumpkin_spice", "Pumpkin pie spice", "spices", 28, "g", "1 oz jar", 3.49, 365),
 ("sage", "Dried sage", "spices", 14, "g", "0.5 oz jar", 2.99, 365),
 ("heavy_cream", "Heavy cream", "dairy", 473, "ml", "1 pint", 3.99, 10),
 ("ham_spiral", "Spiral-cut ham, fully cooked, bone-in", "meat", 454, "g", "per lb", 2.49, 5),
 ("dijon", "Dijon mustard", "cans", 227, "g", "8 oz jar", 2.79, 180),
 ("brown_sugar", "Brown sugar", "dry", 907, "g", "2 lb bag", 2.99, 365),
 ("brussels_sprouts", "Brussels sprouts", "produce", 454, "g", "1 lb", 3.49, 7),
 ("dinner_rolls", "Dinner rolls", "bakery", 12, "count", "12 count", 3.99, 4),
 ("puff_pastry", "Frozen puff pastry", "frozen", 2, "count", "2 sheets", 4.99, 90),
 ("apples", "Baking apples", "produce", 1, "count", "each", 0.99, 21),
 ("oats", "Rolled oats", "dry", 510, "g", "18 oz canister", 3.49, 365),
 ("cinnamon", "Ground cinnamon", "spices", 68, "g", "2.4 oz jar", 2.99, 365),
 ("elbow_pasta", "Elbow macaroni", "dry", 454, "g", "1 lb box", 1.39, 365),
]
for n in new:
    if n[0] not in have:
        ings.append(dict(id=n[0], name=n[1], aisle=n[2], packSize=n[3], unit=n[4], packLabel=n[5], refPrice=n[6], keepsDays=n[7], staple=False))
json.dump(ings, open(ING, "w"), indent=1, ensure_ascii=False)

def ing(i, a, text, note=""): return {"ingredient": i, "amount": a, "text": text, "note": note}
# schedule: (minutes before dinner, task). Negative minutes = after the turkey goes in is handled in code; turkey has its own schedule.
dishes = [
 dict(id="tg_turkey", name="Roast turkey", course="main", vegetarian=False, servings=8, allergens=["dairy"],
      ingredients=[ing("turkey_whole", 4540, "1 turkey, about 10 lb for 8", "thawed, giblets removed"), ing("butter", 113, "½ cup", "softened"),
                   ing("sage", 2, "1 tbsp"), ing("thyme", 2, "1 tbsp"), ing("lemon", 1, "1"), ing("onion_yellow", 220, "1", "quartered"), ing("salt", 18, "1 tbsp")],
      steps=["Pat the turkey dry. Mix the butter, sage, thyme and lemon zest; rub it under and over the skin. Salt it all over.",
             "Put the lemon halves and onion in the cavity. Set the bird on a rack in a roasting pan, breast up.",
             "Roast at 325°F. Start checking an hour before the time on the plan.",
             "It's done when a thermometer reads 165°F in the thickest part of the thigh, the wing and the breast (USDA).",
             "Rest it, loosely covered, for 30 minutes before carving. Keep the pan juices for the gravy."],
      schedule="turkey"),
 dict(id="tg_gravy", name="Pan gravy", course="side", vegetarian=False, servings=8, allergens=["gluten", "dairy"],
      ingredients=[ing("butter", 56, "4 tbsp"), ing("flour", 32, "¼ cup"), ing("chicken_broth", 946, "4 cups", "plus the pan juices")],
      steps=["Pour the pan juices into a jug and skim off the fat.", "Melt the butter in a saucepan, whisk in the flour and cook 2 minutes until golden.",
             "Whisk in the broth and juices a little at a time. Simmer 8 minutes until it coats a spoon. Season."],
      schedule=[(25, "Make the gravy while the turkey rests.")]),
 dict(id="tg_stuffing", name="Herb stuffing", course="side", vegetarian=True, servings=8, allergens=["gluten", "dairy"],
      ingredients=[ing("stuffing_cubes", 680, "2 bags", "12 oz each"), ing("celery", 200, "4 stalks", "diced"), ing("onion_yellow", 220, "1", "diced"),
                   ing("butter", 113, "½ cup"), ing("veg_broth", 710, "3 cups", "vegetable, so it's vegetarian"), ing("sage", 2, "1 tbsp"), ing("thyme", 1, "2 tsp")],
      steps=["Soften the onion and celery in the butter, 8 minutes. Stir in the herbs.", "Toss with the bread cubes and broth in a buttered 9×13 dish.",
             "Bake covered at 350°F for 25 minutes, then uncovered 20 minutes until crisp on top."],
      schedule=[(75, "Assemble the stuffing."), (55, "Stuffing into the oven (it shares the oven when the turkey comes out).")]),
 dict(id="tg_mash", name="Mashed potatoes", course="side", vegetarian=True, servings=8, allergens=["dairy"],
      ingredients=[ing("potatoes", 2270, "5 lb", "peeled, in chunks"), ing("butter", 113, "½ cup"), ing("milk", 240, "1 cup", "warm"), ing("salt", 12, "2 tsp")],
      steps=["Cover the potatoes with cold salted water, bring to a boil and simmer 15–20 minutes until a knife slides in.",
             "Drain well. Mash with the butter, then beat in the warm milk. Season."],
      schedule=[(60, "Peel the potatoes into cold water."), (40, "Potatoes on to boil."), (10, "Mash the potatoes.")]),
 dict(id="tg_beans", name="Garlic green beans", course="side", vegetarian=True, servings=8, allergens=[],
      ingredients=[ing("green_beans", 908, "2 lb", "trimmed"), ing("garlic", 4, "4 cloves", "sliced"), ing("olive_oil", 30, "2 tbsp"), ing("lemon", 1, "1")],
      steps=["Blanch the beans in boiling salted water for 4 minutes, then drain.", "Fry the garlic in the oil for 1 minute, toss in the beans, finish with lemon."],
      schedule=[(20, "Blanch the green beans."), (5, "Toss the beans with garlic.")]),
 dict(id="tg_cranberry", name="Cranberry orange sauce", course="side", vegetarian=True, servings=8, allergens=[],
      ingredients=[ing("cranberries", 340, "1 bag", "12 oz"), ing("sugar", 200, "1 cup"), ing("orange", 1, "1", "zest and juice")],
      steps=["Simmer everything with ½ cup water for 10 minutes, until most berries pop.", "Cool. It sets as it chills, and keeps 5 days in the fridge."],
      schedule=[(2 * 1440, "Make the cranberry sauce; it keeps in the fridge.")]),
 dict(id="tg_sweetpot", name="Honey roasted sweet potatoes", course="side", vegetarian=True, servings=8, allergens=[],
      ingredients=[ing("sweet_potato", 1360, "3 lb", "in 1 in cubes"), ing("olive_oil", 30, "2 tbsp"), ing("honey", 30, "2 tbsp"), ing("salt", 6, "1 tsp")],
      steps=["Toss with the oil and salt on two sheet pans.", "Roast at 425°F for 30 minutes, turning once. Drizzle with honey for the last 5 minutes."],
      schedule=[(50, "Cube the sweet potatoes."), (35, "Sweet potatoes in the oven at 425°F (after the turkey comes out).")]),
 dict(id="tg_squash", name="Roast squash with chickpeas and feta", course="main", vegetarian=True, servings=4, allergens=["dairy"],
      ingredients=[ing("butternut_squash", 1, "1", "about 2 lb, in wedges"), ing("chickpeas", 1, "1 can", "drained"), ing("feta", 100, "⅔ cup"),
                   ing("spinach", 142, "1 box"), ing("honey", 15, "1 tbsp"), ing("olive_oil", 30, "2 tbsp")],
      steps=["Roast the squash wedges and chickpeas with oil and salt at 425°F for 35 minutes.", "Wilt the spinach underneath, top with feta and a drizzle of honey."],
      schedule=[(45, "Vegetarian main: squash and chickpeas into the oven.")], forVegetarians=True),
 dict(id="tg_pie", name="Pumpkin pie", course="dessert", vegetarian=True, servings=8, allergens=["gluten", "dairy", "egg"],
      ingredients=[ing("pie_crust", 1, "1 crust", "of a 2-pack"), ing("pumpkin_puree", 425, "1 can"), ing("evaporated_milk", 354, "1 can"),
                   ing("eggs", 2, "2"), ing("sugar", 150, "¾ cup"), ing("pumpkin_spice", 6, "2 tsp"), ing("heavy_cream", 240, "1 cup", "whipped, to serve")],
      steps=["Whisk the pumpkin, milk, eggs, sugar and spice.", "Pour into the crust and bake at 425°F for 15 minutes, then 350°F for 40–50 minutes until just set in the middle.",
             "Cool at least 2 hours. Whip the cream to serve."],
      schedule=[(1440, "Bake the pie (it's best made the day before).")]),
]
for d in dishes:
    if d["schedule"] != "turkey":
        d["schedule"] = [{"minutesBefore": m, "task": t} for m, t in d["schedule"]]
    else:
        d["schedule"] = []
    d.setdefault("forVegetarians", False)
menu = {"id": "thanksgiving", "name": "Thanksgiving", "defaultDate": "2026-11-26T16:00:00",
        "main": {"kind": "turkey", "ingredient": "turkey_whole", "lbPerPerson": 1.25, "minLb": 8}, "dishes": dishes}
json.dump(menu, open(os.path.join(R, "holiday-thanksgiving.json"), "w"), indent=1, ensure_ascii=False)

xmas = [
 dict(id="xm_ham", name="Honey-mustard glazed ham", course="main", vegetarian=False, servings=8, allergens=[],
      ingredients=[ing("ham_spiral", 2720, "1 spiral ham, about 6 lb for 8", "fully cooked, bone-in"), ing("honey", 85, "¼ cup"),
                   ing("brown_sugar", 55, "¼ cup"), ing("dijon", 30, "2 tbsp")],
      steps=["Heat the oven to 325°F. Unwrap the ham, set it cut side down in a roasting pan, add ½ cup water and cover tightly with foil.",
             "Heat until it reads 140°F in the thickest part (USDA, for fully cooked ham): about 10–14 minutes per pound.",
             "Whisk the honey, brown sugar and mustard. For the last 20 minutes, uncover, brush on the glaze and turn the oven to 400°F.",
             "Keep it covered with foil while the sides roast; it stays hot for about 45 minutes. Slice along the bone."],
      schedule=[]),
 dict(id="xm_potatoes", name="Garlic roast potatoes", course="side", vegetarian=True, servings=8, allergens=[],
      ingredients=[ing("potatoes", 1810, "4 lb", "in chunks"), ing("olive_oil", 60, "¼ cup"), ing("garlic", 6, "6 cloves", "smashed"),
                   ing("thyme", 2, "1 tsp"), ing("salt", 10, "2 tsp")],
      steps=["Parboil the potatoes 8 minutes; drain and shake to rough the edges.", "Toss with the oil, garlic, thyme and salt. Roast at 425°F for 40–45 minutes, turning once."],
      schedule=[(90, "Peel and cut the potatoes."), (65, "Parboil the potatoes."), (44, "Potatoes into the oven at 425°F (the ham is out and resting).")]),
 dict(id="xm_carrots", name="Honey roast carrots", course="side", vegetarian=True, servings=8, allergens=[],
      ingredients=[ing("carrots", 907, "2 lb", "halved lengthwise"), ing("olive_oil", 30, "2 tbsp"), ing("honey", 30, "2 tbsp")],
      steps=["Toss with the oil and salt and roast at 425°F for 30 minutes.", "Drizzle with honey for the last 5 minutes."],
      schedule=[(38, "Carrots into the oven at 425°F.")]),
 dict(id="xm_sprouts", name="Crispy Brussels sprouts with parmesan", course="side", vegetarian=True, servings=8, allergens=["dairy"],
      ingredients=[ing("brussels_sprouts", 1360, "3 lb", "trimmed and halved"), ing("olive_oil", 45, "3 tbsp"), ing("parmesan", 40, "½ cup"), ing("lemon", 1, "1")],
      steps=["Toss with oil and salt, cut side down on a sheet pan.", "Roast at 425°F for 25 minutes until deeply browned. Finish with parmesan and lemon."],
      schedule=[(30, "Brussels sprouts into the oven.")]),
 dict(id="xm_mac", name="Baked mac and cheese", course="side", vegetarian=True, servings=8, allergens=["gluten", "dairy"],
      ingredients=[ing("elbow_pasta", 454, "1 box", "1 lb"), ing("butter", 56, "4 tbsp"), ing("flour", 32, "¼ cup"), ing("milk", 720, "3 cups"),
                   ing("cheddar", 340, "3 cups", "grated"), ing("salt", 6, "1 tsp")],
      steps=["Cook the pasta 2 minutes short of the box time; drain.", "Melt the butter, whisk in the flour for 1 minute, then the milk; simmer until thick. Stir in most of the cheese.",
             "Fold in the pasta, top with the rest of the cheese and bake at 425°F for 20–25 minutes, until bubbling."],
      schedule=[(1440, "Make the mac and cheese and refrigerate it unbaked."), (30, "Mac and cheese into the oven at 425°F with the vegetables.")]),
 dict(id="xm_rolls", name="Warm dinner rolls", course="side", vegetarian=True, servings=8, allergens=["gluten", "dairy"],
      ingredients=[ing("dinner_rolls", 12, "12 rolls"), ing("butter", 56, "4 tbsp", "to serve")],
      steps=["Warm the rolls wrapped in foil for 10 minutes while the ham rests."], schedule=[(12, "Warm the rolls.")]),
 dict(id="xm_pie", name="Mushroom and lentil pot pie", course="main", vegetarian=True, servings=4, allergens=["gluten", "dairy"],
      ingredients=[ing("mushrooms", 454, "1 lb", "sliced"), ing("lentils_red", 100, "½ cup"), ing("carrots", 150, "2", "diced"),
                   ing("onion_yellow", 220, "1", "diced"), ing("veg_broth", 475, "2 cups"), ing("thyme", 1, "1 tsp"), ing("puff_pastry", 1, "1 sheet", "thawed")],
      steps=["Brown the mushrooms, then soften the onion and carrot. Add the lentils, broth and thyme and simmer 15 minutes until thick.",
             "Spoon into a baking dish, top with the pastry, cut a vent and bake at 400°F for 25 minutes until puffed and golden."],
      schedule=[(1440, "Make the vegetarian pot pie filling and refrigerate it."), (35, "Vegetarian pot pie into the oven at 425°F; check it at 25 minutes.")], forVegetarians=True),
 dict(id="xm_crisp", name="Apple crisp", course="dessert", vegetarian=True, servings=8, allergens=["gluten", "dairy"],
      ingredients=[ing("apples", 6, "6", "peeled and sliced"), ing("sugar", 50, "¼ cup"), ing("cinnamon", 3, "1 tsp"), ing("oats", 90, "1 cup"),
                   ing("flour", 60, "½ cup"), ing("brown_sugar", 110, "½ cup"), ing("butter", 113, "½ cup", "cold, cubed")],
      steps=["Toss the apples with the sugar and cinnamon in a baking dish.", "Rub the oats, flour, brown sugar and butter into crumbs and scatter over.",
             "Bake at 350°F for 45 minutes until bubbling. Rewarm it in the cooling oven while you eat."],
      schedule=[(420, "Bake the apple crisp this morning, while the oven is free.")]),
]
for d in xmas:
    d["schedule"] = [{"minutesBefore": m, "task": t} for m, t in d["schedule"]]
    d.setdefault("forVegetarians", False)
json.dump({"id": "christmas", "name": "Christmas", "defaultDate": "2026-12-25T15:00:00",
           "main": {"kind": "ham", "ingredient": "ham_spiral", "lbPerPerson": 0.75, "minLb": 6}, "dishes": xmas},
          open(os.path.join(R, "holiday-christmas.json"), "w"), indent=1, ensure_ascii=False)
print(len(dishes), "dishes;", len(new), "ingredients checked")
