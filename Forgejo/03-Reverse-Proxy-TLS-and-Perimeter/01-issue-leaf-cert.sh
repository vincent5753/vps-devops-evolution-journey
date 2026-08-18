#!/bin/bash
#  Stage 3: issue (or renew) the git.home.arpa server certificate, signed by
#  the CA from 00-generate-ca.sh. Safe to re-run — this is the 90-day-cycle
#  script, unlike the CA generator, which refuses to overwrite. Run on the
#  Ansible control node (Mac); Ansible pushes the output to the VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/../ansible" && pwd)"
PKI_DIR="${ANSIBLE_DIR}/pki"
LEAF_DIR="${PKI_DIR}/leaf"
CA_KEY="${PKI_DIR}/ca.key"
CA_CERT="${PKI_DIR}/ca.pem"
CA_PASS_SCRIPT="${ANSIBLE_DIR}/bin/ca-pass.sh"

# Mirrors group_vars/forgejo/main.yml: forgejo_domain. Only one SAN — every
# client resolves this name via /etc/hosts, so an IP SAN buys nothing.
DOMAIN="git.home.arpa"
LEAF_KEY="${LEAF_DIR}/${DOMAIN}.key"
LEAF_CERT="${LEAF_DIR}/${DOMAIN}.pem"
LEAF_DAYS=90

echo "=== 3-1. Preflight ==="

OPENSSL_VERSION="$(openssl version)"
case "${OPENSSL_VERSION}" in
  OpenSSL\ 3.*) ;;
  *)
    echo "Refusing to run: 'openssl version' reports '${OPENSSL_VERSION}', not OpenSSL 3.x." >&2
    exit 1
    ;;
esac

for f in "${CA_KEY}" "${CA_CERT}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing ${f} — run 00-generate-ca.sh first." >&2
    exit 1
  fi
done

if [[ ! -x "${CA_PASS_SCRIPT}" ]]; then
  echo "Missing or non-executable: ${CA_PASS_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${LEAF_DIR}"

if [[ -f "${LEAF_CERT}" ]]; then
  echo "Existing leaf certificate found, expiry:"
  openssl x509 -in "${LEAF_CERT}" -noout -enddate
  echo "Proceeding to issue a fresh one (this overwrites it)."
fi

CSR_FILE="$(mktemp)"
trap 'rm -f "${CSR_FILE}"' EXIT

echo "=== 3-2. Generate the leaf private key (RSA 2048, unencrypted) ==="
# Unlike the CA key, this one is NOT passphrase-protected: nginx has to read
# it unattended at every boot, and it rotates every 90 days anyway, so the
# blast radius and lifetime are both far smaller. Protected by file mode only.
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out "${LEAF_KEY}"
chmod 600 "${LEAF_KEY}"

echo "=== 3-3. Generate the CSR ==="
openssl req -new \
  -key "${LEAF_KEY}" \
  -subj "/CN=${DOMAIN}" \
  -out "${CSR_FILE}"

echo "=== 3-4. Sign with the CA (${LEAF_DAYS} days) ==="
# Extensions are listed explicitly rather than copied from the CSR
# (-copy_extensions) — the CSR is not a trusted input.
"${CA_PASS_SCRIPT}" | openssl x509 -req \
  -in "${CSR_FILE}" \
  -CA "${CA_CERT}" -CAkey "${CA_KEY}" -passin stdin \
  -CAcreateserial \
  -days "${LEAF_DAYS}" \
  -extfile <(printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' "${DOMAIN}") \
  -out "${LEAF_CERT}"
chmod 644 "${LEAF_CERT}"

echo "=== 3-5. Verify the chain ==="
openssl verify -CAfile "${CA_CERT}" "${LEAF_CERT}"

echo
echo "=== Done ==="
openssl x509 -in "${LEAF_CERT}" -noout -subject -dates -ext subjectAltName
echo
echo "${LEAF_DIR} is gitignored in full — nothing here should be committed."
echo "Next: run the Ansible playbook to push this to the VM (roles/host_tls)."
