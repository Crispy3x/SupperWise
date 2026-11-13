#!/usr/bin/env python3
"""Downloads the chosen photo for each recipe (tools/photos/picks.json: {recipe_id: candidate index or null}),
crops it square around the centre at 720 px (the app shows it in a round plate), and writes
Supperwise/Resources/photos/rp_<id>.jpg plus Supperwise/Resources/photo-credits.json. Usage: fetch_photos.py"""
import io, json, os, sys, time, urllib.request
from PIL import Image
HERE = os.path.dirname(__file__)
RES = os.path.join(HERE, "..", "..", "Supperwise", "Resources")
OUT = os.path.join(RES, "photos"); os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "SupperwiseRecipePhotos/1.0 (meal-planner app; photo attribution tool)"}
cands = json.load(open(os.path.join(HERE, "candidates.json")))
picks = json.load(open(os.path.join(HERE, "picks.json")))
credits_path = os.path.join(RES, "photo-credits.json")
credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {}
ok = fail = 0
for rid, idx in sorted(picks.items()):
    if idx is None or rid not in cands or idx >= len(cands[rid]["candidates"]): continue
    c = cands[rid]["candidates"][idx]
    path = os.path.join(OUT, f"rp_{rid}.jpg")
    if not os.path.exists(path):
        try:
            data = urllib.request.urlopen(urllib.request.Request(c["url"], headers=UA), timeout=60).read()
            img = Image.open(io.BytesIO(data)).convert("RGB")
            side = min(img.size); l, t = (img.width - side) // 2, (img.height - side) // 2
            img.crop((l, t, l + side, t + side)).resize((720, 720), Image.LANCZOS).save(path, quality=72, optimize=True, progressive=True)
            time.sleep(0.3)
        except Exception as e:
            print("failed", rid, e); fail += 1; continue
    credits[rid] = {"title": c["title"][:120], "creator": c["creator"][:80], "license": c["license"],
                    "licenseVersion": c["license_version"], "licenseURL": c.get("license_url"), "page": c.get("page")}
    ok += 1
json.dump(credits, open(credits_path, "w"), indent=1, ensure_ascii=False, sort_keys=True)
print(f"{ok} photos, {fail} failed")
