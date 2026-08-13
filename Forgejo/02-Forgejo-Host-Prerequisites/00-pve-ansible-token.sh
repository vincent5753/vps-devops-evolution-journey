#!/bin/bash
#  Stage 2: read-only PVE token for Ansible. Run as root on the PVE node,
#  once. Separate from the OpenTofu token, which carries VM.Allocate,
#  VM.Clone and VM.PowerMgmt — config management never needs to delete VMs.
set -euo pipefail

USER_ID="AnsibleUser@pve"
TOKEN_NAME="inventory"
ROLE_NAME="AnsibleInventory"

echo "=== 2-1. Create the read-only inventory role ==="
# Not the built-in PVEAuditor, which also grants Datastore/Mapping/Pool/SDN
# audit. Naming exactly what the inventory plugin calls documents it.
pveum role add "${ROLE_NAME}" --privs "" 2>/dev/null || true
pveum role modify "${ROLE_NAME}" -privs "VM.Audit,VM.GuestAgent.Audit,Sys.Audit"

echo "=== 2-2. Create the API user ==="
pveum user add "${USER_ID}" --comment "Ansible dynamic inventory (read-only)" 2>/dev/null || \
  echo "  User already exists, skipping"

echo "=== 2-3. Assign ACLs (scoped paths, never granted at /) ==="
pveum acl modify /vms   -user "${USER_ID}" -role "${ROLE_NAME}"
pveum acl modify /nodes -user "${USER_ID}" -role "${ROLE_NAME}"

echo "=== 2-4. Generate the API token ==="
# privsep=0 is safe here precisely because the user holds nothing but audit
# rights — there is no wider privilege for the token to inherit.
echo ">>> The value below is shown ONLY ONCE, copy it immediately <<<"
pveum user token add "${USER_ID}" "${TOKEN_NAME}" --privsep=0

echo
echo "=== Done ==="
echo "Put it in the Ansible control node's .env (see ansible/.env.example):"
echo "  PROXMOX_TOKEN_SECRET=<the value above>"
echo
echo "inventory/pve.proxmox.yml already expects:"
echo "  user:     ${USER_ID}"
echo "  token_id: ${TOKEN_NAME}"
