#!/usr/bin/env python3
"""Builds preview/supperwise-prototype.html from preview/template.html with the app's current data.
Images are reused from the previous build (they come from design/ and rarely change)."""
import json, os, re
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "app", "Supperwise", "Resources")
OUT = os.path.join(ROOT, "preview", "supperwise-prototype.html")
old = open(OUT).read()
img = re.search(r"^const IMG = (.*);$", old, re.M).group(1)
data = json.loads(re.search(r"^const DATA = (.*);$", old, re.M).group(1))
data["ingredients"] = json.load(open(os.path.join(RES, "ingredients.json")))
lunch = json.load(open(os.path.join(RES, "lunches.json")))
data["lunches"], data["lunchNotes"] = lunch["lunches"], lunch["notes"]
html = open(os.path.join(ROOT, "preview", "template.html")).read()
html = html.replace("__DATA__", json.dumps(data, ensure_ascii=False), 1).replace("__IMAGES__", img, 1)
open(OUT, "w").write(html)
print("wrote", OUT, len(html) // 1024, "KB")
