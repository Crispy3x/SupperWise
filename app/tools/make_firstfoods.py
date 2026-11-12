# Writes Supperwise/Resources/first-foods.json: 100 first foods with how to serve them by age, and the common allergens.
# Guidance follows widely published US advice (AAP, CDC, NIAID): solids from about 6 months when developmentally ready;
# no honey before 12 months; no cow's milk as a drink before 12 months; cut or avoid choking hazards; introduce common
# allergens one at a time and keep offering them. It is general information; families follow their pediatrician.
import json, os
OUT = os.path.join(os.path.dirname(__file__), "..", "Supperwise", "Resources", "first-foods.json")

SERVE = {
 "veg": ("Steam until soft enough to squash between your fingers. Mash, or offer finger-length strips.", "Soft, bite-size pieces."),
 "fruit": ("Ripe and soft: mash, or offer large slices that are easy to hold.", "Soft, bite-size pieces."),
 "protein": ("Cook through. Shred very finely, mash, or offer a large strip to hold and suck.", "Small, tender pieces."),
 "grain": ("Soft-cooked. Thin with breast milk or formula if needed.", "Soft pieces or small spoonfuls."),
 "dairy": ("Plain, whole-milk versions. No added sugar.", "Small amounts as part of meals."),
}
F = [  # name, category, allergen or None, from months, override for 6–8 months (None = category default), hazard note
 # Vegetables
 ("Sweet potato","veg",None,6,None,None),("Carrot","veg",None,6,"Steam or roast until very soft. Raw carrot is a choking hazard.",None),
 ("Broccoli","veg",None,6,"Steam whole florets until soft; the stalk makes a handle.",None),("Zucchini","veg",None,6,None,None),
 ("Butternut squash","veg",None,6,None,None),("Peas","veg",None,6,"Mash or flatten each pea. Whole peas can be a choking risk.",None),
 ("Green beans","veg",None,6,"Steam until very soft; offer whole for holding.",None),("Cauliflower","veg",None,6,None,None),
 ("Spinach","veg",None,6,"Finely chop and mix into other food.",None),("Potato","veg",None,6,None,None),
 ("Pumpkin","veg",None,6,None,None),("Parsnip","veg",None,6,None,None),("Beet","veg",None,6,None,None),
 ("Bell pepper","veg",None,6,"Roast until soft, skin removed, in strips.",None),("Asparagus","veg",None,6,"Steam spears until very soft.",None),
 ("Corn","veg",None,6,"Offer on the cob to gnaw, or mash kernels. Loose whole kernels can be a choking risk.",None),
 ("Kale","veg",None,6,"Finely chop and cook into other food.",None),("Cucumber","veg",None,6,"Peeled, in long thick spears, for gnawing under supervision.",None),
 ("Tomato","veg",None,6,"Ripe, skin removed, in soft wedges. Quarter cherry tomatoes.","Cherry tomatoes: quarter them."),
 ("Mushroom","veg",None,6,"Cooked until soft, finely chopped.",None),("Eggplant","veg",None,6,None,None),("Cabbage","veg",None,6,None,None),
 ("Leek","veg",None,6,"Cooked until very soft, finely chopped.",None),("Turnip","veg",None,6,None,None),("Celery","veg",None,9,"Cooked until soft and finely chopped; raw celery is stringy.",None),
 # Fruits
 ("Banana","fruit",None,6,"Half a peeled banana, or mashed.",None),("Avocado","fruit",None,6,"Ripe spears, or mashed.",None),
 ("Apple","fruit",None,6,"Cooked until soft, or finely grated. Raw apple pieces are a choking hazard.","Raw apple: thin slices only once chewing is strong."),
 ("Pear","fruit",None,6,"Ripe and soft, or cooked.",None),("Mango","fruit",None,6,"Ripe spears, or the pit with some flesh to gnaw.",None),
 ("Peach","fruit",None,6,"Ripe, skin off, in soft slices.",None),("Plum","fruit",None,6,"Ripe, skin off, pit removed, in soft slices.",None),
 ("Blueberries","fruit",None,6,"Flatten or mash each one. Whole berries are a choking hazard.","Cut in half until chewing is strong."),
 ("Strawberries","fruit",None,6,"Large whole berries to hold, or mashed.",None),("Raspberries","fruit",None,6,"Flattened or mashed.",None),
 ("Grapes","fruit",None,6,"Quarter lengthwise, every time. Whole grapes are a top choking hazard.","Quarter lengthwise until at least age 4."),
 ("Melon","fruit",None,6,"Ripe, rind off, in thick strips.",None),("Watermelon","fruit",None,6,"Seedless, in thick sticks.",None),
 ("Kiwi","fruit",None,6,"Ripe, peeled, in halves or mashed.",None),("Orange","fruit",None,6,"Segments with membranes and seeds removed, or flattened.",None),
 ("Papaya","fruit",None,6,None,None),("Pineapple","fruit",None,6,"Ripe, in thin spears.",None),("Cherries","fruit",None,6,"Pitted and quartered.","Pitted and quartered."),
 ("Apricot","fruit",None,6,"Ripe or cooked, skin off.",None),("Dates","fruit",None,9,"Pitted, soaked and finely chopped. Whole dried fruit is a choking hazard.",None),
 ("Prunes","fruit",None,6,"Pitted and puréed or finely chopped.",None),
 # Protein
 ("Chicken","protein",None,6,None,None),("Turkey","protein",None,6,None,None),("Beef","protein",None,6,"Ground and cooked through, or a large strip to suck.",None),
 ("Pork","protein",None,6,None,None),("Lamb","protein",None,6,None,None),("Lentils","protein",None,6,"Cooked until very soft and mashed.",None),
 ("Black beans","protein",None,6,"Mashed or flattened.",None),("Chickpeas","protein",None,6,"Mashed, or as smooth hummus.","Whole chickpeas: flatten them."),
 ("Tofu","protein","soy",6,"Firm tofu in strips, or crumbled.",None),("Kidney beans","protein",None,6,"Well cooked, mashed.",None),
 ("White beans","protein",None,6,"Mashed or flattened.",None),("Edamame","protein","soy",6,"Shelled and mashed. Whole beans are a choking risk.",None),
 # Allergen foods
 ("Egg","protein","egg",6,"Well-cooked: hard-boiled in quarters, or an omelette in strips.",None),
 ("Peanut","protein","peanut",6,"Smooth peanut butter thinned with water or breast milk, or peanut powder stirred into food. Never whole peanuts or thick globs.","Whole nuts stay off the menu until at least age 4."),
 ("Tree nuts","protein","tree nut",6,"Smooth nut butter (almond, cashew) thinned, or finely ground into food. Never whole nuts.","Whole nuts stay off the menu until at least age 4."),
 ("Salmon","protein","fish",6,"Cooked through, flaked, every bone removed.",None),("Cod","protein","fish",6,"Cooked through, flaked, every bone removed.",None),
 ("Tuna, canned light","protein","fish",6,"Flaked into other food. Choose light tuna, which is lower in mercury.",None),
 ("Shrimp","protein","shellfish",6,"Cooked, finely chopped or ground.",None),
 ("Sesame","protein","sesame",6,"Smooth tahini thinned, or stirred into hummus or yogurt.",None),
 ("Yogurt","dairy","dairy",6,"Plain whole-milk yogurt on a preloaded spoon.",None),("Cheese","dairy","dairy",6,"Pasteurised, mild: thin slices or grated. Cubes are a choking risk.",None),
 ("Cottage cheese","dairy","dairy",6,"Plain, whole-milk.",None),("Butter","dairy","dairy",6,"A little melted into vegetables.",None),
 ("Cow's milk (as a drink)","dairy","dairy",12,"Not as a drink before 12 months. Small amounts cooked into food are fine.",None),
 ("Wheat","grain","wheat",6,"Soft toast strips, or well-cooked pasta.",None),
 # Grains
 ("Oatmeal","grain",None,6,None,None),("Rice","grain",None,6,"Soft-cooked; vary grains (rice can contain arsenic, so not every day).",None),
 ("Pasta","grain","wheat",6,"Well-cooked large shapes to hold.",None),("Quinoa","grain",None,6,None,None),("Barley","grain","wheat",6,None,None),
 ("Toast","grain","wheat",6,"Lightly toasted, thin strips.",None),("Pancakes","grain","wheat",9,"Soft strips, no syrup or honey.",None),
 ("Couscous","grain","wheat",6,None,None),("Polenta","grain",None,6,"Soft, or set and cut into fingers.",None),("Tortilla","grain","wheat",9,"Soft strips.",None),
 ("Millet","grain",None,6,None,None),("Buckwheat","grain",None,9,None,None),
 # Herbs, spices and flavours
 ("Cinnamon","veg",None,6,"A pinch stirred into fruit or oatmeal.",None),("Garlic","veg",None,6,"Cooked into food.",None),
 ("Cumin","veg",None,6,"A pinch cooked into food. No chili heat yet.",None),("Ginger","veg",None,6,"A little cooked into food.",None),
 ("Herbs (parsley, basil, dill)","veg",None,6,"Finely chopped into food.",None),("Lemon","fruit",None,6,"A squeeze over food.",None),
 ("Coconut","fruit",None,6,"Unsweetened, finely grated or as coconut milk in cooking.",None),
 ("Honey","fruit",None,12,"Never before 12 months, even baked in: risk of infant botulism.",None),
 # More vegetables and fruit to reach 100
 ("Artichoke","veg",None,9,"Soft-cooked hearts, finely chopped.",None),("Okra","veg",None,6,"Cooked until soft, in whole pods to hold.",None),
 ("Bok choy","veg",None,6,"Cooked until soft, finely chopped.",None),("Swiss chard","veg",None,6,"Cooked, finely chopped.",None),
 ("Fig","fruit",None,6,"Ripe and soft, halved.",None),("Pomegranate","fruit",None,9,"Arils flattened or mixed into yogurt, seeds can be hard: supervise.",None),
 ("Persimmon","fruit",None,6,"Very ripe, peeled, in soft slices.",None),("Nectarine","fruit",None,6,"Ripe, skin off, in soft slices.",None),
 ("Sardines","protein","fish",9,"Canned in water, mashed, bones crushed fine.",None),("Duck","protein",None,9,"Cooked through, finely shredded.",None),
 ("Ricotta","dairy","dairy",6,"Plain, whole-milk, on a spoon.",None),("Hummus","protein","sesame",6,"Smooth, on a spoon or toast strip.",None),
 ("Brown rice","grain",None,6,"Soft-cooked, mashed lightly.",None),("Sweet corn polenta cakes","grain",None,9,"Soft fingers.",None),
]
foods = []
for name, cat, allergen, frm, prep6, later in F:
    p6, p9 = SERVE[cat]
    foods.append(dict(id=name.lower().replace("'", "").replace(",", "").replace("(", "").replace(")", "").replace(" ", "_"),
                      name=name, category=cat, allergen=allergen, fromMonths=frm,
                      serve6=prep6 or p6, serve9=later or p9))
assert len(foods) == len({f["id"] for f in foods})
allergens = ["peanut", "egg", "dairy", "wheat", "soy", "fish", "shellfish", "tree nut", "sesame"]
json.dump({"foods": foods, "allergens": allergens,
           "notes": ["Start solids at about 6 months, when your baby sits with support and shows interest. Your pediatrician can tell you when your baby is ready.",
                     "Introduce common allergens one at a time, and keep offering them a few times a week once tolerated. If your baby has severe eczema or an egg allergy, talk to your pediatrician before introducing peanut.",
                     "Always supervise meals with your baby sitting upright. Gagging is normal while learning; choking is silent. Learn infant first aid.",
                     "Call 911 for trouble breathing, swelling of the lips or face, repeated vomiting or floppiness after a new food."]},
          open(OUT, "w"), indent=1, ensure_ascii=False)
print(len(foods), "foods,", sum(1 for f in foods if f["allergen"]), "allergen foods")
