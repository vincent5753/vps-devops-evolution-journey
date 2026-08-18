#!/bin/bash
#  Stage 3: trust the homelab CA on this Mac. NOT run automatically by
#  anything — importing a root CA into a personal trust store is a security
#  decision the user makes deliberately, not something automation does on
#  their behalf. Run this yourself after reviewing what it does.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT="$(cd "${SCRIPT_DIR}/../ansible/pki" && pwd)/ca.pem"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if [[ ! -f "${CA_CERT}" ]]; then
  echo "Missing ${CA_CERT} — run 00-generate-ca.sh first." >&2
  exit 1
fi

echo "About to add this certificate as a trusted root to your login keychain:"
echo
openssl x509 -in "${CA_CERT}" -noout -subject -issuer -dates
echo
read -r -p "Proceed? [y/N] " REPLY
if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# -d adds it as trusted for all policies (SSL, X.509 basic, etc).
# -r trustRoot marks it as a root anchor, not a leaf override.
security add-trusted-cert -d -r trustRoot -k "${KEYCHAIN}" "${CA_CERT}"

echo
echo "=== Done ==="
echo "Verify with: security find-certificate -c \"Forgejo Homelab Root CA\" -p \"${KEYCHAIN}\""
echo
echo "This covers Safari/Chrome (Keychain-backed trust) and any git built"
echo "against Secure Transport. It does NOT by itself make git respect this"
echo "CA if your git uses OpenSSL instead — verify with an actual clone once"
echo "nginx is serving TLS (Stage 3 work line 2), and fall back to"
echo "'git config http.sslCAInfo ${CA_CERT}' scoped to this remote if needed."
