#!/usr/bin/env python3
"""Creates what's needed to sign Supperwise for the App Store, through Apple's API, on the build machine:
an Apple Distribution certificate (from a key made here) and an App Store provisioning profile for
com.supperwise.app (App Store profiles need no registered devices).

Writes to $OUT_DIR: dist.p12 (password in $P12_PASSWORD), profile.mobileprovision, and profile_name.txt.
Apple allows only a few distribution certificates per team; if the limit is reached, the oldest one is revoked
(apps already on the App Store are not affected by revoking a certificate)."""
import base64, os, subprocess, sys, time
sys.argv = sys.argv[:1]
HERE = os.path.dirname(__file__)
src = open(os.path.join(HERE, "asc_setup.py")).read()
exec(src[:src.index("# 1. Bundle ID and capabilities")])
OUT = os.environ["OUT_DIR"]; PW = os.environ["P12_PASSWORD"]
os.makedirs(OUT, exist_ok=True)

from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12

step("Distribution certificate")
# The key and request are made here, in Python (the same on every machine); the private key never leaves this run.
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, "Supperwise CI"), x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Supperwise"),
    x509.NameAttribute(NameOID.COUNTRY_NAME, "US")])).sign(key, hashes.SHA256()).public_bytes(serialization.Encoding.PEM).decode()
cert = None
for attempt in range(2):
    try:
        cert = call("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr}}})["data"]
        break
    except RuntimeError as e:
        msg = str(e)
        if "403" in msg or "FORBIDDEN" in msg:
            print("::error::This API key can't create certificates. Make a Team Key with **Admin** access in App Store Connect "
                  "(Users and Access → Integrations → App Store Connect API) and put its Key ID and .p8 in the ASC_KEY_ID / ASC_KEY_P8 secrets.")
            sys.exit(1)
        if attempt == 0 and ("maximum" in msg.lower() or "limit" in msg.lower() or "already" in msg.lower()):
            existing = [c for c in all_pages("/v1/certificates", {"filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION"})]
            existing.sort(key=lambda c: c["attributes"].get("expirationDate") or "")
            if existing:
                old = existing[0]
                call("DELETE", f"/v1/certificates/{old['id']}")
                print(f"revoked the oldest distribution certificate ({old['attributes'].get('name')}, expiring {old['attributes'].get('expirationDate')}) to make room")
                continue
        raise
certificate = x509.load_der_x509_certificate(base64.b64decode(cert["attributes"]["certificateContent"]))
# The older PKCS#12 encryption, which the macOS keychain imports reliably.
enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
       .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1()).build(PW.encode()))
open(os.path.join(OUT, "dist.p12"), "wb").write(pkcs12.serialize_key_and_certificates(b"Supperwise Distribution", key, certificate, None, enc))
print(f"created {cert['attributes'].get('name')} (expires {cert['attributes'].get('expirationDate')})")

step("App Store provisioning profile")
bundle = [b for b in call("GET", "/v1/bundleIds", params={"filter[identifier]": BUNDLE_ID})["data"] if b["attributes"]["identifier"] == BUNDLE_ID][0]
name = f"Supperwise App Store {time.strftime('%Y%m%d-%H%M%S')}"
profile = call("POST", "/v1/profiles", {"data": {"type": "profiles", "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
               "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                                 "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
open(os.path.join(OUT, "profile.mobileprovision"), "wb").write(base64.b64decode(profile["attributes"]["profileContent"]))
open(os.path.join(OUT, "profile_name.txt"), "w").write(name)
print(f"created profile '{name}'")
