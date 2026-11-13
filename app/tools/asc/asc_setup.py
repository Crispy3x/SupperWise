#!/usr/bin/env python3
"""Sets up Supperwise in App Store Connect through Apple's official API, so nobody has to click through it.

What it does (each step is safe to re-run; anything already there is left alone):
  1. Registers the bundle ID com.supperwise.app (In-App Purchase is on by default) and turns on App Groups.
  2. Finds the app record (create it once by hand: App Store Connect → Apps → + → New App).
  3. Creates the "Supperwise" subscription group and the 6 subscriptions with names and descriptions.
  4. Prices each one in the US and sets Apple's equivalent price in every other country.
  5. Adds a 1-week free trial to the yearly plans.
  6. Attaches the plans screenshot Apple's review needs for each subscription.

Needs: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (environment variables; GitHub passes them from repository secrets).
"""
import hashlib, json, os, sys, time
import jwt, requests

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.supperwise.app")
SCREENSHOT = os.environ.get("REVIEW_SCREENSHOT", "app/launch/captures/iphone/plans.png")

PLANS = [  # product id, reference name, period, level (1 = highest), US price, display name, description (≤ 55 chars)
    ("monthly", "Pro Monthly", "ONE_MONTH", 1, "14.99", "Supperwise Pro", "Everything, plus the fridge scan"),
    ("yearly", "Pro Yearly", "ONE_YEAR", 1, "79.99", "Supperwise Pro (Yearly)", "Everything, plus the fridge scan"),
    ("family_monthly", "Family Monthly", "ONE_MONTH", 2, "9.99", "Supperwise Family", "Lunches, first foods, food scan, scores"),
    ("family_yearly", "Family Yearly", "ONE_YEAR", 2, "49.99", "Supperwise Family (Yearly)", "Lunches, first foods, food scan, scores"),
    ("plus_monthly", "Plus Monthly", "ONE_MONTH", 3, "5.99", "Supperwise Plus", "A new priced week of dinners every Sunday"),
    ("plus_yearly", "Plus Yearly", "ONE_YEAR", 3, "29.99", "Supperwise Plus (Yearly)", "A new priced week of dinners every Sunday"),
]
REVIEW_NOTE = ("Auto-renewing subscription unlocking Supperwise features. Reviewers can open Settings → See plans; "
               "purchases use the sandbox. Each higher plan includes the lower plans' features.")

_token = {"value": None, "at": 0}


def token():
    if not _token["value"] or time.time() - _token["at"] > 600:
        key = os.environ["ASC_KEY_P8"].replace("\\n", "\n")
        now = int(time.time())
        _token["value"] = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                                     key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
        _token["at"] = time.time()
    return _token["value"]


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    for attempt in range(5):
        r = requests.request(method, API + path, json=body, params=params, timeout=60,
                             headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(5 * (attempt + 1)); continue
        if r.status_code not in ok:
            raise RuntimeError(f"{method} {path} → {r.status_code}: {r.text[:800]}")
        return r.json() if r.text else {}
    raise RuntimeError(f"{method} {path} kept failing")


def all_pages(path, params=None):
    out, url, p = [], path, dict(params or {}, limit=200)
    while url:
        d = call("GET", url, params=p)
        out += d.get("data", [])
        nxt = d.get("links", {}).get("next")
        url, p = (nxt.replace(API, ""), None) if nxt else (None, None)
    return out


def step(msg): print(f"\n== {msg}", flush=True)


# 1. Bundle ID and capabilities
step(f"Bundle ID {BUNDLE_ID}")
found = call("GET", "/v1/bundleIds", params={"filter[identifier]": BUNDLE_ID}).get("data", [])
found = [b for b in found if b["attributes"]["identifier"] == BUNDLE_ID]
if found:
    bundle = found[0]; print("already registered")
else:
    bundle = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID, "name": "Supperwise", "platform": "IOS"}}})["data"]
    print("registered")
caps = {c["attributes"]["capabilityType"] for c in all_pages(f"/v1/bundleIds/{bundle['id']}/bundleIdCapabilities")}
for cap in ["APP_GROUPS"]:
    if cap in caps: print(f"{cap} already on"); continue
    try:
        call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": cap},
             "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}}}})
        print(f"{cap} turned on")
    except RuntimeError as e:
        print(f"couldn't turn on {cap} (not needed yet): {e}")

# 2. The app record
step("App record")
apps = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID}).get("data", [])
if not apps:
    print(f"::error::No app with bundle ID {BUNDLE_ID} yet. Create it once: App Store Connect → Apps → + → New App "
          f"(name Supperwise, bundle ID {BUNDLE_ID}, any SKU), then run this again.")
    sys.exit(1)
app = apps[0]
print(f"found {app['attributes']['name']} ({app['id']})")

# 3. Subscription group and subscriptions
step("Subscription group")
groups = all_pages(f"/v1/apps/{app['id']}/subscriptionGroups")
group = next((g for g in groups if g["attributes"]["referenceName"] == "Supperwise"), None)
if not group:
    group = call("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups", "attributes": {"referenceName": "Supperwise"},
                 "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
    print("created")
else:
    print("already there")
glocs = all_pages(f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")
if not any(l["attributes"]["locale"] == "en-US" for l in glocs):
    call("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
         "attributes": {"name": "Supperwise", "locale": "en-US"},
         "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})
    print("group name set")

existing = {s["attributes"]["productId"]: s for s in all_pages(f"/v1/subscriptionGroups/{group['id']}/subscriptions")}
territories = [t["id"] for t in all_pages("/v1/territories")]
print(f"{len(territories)} territories")

for pid, ref, period, level, usd, display, desc in PLANS:
    step(f"{pid}: {display}, ${usd}")
    sub = existing.get(pid)
    if not sub:
        sub = call("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
            "name": ref, "productId": pid, "subscriptionPeriod": period, "groupLevel": level,
            "familySharable": False, "reviewNote": REVIEW_NOTE},
            "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})["data"]
        print("created")
    else:
        print("already there")
    sid = sub["id"]

    locs = all_pages(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
    if not any(l["attributes"]["locale"] == "en-US" for l in locs):
        call("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
             "attributes": {"name": display, "locale": "en-US", "description": desc},
             "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})
        print("name and description set")

    # Availability everywhere, including new territories.
    try:
        call("POST", "/v1/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities",
             "attributes": {"availableInNewTerritories": True},
             "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                               "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
        print("available in all territories")
    except RuntimeError as e:
        print(f"availability: {e}")

    # Prices: the US price point closest to the target, then Apple's equivalents elsewhere.
    current = all_pages(f"/v1/subscriptions/{sid}/prices", {"include": "territory"})
    if len(current) >= len(territories) - 5:
        print(f"prices already set in {len(current)} territories")
    else:
        points = all_pages(f"/v1/subscriptions/{sid}/pricePoints", {"filter[territory]": "USA"})
        best = min(points, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - float(usd)))
        print(f"US price point {best['attributes']['customerPrice']}")
        eq = all_pages(f"/v1/subscriptionPricePoints/{best['id']}/equalizations", {"include": "territory"})
        priced = 0
        for pp in [best] + eq:
            try:
                call("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
                     "attributes": {"preserveCurrentPrice": False},
                     "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                       "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp["id"]}}}}})
                priced += 1
            except RuntimeError as e:
                if "409" not in str(e): print(f"price: {e}")
        print(f"priced in {priced} territories")

    # A 1-week free trial on yearly plans.
    if period == "ONE_YEAR":
        offers = all_pages(f"/v1/subscriptions/{sid}/introductoryOffers")
        if offers:
            print("trial already set")
        else:
            made = 0
            for t in territories:
                try:
                    call("POST", "/v1/subscriptionIntroductoryOffers", {"data": {"type": "subscriptionIntroductoryOffers",
                         "attributes": {"duration": "ONE_WEEK", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
                         "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                           "territory": {"data": {"type": "territories", "id": t}}}}})
                    made += 1
                except RuntimeError as e:
                    if made == 0: print(f"trial: {e}"); break
            print(f"1-week free trial in {made} territories")

    # Review screenshot (the plans screen).
    try:
        have = call("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
    except RuntimeError:
        have = {}
    if have.get("data"):
        print("review screenshot already attached")
    elif os.path.exists(SCREENSHOT):
        data = open(SCREENSHOT, "rb").read()
        res = call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {"type": "subscriptionAppStoreReviewScreenshots",
                   "attributes": {"fileName": "plans.png", "fileSize": len(data)},
                   "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})["data"]
        for op in res["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            requests.request(op["method"], op["url"], data=chunk, timeout=120,
                             headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])}).raise_for_status()
        call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{res['id']}", {"data": {"type": "subscriptionAppStoreReviewScreenshots",
             "id": res["id"], "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print("review screenshot attached")

step("Done")
print("Subscriptions are set up. They're submitted for review together with the first app version.")
