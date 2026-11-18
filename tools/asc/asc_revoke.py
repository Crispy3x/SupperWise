#!/usr/bin/env python3
"""Revokes the distribution certificate this CI run created (its id is in $OUT_DIR/cert_id.txt), so the team's
small certificate limit is never used up by CI runs. Builds already uploaded to App Store Connect stay valid.
It only ever touches the certificate this run made; certificates made elsewhere (for example by EAS) are left alone."""
import os, sys
sys.argv = sys.argv[:1]
HERE = os.path.dirname(__file__)
src = open(os.path.join(HERE, "asc_setup.py")).read()
exec(src[:src.index("# 1. Bundle ID and capabilities")])
path = os.path.join(os.environ["OUT_DIR"], "cert_id.txt")
if not os.path.exists(path):
    print("no certificate was created in this run")
    sys.exit(0)
cid = open(path).read().strip()
call("DELETE", f"/v1/certificates/{cid}")
print(f"revoked this run's distribution certificate ({cid})")
