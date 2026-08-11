#!/bin/bash
# ============================================================
#  Stage 0: PVE host prerequisites
#  Run as root on the PVE node. Only needs to be run once.
# ============================================================
set -euo pipefail

USER_ID="OpenTofuUser@pve"
TOKEN_NAME="provider"
TEMPLATE_VMID=9000
TEMPLATE_NAME="ubuntu-2404-cloud-init-template"
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG_PATH="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"
SNIPPET="/var/lib/vz/snippets/ubuntu-cloud_init-basic-harden.yaml"

echo "=== 0-1. Create the OpenTofu role ==="
# This assumes the 'local' storage already has the 'snippets' content type
# enabled and that 'local-lvm' is lvmthin, which is the PVE default.
# If yours differs, enable it first with: pvesm set local --content snippets,...
pveum role add OpenTofu --privs "" 2>/dev/null || true
pveum role modify OpenTofu -append -privs "\
VM.Allocate,VM.Audit,VM.Clone,\
VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,\
VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,\
VM.Config.Network,VM.Config.Options,\
VM.PowerMgmt,VM.GuestAgent.Audit,\
Datastore.Audit,Datastore.AllocateSpace,Datastore.AllocateTemplate,\
SDN.Use,Sys.Audit"

echo "=== 0-2. Create the API user ==="
pveum user add "${USER_ID}" --comment "OpenTofu Automation Account" 2>/dev/null || \
  echo "  User already exists, skipping"

echo "=== 0-3. Assign ACLs (scoped paths, never granted at /) ==="
pveum acl modify /vms               -user "${USER_ID}" -role OpenTofu
pveum acl modify /storage/local     -user "${USER_ID}" -role OpenTofu
pveum acl modify /storage/local-lvm -user "${USER_ID}" -role OpenTofu
pveum acl modify /nodes             -user "${USER_ID}" -role OpenTofu
pveum acl modify /sdn               -user "${USER_ID}" -role OpenTofu

echo "=== 0-4. Place the cloud-init snippet ==="
mkdir -p /var/lib/vz/snippets
if [[ ! -f "${SNIPPET}" ]]; then
  echo "  !! Copy ubuntu-cloud_init-basic-harden.yaml to ${SNIPPET} first"
  echo "  !! and remember to replace the SSH public keys inside it with your own"
  exit 1
fi
chmod 644 "${SNIPPET}"
chown root:root "${SNIPPET}"

echo "=== 0-5. Download the Ubuntu cloud image ==="
# Note: this is the .img cloud image, NOT the Server installer ISO
[[ -f "${IMG_PATH}" ]] || wget -O "${IMG_PATH}" "${IMG_URL}"

echo "=== 0-6. Build the template VM ==="
if qm status "${TEMPLATE_VMID}" &>/dev/null; then
  echo "  VMID ${TEMPLATE_VMID} already exists, skipping creation"
else
  qm create "${TEMPLATE_VMID}" \
    --name "${TEMPLATE_NAME}" \
    --memory 2048 \
    --cores 2 \
    --cpu host \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-single \
    --ostype l26 \
    --agent enabled=1

  # Import the cloud image as scsi0 (PVE 7.3+ syntax)
  qm disk import "${TEMPLATE_VMID}" "${IMG_PATH}" local-lvm
  qm set "${TEMPLATE_VMID}" --scsi0 "local-lvm:vm-${TEMPLATE_VMID}-disk-0"

  # cloud-init drive + boot order + serial console (required by cloud images)
  qm set "${TEMPLATE_VMID}" --ide2 local-lvm:cloudinit
  qm set "${TEMPLATE_VMID}" --boot order=scsi0
  qm set "${TEMPLATE_VMID}" --serial0 socket --vga serial0

  # Convert it into a template
  qm template "${TEMPLATE_VMID}"
fi

echo "=== 0-7. Generate the API token ==="
echo ">>> The value below is shown ONLY ONCE, copy it immediately <<<"
pveum user token add "${USER_ID}" "${TOKEN_NAME}" --privsep=0

echo
echo "=== Done ==="
echo "Full token ID format: ${USER_ID}!${TOKEN_NAME}"
echo "In terraform.tfvars, write it as: ${USER_ID}!${TOKEN_NAME}=<the value above>"
