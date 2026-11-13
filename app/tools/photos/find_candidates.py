#!/usr/bin/env python3
"""Finds candidate photos for each recipe from openly licensed sources (commercial use allowed) and records
attribution. Openverse first (200 anonymous searches a day), Wikimedia Commons for the rest.
Writes tools/photos/candidates.json; safe to re-run (it resumes)."""
import json, os, re, sys, time, urllib.parse, urllib.request, html
HERE = os.path.dirname(__file__)
RES = os.path.join(HERE, "..", "..", "Supperwise", "Resources")
OUT = os.path.join(HERE, "candidates.json")
UA = {"User-Agent": "SupperwiseRecipePhotos/1.0 (meal-planner app; photo attribution tool)"}
OPENVERSE_BUDGET = int(sys.argv[1]) if len(sys.argv) > 1 else 180
OK_LICENSES = {"cc0", "pdm", "by", "by-sa"}

def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r: return json.load(r)

def query_for(name):
    n = re.sub(r"\(.*?\)", "", name)
    n = re.split(r"\bwith\b|,|\bover\b|\bon\b", n, flags=re.I)[0]
    n = re.sub(r"\b(sheet-pan|sheet pan|slow-cooker|slow cooker|air fryer|air-fryer|one-pot|one-pan|weeknight|easy|quick|skillet|baked|grilled|crispy|creamy|classic|simple|style|-style)\b", " ", n, flags=re.I)
    return re.sub(r"\s+", " ", n).strip(" -") or name

def openverse(q):
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode({"q": q, "license": ",".join(sorted(OK_LICENSES)), "page_size": 10, "mature": "false"})
    out = []
    for r in get(url).get("results", []):
        if (r.get("width") or 0) < 640: continue
        out.append(dict(src="openverse", url=r["url"], title=r.get("title") or "", creator=r.get("creator") or "Unknown",
                        creator_url=r.get("creator_url"), license=r["license"], license_version=r.get("license_version") or "",
                        license_url=r.get("license_url"), page=r.get("foreign_landing_url"), w=r.get("width"), h=r.get("height")))
    return out

def commons(q):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6, "gsrlimit": 12,
        "gsrsearch": f"{q} food filetype:bitmap", "prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": 1200})
    out = []
    for p in (get(url).get("query", {}).get("pages", {}) or {}).values():
        ii = (p.get("imageinfo") or [{}])[0]; md = ii.get("extmetadata", {})
        lic = (md.get("LicenseShortName", {}).get("value") or "").lower()
        if lic.startswith("cc0") or "public domain" in lic: key, ver = ("cc0" if lic.startswith("cc0") else "pdm"), ""
        else:
            m = re.match(r"cc[ -]by(-sa)?[ -]([\d.]+)", lic)
            if not m: continue
            key, ver = ("by-sa" if m.group(1) else "by"), m.group(2)
        if (ii.get("width") or 0) < 640: continue
        artist = re.sub("<[^>]+>", "", html.unescape(md.get("Artist", {}).get("value") or "Unknown")).strip()[:80]
        out.append(dict(src="commons", url=ii.get("thumburl") or ii["url"], title=p.get("title", "").replace("File:", ""),
                        creator=artist or "Unknown", creator_url=None, license=key, license_version=ver,
                        license_url=md.get("LicenseUrl", {}).get("value"), page=ii.get("descriptionurl"), w=ii.get("width"), h=ii.get("height")))
    return out

recipes = json.load(open(os.path.join(RES, "recipes.json")))
done = json.load(open(OUT)) if os.path.exists(OUT) else {}
used_openverse = sum(1 for v in done.values() if v.get("via") == "openverse")
for r in recipes:
    if r["id"] in done: continue
    q = query_for(r["name"])
    try:
        if used_openverse < OPENVERSE_BUDGET:
            c, via = openverse(q), "openverse"; used_openverse += 1; time.sleep(3.3)
            if len(c) < 3: c += commons(q); time.sleep(0.5)
        else:
            c, via = commons(q), "commons"; time.sleep(0.7)
    except Exception as e:
        print("error", r["id"], e, file=sys.stderr); time.sleep(10); continue
    done[r["id"]] = {"name": r["name"], "query": q, "via": via, "candidates": c[:8]}
    json.dump(done, open(OUT, "w"), indent=1, ensure_ascii=False)
    print(len(done), r["id"], q, len(c), flush=True)
print("finished", len(done), "recipes;", sum(1 for v in done.values() if not v["candidates"]), "with no candidates")
