#!/usr/bin/env python3
"""Offline checks for the certificate rule in asc_certs.py: only CI-made, recent certificates are ever marked for revoking."""
import os, sys
from datetime import datetime, timezone
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_certs import classify

NOW = datetime(2026, 11, 19, 12, 0, tzinfo=timezone.utc)
cases = [
    (["Lumen App Store 20261119-061423"], "CI-LEFTOVER"),
    (["Supperwise App Store 20261119-100000", "Lumen App Store 20261119-061423"], "CI-LEFTOVER"),
    ([], "KEEP"),                                                     # no profile: origin unknown
    (["Lumen App Store 20261119-061423", "*[expo] com.x AppStore 2026-11-01"], "KEEP"),   # EAS profile shares it
    (["*[expo] com.x AppStore 2026-11-01"], "KEEP"),
    (["Lumen App Store 20261101-061423"], "KEEP"),                    # CI-named but old
    (["Lumen App Store 2026-11-19"], "KEEP"),                         # name not in the exact CI format
    (["iOS Team Provisioning Profile: com.x"], "KEEP"),
]
bad = 0
for names, want in cases:
    got, why = classify(names, NOW)
    ok = got == want; bad += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {names or '[]'} -> {got} ({why})")
sys.exit(1 if bad else 0)
