#!/bin/bash
#  Stage 3: generate the self-signed root CA for the homelab. Run once, on
#  the Ansible control node (Mac). Not idempotent by re-running — it refuses
#  to overwrite an existing CA, because rotating the root means redistributing
#  trust to the VM, the Mac, and (later) the Stage 7 runner. See HANDOFF §3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/../ansible" && pwd)"
PKI_DIR="${ANSIBLE_DIR}/pki"
CA_KEY="${PKI_DIR}/ca.key"
CA_CERT="${PKI_DIR}/ca.pem"
CA_PASS_SCRIPT="${ANSIBLE_DIR}/bin/ca-pass.sh"
CA_SUBJECT="/CN=Forgejo Homelab Root CA"
CA_DAYS=3650

echo "=== 3-1. Preflight ==="

# macOS ships LibreSSL as /usr/bin/openssl; -addext and modern req/x509
# behavior are not guaranteed there. Homebrew's openssl (first on most
# devs' PATH) is the one this script is written against.
OPENSSL_VERSION="$(openssl version)"
case "${OPENSSL_VERSION}" in
  OpenSSL\ 3.*) ;;
  *)
    echo "Refusing to run: 'openssl version' reports '${OPENSSL_VERSION}', not OpenSSL 3.x." >&2
    echo "This is almost certainly macOS's built-in LibreSSL. Put Homebrew's" >&2
    echo "openssl (brew install openssl@3) ahead of it on PATH and retry." >&2
    exit 1
    ;;
esac

if [[ ! -x "${CA_PASS_SCRIPT}" ]]; then
  echo "Missing or non-executable: ${CA_PASS_SCRIPT}" >&2
  echo "Copy bin/ca-pass.sh.example to bin/ca-pass.sh, chmod 700, and store" >&2
  echo "the CA passphrase in Keychain first (see the script's own comments)." >&2
  exit 1
fi

mkdir -p "${PKI_DIR}"

if [[ -f "${CA_KEY}" || -f "${CA_CERT}" ]]; then
  echo "Refusing to overwrite an existing CA:" >&2
  [[ -f "${CA_KEY}"  ]] && echo "  ${CA_KEY} already exists" >&2
  [[ -f "${CA_CERT}" ]] && echo "  ${CA_CERT} already exists" >&2
  echo "Delete both by hand first if a genuine rotation is intended." >&2
  exit 1
fi

echo "=== 3-2. Generate the CA private key (RSA 4096, AES-256 encrypted) ==="
# Passphrase piped straight from Keychain into openssl via -pass stdin —
# never touches disk, an env var, or the process argument list.
"${CA_PASS_SCRIPT}" | openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -aes256 -pass stdin \
  -out "${CA_KEY}"
chmod 600 "${CA_KEY}"

echo "=== 3-3. Self-sign the CA certificate (${CA_DAYS} days) ==="
"${CA_PASS_SCRIPT}" | openssl req -x509 -new \
  -key "${CA_KEY}" -passin stdin \
  -sha256 -days "${CA_DAYS}" \
  -subj "${CA_SUBJECT}" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out "${CA_CERT}"
chmod 644 "${CA_CERT}"

echo
echo "=== Done ==="
openssl x509 -in "${CA_CERT}" -noout -subject -dates
echo
echo "${CA_CERT} is meant to be committed (it is the trust anchor)."
echo "${CA_KEY} is gitignored — verify with: git check-ignore -v ${CA_KEY}"
echo "Next: 01-issue-leaf-cert.sh to issue the git.home.arpa server certificate."
