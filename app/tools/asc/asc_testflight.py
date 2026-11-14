#!/usr/bin/env python3
"""After a build is uploaded: waits for Apple to process it, answers export compliance (the app uses only standard
HTTPS, which is exempt), creates an internal TestFlight group with access to every build, and adds every App Store
Connect user on the team to it, so they get the build in the TestFlight app. Safe to re-run."""
import os, sys, time
sys.argv = sys.argv[:1]
HERE = os.path.dirname(__file__)
src = open(os.path.join(HERE, "asc_setup.py")).read()
exec(src[:src.index("# 1. Bundle ID and capabilities")])

step("App")
app = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]
print(app["attributes"]["name"])

step("Latest build")
build = None
for minute in range(45):
    builds = call("GET", "/v1/builds", params={"filter[app]": app["id"], "sort": "-uploadedDate", "limit": 1}).get("data", [])
    if builds:
        b = builds[0]; state = b["attributes"]["processingState"]
        print(f"build {b['attributes']['version']}: {state}")
        if state == "VALID": build = b; break
        if state in ("FAILED", "INVALID"): print("::error::Apple rejected the build while processing it. Check App Store Connect › TestFlight."); sys.exit(1)
    else:
        print("no build yet")
    time.sleep(60)
if not build: print("::error::The build is still processing after 45 minutes. Run this again later."); sys.exit(1)

if build["attributes"].get("usesNonExemptEncryption") is None:
    call("PATCH", f"/v1/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
    print("export compliance: standard encryption only (exempt)")

step("Internal testers")
groups = all_pages(f"/v1/apps/{app['id']}/betaGroups")
group = next((g for g in groups if g["attributes"]["name"] == "Supperwise team"), None)
if not group:
    group = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {
        "name": "Supperwise team", "isInternalGroup": True, "hasAccessToAllBuilds": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
    print("created the internal group 'Supperwise team'")
have = {t["attributes"].get("email", "").lower() for t in all_pages(f"/v1/betaGroups/{group['id']}/betaTesters")}
for u in all_pages("/v1/users"):
    a = u["attributes"]; email = (a.get("username") or a.get("email") or "").lower()
    if not email or email in have: continue
    try:
        call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {
            "email": email, "firstName": a.get("firstName") or "", "lastName": a.get("lastName") or ""},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
        print(f"added {email} as a tester")
    except RuntimeError as e:
        print(f"couldn't add {email}: {e}")

step("Done")
print("Install the TestFlight app on your iPhone, sign in with your Apple ID, and Supperwise will be there.")
