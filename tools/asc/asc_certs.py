#!/usr/bin/env python3
"""Lists the team's distribution certificates and, only when asked, revokes the ones THESE GitHub workflows made.

  python3 tools/asc/asc_certs.py            list only (changes nothing)
  python3 tools/asc/asc_certs.py --revoke   list, then revoke the certificates marked CI-LEFTOVER

A certificate is CI-LEFTOVER only when every provisioning profile that uses it is named like this repo's and Lumen's
CI profiles ("Supperwise App Store 20261119-061423" or "Lumen App Store 20261119-061423") and the newest of those
names is recent (--within-hours, default 36). Anything else is KEEP: a certificate with no profile, a profile with
another name (EAS names its own), or an older one. Those are never touched, because EAS or a manual Xcode setup may
depend on them. Builds already uploaded to App Store Connect do not depend on the certificate that signed them."""
import argparse, os, re, sys
from datetime import datetime, timedelta, timezone

CI_PROFILE = re.compile(r"^(Supperwise|Lumen) App Store (\d{8})-(\d{6})$")


def profile_time(name):
    m = CI_PROFILE.match(name or "")
    if not m:
        return None
    return datetime.strptime(m.group(2) + m.group(3), "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)


def classify(profile_names, now, within_hours=36):
    """Returns (verdict, reason) for one certificate given the names of the profiles that use it."""
    if not profile_names:
        return "KEEP", "no profile uses it, so its origin can't be told"
    times = [profile_time(n) for n in profile_names]
    other = [n for n, t in zip(profile_names, times) if t is None]
    if other:
        return "KEEP", f"used by a profile this CI did not create ({other[0]})"
    newest = max(times)
    if now - newest > timedelta(hours=within_hours):
        return "KEEP", f"CI profiles only, but the newest is older than {within_hours} hours"
    return "CI-LEFTOVER", f"only CI profiles use it, newest made {newest:%Y-%m-%d %H:%M} UTC"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--revoke", action="store_true")
    ap.add_argument("--within-hours", type=int, default=36)
    args = ap.parse_args()
    sys.argv = sys.argv[:1]
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "asc_setup.py")).read()
    ns = {"__name__": "asc_header"}
    exec(src[:src.index("# 1. Bundle ID and capabilities")], ns)
    call, all_pages = ns["call"], ns["all_pages"]

    certs = all_pages("/v1/certificates", {"filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION"})
    by_cert = {c["id"]: [] for c in certs}
    # Profiles say which certificates they use. Ask for them with their relationships.
    url, params = "/v1/profiles", {"include": "certificates", "limit": 200, "fields[profiles]": "name,profileState,profileType,certificates"}
    while url:
        d = call("GET", url, params=params)
        for p in d.get("data", []):
            for ref in (p.get("relationships", {}).get("certificates", {}) or {}).get("data", []) or []:
                if ref["id"] in by_cert:
                    by_cert[ref["id"]].append(p["attributes"].get("name") or "")
        nxt = d.get("links", {}).get("next")
        url, params = (nxt.replace(ns["API"], ""), None) if nxt else (None, None)

    now = datetime.now(timezone.utc)
    print(f"{len(certs)} distribution certificate(s) on the team. Now: {now:%Y-%m-%d %H:%M} UTC\n")
    to_revoke = []
    for c in sorted(certs, key=lambda c: c["attributes"].get("expirationDate") or ""):
        a = c["attributes"]
        verdict, why = classify(by_cert[c["id"]], now, args.within_hours)
        print(f"- {c['id']}  {a.get('certificateType')}  \"{a.get('name')}\"  expires {a.get('expirationDate')}")
        for n in by_cert[c["id"]] or ["(none)"]:
            print(f"    profile: {n}")
        print(f"    {verdict}: {why}")
        if verdict == "CI-LEFTOVER":
            to_revoke.append(c)
    print(f"\n{len(to_revoke)} CI-LEFTOVER certificate(s).")
    if not args.revoke:
        print("List only. Nothing was changed.")
        return
    for c in to_revoke:
        call("DELETE", f"/v1/certificates/{c['id']}")
        print(f"revoked {c['id']}")
    print("Done.")


if __name__ == "__main__":
    main()
