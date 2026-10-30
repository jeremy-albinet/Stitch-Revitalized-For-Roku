"""Fail closed on an unpatched Debian CA package or stale Python TLS roots."""

import hashlib
import json
import os
import re
import ssl
import subprocess
from pathlib import Path

MIN_CA_VERSION = "20250419+deb13u1"
# Debian's security source mozilla/{blacklist.txt,certdata.txt} identifies these roots:
# https://tracker.debian.org/news/1813397/accepted-ca-certificates-20250419deb13u1-source-into-stable-security/
EXCLUDED_ROOTS = {
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b": "emSign ECC Root CA - G3",
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4": "AAA Certificate Services",
}


def verify_ca_package() -> str:
    """Use Debian's version ordering and require a fully configured package."""
    result = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}\n${Version}", "ca-certificates"],
        check=True,
        capture_output=True,
        text=True,
    )
    status, version = result.stdout.strip().splitlines()
    if status != "install ok installed":
        raise RuntimeError("ca-certificates is not installed and configured")
    comparison = subprocess.run(
        ["dpkg", "--compare-versions", version, "ge", MIN_CA_VERSION], check=False
    )
    if comparison.returncode != 0:
        raise RuntimeError(f"ca-certificates {version} must be >= {MIN_CA_VERSION}")
    return version


def verify_active_roots() -> int:
    """Inspect the verified default context, including lazily loaded CApath roots."""
    context = ssl.create_default_context()
    if context.verify_mode != ssl.CERT_REQUIRED or not context.check_hostname:
        raise RuntimeError("Python TLS verification and hostname checks must be enabled")

    # get_ca_certs() omits CApath certificates until OpenSSL loads them on demand.
    # Eagerly load hashed anchors into this inspection-only context as well.
    # CPython filters capath to None for directory lists that OpenSSL still uses.
    # An explicitly empty override disables the directory source, without fallback.
    paths = ssl.get_default_verify_paths()
    capath = os.environ.get(paths.openssl_capath_env, paths.openssl_capath)
    if capath:
        for directory in capath.split(os.pathsep):
            # OpenSSL ignores empty list entries; they do not mean the cwd.
            if not directory:
                continue
            for certificate in Path(directory).iterdir():
                if re.fullmatch(r"[0-9a-fA-F]{8}\.\d+", certificate.name):
                    context.load_verify_locations(cafile=str(certificate))

    certificates = context.get_ca_certs(binary_form=True)
    if not certificates:
        raise RuntimeError("Python's active CA trust store is empty")
    for certificate in certificates:
        fingerprint = hashlib.sha256(certificate).hexdigest()
        if fingerprint in EXCLUDED_ROOTS:
            raise RuntimeError(
                f"Distrusted CA is active: {EXCLUDED_ROOTS[fingerprint]} ({fingerprint})"
            )
    return len(certificates)


def check_ca_trust() -> dict[str, str | int | list[str]]:
    """Shared Docker build/CI check; uses only the Python standard library."""
    return {
        "ca_certificates": verify_ca_package(),
        "active_ca_count": verify_active_roots(),
        "excluded_roots": list(EXCLUDED_ROOTS.values()),
    }


if __name__ == "__main__":
    print(json.dumps(check_ca_trust(), sort_keys=True))
