#!/usr/bin/env python3
"""Invites someone to test Supperwise in TestFlight as an internal tester.
Step 1 (now): an App Store Connect invitation with the Developer role, limited to the Supperwise app only
(no sales, banking or other apps). Step 2 (after they accept): asc_testflight.py adds every team member to
the "Supperwise team" TestFlight group. Usage: INVITE_EMAIL=someone@example.com asc_invite.py"""
import os, sys
sys.argv = sys.argv[:1]
HERE = os.path.dirname(__file__)
src = open(os.path.join(HERE, "asc_setup.py")).read()
exec(src[:src.index("# 1. Bundle ID and capabilities")])
email = os.environ["INVITE_EMAIL"].strip().lower()
first = os.environ.get("INVITE_FIRST", "").strip() or "Supperwise"
last = os.environ.get("INVITE_LAST", "").strip() or "Tester"

step(f"Invite {email}")
app = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]
users = {(u["attributes"].get("username") or "").lower() for u in all_pages("/v1/users")}
if email in users:
    print("already on the team: run the 'testflight' step to add them to the TestFlight group")
    sys.exit(0)
pending = {(i["attributes"].get("email") or "").lower() for i in all_pages("/v1/userInvitations")}
if email in pending:
    print("an invitation is already waiting for them to accept (check their inbox and spam)")
    sys.exit(0)
call("POST", "/v1/userInvitations", {"data": {"type": "userInvitations", "attributes": {
    "email": email, "firstName": first, "lastName": last, "roles": ["DEVELOPER"],
    "allAppsVisible": False, "provisioningAllowed": False},
    "relationships": {"visibleApps": {"data": [{"type": "apps", "id": app["id"]}]}}}})
print("invitation sent: Developer role, Supperwise only. After they accept it, run the 'testflight' step.")
