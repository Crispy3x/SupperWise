#!/usr/bin/env python3
"""Downloads candidate thumbnails and lays them out as contact sheets (5 recipes per sheet, up to 8 candidates
each) so each recipe's photo can be chosen by eye. Usage: make_sheets.py <cache dir> <sheet dir>"""
import json, os, sys, io, urllib.request, concurrent.futures as cf
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(__file__)
CACHE, SHEETS = sys.argv[1], sys.argv[2]
os.makedirs(CACHE, exist_ok=True); os.makedirs(SHEETS, exist_ok=True)
UA = {"User-Agent": "SupperwiseRecipePhotos/1.0 (meal-planner app; photo attribution tool)"}
cands = json.load(open(os.path.join(HERE, "candidates.json")))

def thumb(rid, i, url):
    path = os.path.join(CACHE, f"{rid}__{i}.jpg")
    if os.path.exists(path): return path
    try:
        req = urllib.request.Request(url, headers=UA)
        img = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=40).read())).convert("RGB")
        img.thumbnail((300, 300)); img.save(path, quality=80); return path
    except Exception as e:
        return None

jobs = [(rid, i, c["url"]) for rid, v in cands.items() for i, c in enumerate(v["candidates"])]
with cf.ThreadPoolExecutor(8) as ex: list(ex.map(lambda j: thumb(*j), jobs))

try: font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22); small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
except Exception: font = small = ImageFont.load_default()
ids = [rid for rid, v in cands.items() if v["candidates"]]
W, H, LABEL = 300, 225, 40
index = {}
for s in range(0, len(ids), 5):
    group = ids[s:s + 5]
    sheet = Image.new("RGB", (8 * W + 20, len(group) * (H + LABEL + 14) + 10), "white")
    d = ImageDraw.Draw(sheet)
    for row, rid in enumerate(group):
        y = 10 + row * (H + LABEL + 14)
        d.text((10, y), f"{s + row}: {cands[rid]['name']}", fill="black", font=font)
        for i in range(len(cands[rid]["candidates"])):
            p = os.path.join(CACHE, f"{rid}__{i}.jpg")
            x = 10 + i * W
            if os.path.exists(p):
                im = Image.open(p); im.thumbnail((W - 8, H)); sheet.paste(im, (x, y + LABEL))
            d.rectangle([x, y + LABEL, x + 34, y + LABEL + 28], fill="black"); d.text((x + 8, y + LABEL + 2), str(i), fill="white", font=small)
    name = f"sheet_{s // 5:03d}.jpg"
    sheet.save(os.path.join(SHEETS, name), quality=70)
    index[name] = group
json.dump(index, open(os.path.join(SHEETS, "index.json"), "w"), indent=1)
print(len(index), "sheets for", len(ids), "recipes;", len(cands) - len(ids), "recipes have no candidates")
