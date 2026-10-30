These are public CA certificates, with no private keys. Tests load them into fresh
`ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)` objects; they never change host trust.

Source: `mozilla/certdata.txt` in Debian's
[ca-certificates 20250419+deb13u1 source](https://security.debian.org/debian-security/pool/updates/main/c/ca-certificates/ca-certificates_20250419+deb13u1.tar.xz).
The archive SHA-256 is
`1b2e3d0b90cfc62ac8033d64e18ea4649fbb2a01c937c9ac9d36e762da6b9446`,
as published in the [signed Debian security upload](https://tracker.debian.org/news/1813397/accepted-ca-certificates-20250419deb13u1-source-into-stable-security/).
Certificates are the decoded `CKA_VALUE MULTILINE_OCTAL` DER objects, encoded as PEM.

- `emsign-g3.pem`: label `emSign ECC Root CA - G3`, SHA-256
  `86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b`.
- `comodo-aaa.pem`: label `Comodo AAA Services root`, X.509 CN
  `AAA Certificate Services`, SHA-256
  `d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4`.
- `unaffected-roots.pem`: ISRG Root X1 and emSign C1, C3, G1. These verify that
  ordinary trusted roots and unrelated emSign roots still pass the policy.

Debian keeps the two distrusted certificates in `certdata.txt` but excludes them
from its generated trust store using `mozilla/blacklist.txt`. Their presence in
the source is intentional and allows exact fingerprint regressions.
