#!/usr/bin/env python3
"""Fills in the App Store listing for Supperwise through Apple's API: name, subtitle, categories, privacy URL,
description, keywords, promotional text, support/marketing URLs, copyright, age rating answers and the
6.9-inch iPhone screenshots. Safe to re-run: text is overwritten, screenshots are replaced.

Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 and optionally SITE_BASE (e.g. https://crispy3x.github.io/supperwise-site)
for the privacy and support links. Reuses the API helpers from asc_setup.py."""
import glob, hashlib, json, os, sys
sys.argv = sys.argv[:1]
HERE = os.path.dirname(__file__)
src = open(os.path.join(HERE, "asc_setup.py")).read()
exec(src[:src.index("# 1. Bundle ID and capabilities")])  # imports, call(), all_pages(), step(), token()

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
listing = json.load(open(os.path.join(ROOT, "launch", "listing", "listing.json")))
L = listing["locales"]["en-US"]
SITE = os.environ.get("SITE_BASE", "").rstrip("/")
privacy = f"{SITE}/privacy.html" if SITE else None
support = f"{SITE}/support.html" if SITE else None
description = L["description"].replace("PRIVACY_URL", privacy or "available in the app under Settings")

step("App")
apps = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).get("data", [])
if not apps: print("::error::No app record yet."); sys.exit(1)
app = apps[0]; print(app["attributes"]["name"])

step("App information: name, subtitle, privacy link, categories")
infos = all_pages(f"/v1/apps/{app['id']}/appInfos")
info = next((i for i in infos if i["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", None)), infos[0])
for loc in all_pages(f"/v1/appInfos/{info['id']}/appInfoLocalizations"):
    if loc["attributes"]["locale"] != "en-US": continue
    attrs = {"name": L["name"], "subtitle": L["subtitle"]}
    if privacy: attrs["privacyPolicyUrl"] = privacy
    try:
        call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
        print("name, subtitle" + (", privacy link" if privacy else "") + " set")
    except RuntimeError as e:
        # The name may be taken; keep whatever name the app record has.
        attrs.pop("name"); call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
        print(f"subtitle set; name left as is ({e})")
try:
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "FOOD_AND_DRINK"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}})
    print("categories: Food & Drink, Lifestyle")
except RuntimeError as e:
    print(f"categories: {e}")

step("Age rating")
try:
    decl = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    none = "NONE"
    answers = {k: none for k in ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
               "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
               "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
               if k in decl["attributes"]}
    for k in ["gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "advertising", "ageAssurance", "parentalControls", "healthOrWellnessTopics"]:
        if k in decl["attributes"]: answers[k] = False
    if "userGeneratedContent" in decl["attributes"]: answers["userGeneratedContent"] = True   # community recipes (moderated)
    import re as _re
    # Apple adds questions over time: answer any it says are missing ("NONE" for frequency questions, no for yes/no ones).
    for attempt in range(6):
        try:
            call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": answers}})
            break
        except RuntimeError as e:
            msg = str(e)
            missing = _re.findall(r"value for the attribute '(\w+)'", msg)
            invalid = _re.findall(r'"pointer" : "/data/attributes/(\w+)"', msg) if "INVALID" in msg or "invalid" in msg else []
            if not missing and not invalid: raise
            for k in missing: answers.setdefault(k, "NONE")
            for k in invalid: answers[k] = False if answers.get(k) == "NONE" else "NONE"
            print(f"added answers for: {', '.join(missing + invalid)}")
    print(f"answered {len(answers)} questions (none of the mature themes; moderated user recipes)")
except RuntimeError as e:
    print(f"age rating: answer it in App Store Connect › App Information ({e})")

step("Version 1.0 text")
versions = all_pages(f"/v1/apps/{app['id']}/appStoreVersions", {"filter[platform]": "IOS"})
version = next((v for v in versions if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not version: print("::error::No editable version found."); sys.exit(1)
call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": {"copyright": "2026 Supperwise"}}})
vloc = next((l for l in all_pages(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations") if l["attributes"]["locale"] == "en-US"), None)
attrs = {"description": description, "keywords": L["keywords"], "promotionalText": L["promotionalText"]}
if support: attrs.update(supportUrl=support, marketingUrl=SITE + "/")
call("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": attrs}})
print("description, keywords, promotional text" + (", support and marketing links" if support else "") + " set")

step("Screenshots (6.9-inch iPhone, 1290 × 2796)")
shots = sorted(glob.glob(os.path.join(ROOT, "launch", "screenshots", "iphone-max", "*.png")))
sets = all_pages(f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")
sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
if not sset:
    sset = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}}}})["data"]
for old in all_pages(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots"):
    call("DELETE", f"/v1/appScreenshots/{old['id']}")
for path in shots:
    data = open(path, "rb").read()
    res = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
               "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
    for op in res["attributes"]["uploadOperations"]:
        requests.request(op["method"], op["url"], data=data[op["offset"]:op["offset"] + op["length"]], timeout=120,
                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])}).raise_for_status()
    call("PATCH", f"/v1/appScreenshots/{res['id']}", {"data": {"type": "appScreenshots", "id": res["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("uploaded", os.path.basename(path))

step("Done")
print("Still yours in App Store Connect: App Review contact details, the build to submit (after TestFlight), "
      "and the App Privacy answers (see app/launch/review/privacy-label.md).")
