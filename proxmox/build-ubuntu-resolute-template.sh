#!/bin/bash
set -e

# Proxmox Ubuntu Resolute template builder.
# Run on Proxmox host. Designed for Ceph-backed storage.
#
# Secrets are expected as environment variables (SSHKEY, NS1, NS2, SEARCHDOMAIN, TZ).
# Use ../build-ubuntu-resolute-template wrapper to inject via 1Password.
#
# Prerequisites: apt-get install libguestfs-tools
#
# Sources:
#   https://www.yanboyang.com/clouldinit/
#   https://gist.github.com/chriswayg/43fbea910e024cbe608d7dcb12cb8466

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Prerequisite Checks ---
REQUIRED_PKG="libguestfs-tools"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2>/dev/null | grep "install ok installed")
echo "Checking for $REQUIRED_PKG: ${PKG_OK:-NOT INSTALLED}"
if [ -z "$PKG_OK" ]; then
  echo "Error: $REQUIRED_PKG not installed. Run: apt-get install $REQUIRED_PKG"
  exit 1
fi

# --- Image Variables ---
SRC_VER="resolute"
SRC_URL="https://cloud-images.ubuntu.com/${SRC_VER}/current/${SRC_VER}-server-cloudimg-amd64v3.img"
SRC_IMG=${SRC_URL##*/}
IMG_NAME="${SRC_IMG/.img/.qcow2}"
WORK_DIR="/tmp"
DELETEIMG="yes" # Set to "no" to keep image and qcow2 files (useful in Dev)

# --- VM Configuration Defaults ---
OSNAME="Ubuntu 26.04"
TEMPL_NAME_DEFAULT="ubuntu-26.04-server-cloudimg-$(date +%Y%m%d)"
VMID_DEFAULT="526040"
# Cloud-Init credentials — fetched from 1Password, updated on change
OP_CREDS="op://Automation/zimfxfdnvyaecrwx3rnvk25azi"
CLOUD_USER_OP=$(op read "${OP_CREDS}/username" 2>/dev/null || echo "")
CLOUD_PASSWORD_OP=$(op read "${OP_CREDS}/password" 2>/dev/null || echo "")
CLOUD_USER_DEFAULT=${CLOUD_USER_OP:-"root"}
MEM="4096"
BALLOON="1024"
DISK_SIZE="16G"
DISK_STOR="ceph"
NET_BRIDGE="vmbr10"
VLAN="100"              # VLAN tag; set to "" if no VLAN required
CORES="2"
OS_TYPE="l26"
AGENT_ENABLE="1"        # 0 = disable QEMU guest agent
FSTRIM="1"              # 0 = disable fstrim on cloned disks
BIOS="ovmf"             # "ovmf" (UEFI) or "seabios"
MACHINE="q35"
VIRTPKG="qemu-guest-agent,cloud-utils,cloud-guest-utils"
SETX11="yes"            # "yes" = configure keyboard/locale, "no" = skip
X11LAYOUT="us"
X11MODEL="pc105"
LOCALLANG="en_CA.UTF-8"

# --- Environment-Dependent Variables ---
# Read from environment. TZ is optional (skip timezone config if empty).
# SSHKEY, NS1, NS2, SEARCHDOMAIN are required.

if [ -z "${SSHKEY:-}" ]; then
  echo "Error: SSHKEY environment variable is required." >&2
  exit 1
fi

# Compose nameserver list from individual NS env vars
# (qm --nameserver accepts space-separated IPs)
NAMESERVER="${NS1:-} ${NS2:-}"
NAMESERVER="${NAMESERVER#"${NAMESERVER%%[![:space:]]*}"}" # trim leading whitespace
NAMESERVER="${NAMESERVER%"${NAMESERVER##*[![:space:]]}"}" # trim trailing whitespace

if [ -z "$NAMESERVER" ]; then
  echo "Error: NS1 and/or NS2 environment variable must be set." >&2
  exit 1
fi

if [ -z "${SEARCHDOMAIN:-}" ]; then
  echo "Error: SEARCHDOMAIN environment variable is required." >&2
  exit 1
fi

# --- Interactive Prompts (press Enter to accept defaults) ---
read -p "Enter a VM Template Name [$TEMPL_NAME_DEFAULT]: " TEMPL_NAME
TEMPL_NAME=${TEMPL_NAME:-$TEMPL_NAME_DEFAULT}

read -p "Enter a VM ID for $OSNAME [$VMID_DEFAULT]: " VMID
VMID=${VMID:-$VMID_DEFAULT}

read -p "Enter a Cloud-Init Username for $OSNAME [$CLOUD_USER_DEFAULT]: " CLOUD_USER
CLOUD_USER=${CLOUD_USER:-$CLOUD_USER_DEFAULT}

CLOUD_PASSWORD_DEFAULT=${CLOUD_PASSWORD_OP:-$(date +%s | sha256sum | base64 | head -c 16 ; echo)}
read -p "Enter a Cloud-Init Password for $OSNAME [$CLOUD_PASSWORD_DEFAULT]: " CLOUD_PASSWORD
CLOUD_PASSWORD=${CLOUD_PASSWORD:-$CLOUD_PASSWORD_DEFAULT}

# Helper: 1Password Connect Server is read-only for item writes.
# Only attempt credential updates when using op signin or service account.
_op_backend_writable() {
    [[ -z "${OP_CONNECT_TOKEN:-}${OP_CONNECT_HOST:-}${OP_CONNECT_TOKEN_ENV:-}${OP_CONNECT_HOST_ENV:-}" ]]
}

# Update 1Password if user changed values
if [ -n "$CLOUD_USER_OP" ] && [ "$CLOUD_USER" != "$CLOUD_USER_OP" ]; then
    if _op_backend_writable; then
        echo "Updating cloud-init username in 1Password..."
        op item edit zimfxfdnvyaecrwx3rnvk25azi "username=$CLOUD_USER" --vault Automation || \
            echo "Warning: Failed to update 1Password username. Check service account permissions." >&2
    else
        echo "Skipping 1Password username update (Connect Server is read-only; use 'op signin' to update)." >&2
    fi
fi
if [ -n "$CLOUD_PASSWORD_OP" ] && [ "$CLOUD_PASSWORD" != "$CLOUD_PASSWORD_OP" ]; then
    if _op_backend_writable; then
        echo "Updating cloud-init password in 1Password..."
        op item edit zimfxfdnvyaecrwx3rnvk25azi "password=$CLOUD_PASSWORD" --vault Automation || \
            echo "Warning: Failed to update 1Password password. Check service account permissions." >&2
    else
        echo "Skipping 1Password password update (Connect Server is read-only; use 'op signin' to update)." >&2
    fi
fi

echo ""
echo "=== Starting template build for: $TEMPL_NAME (VMID: $VMID) ==="

# --- Download and Prepare Image ---
echo "[1/7] Downloading $OSNAME cloud image..."
cd "$WORK_DIR"
wget -N -q --show-progress "$SRC_URL"

echo "       Converting image to qcow2..."
cp "$SRC_IMG" "$IMG_NAME"

# Resize before customizing — apt-get upgrade needs room.
# Cloud images ship with ~2GB root partition; upgrade + install can fill it.
echo "       Resizing image to $DISK_SIZE..."
qemu-img resize "$IMG_NAME" "$DISK_SIZE"

# --- virt-customize: Customize Image In-Place ---
echo "[2/7] Customizing image with virt-customize..."

# Grow root partition to fill the expanded disk (must run before --update).
# Uses sfdisk (util-linux, always available) — growpart needs cloud-guest-utils
# which isn't installed yet.
# Ubuntu cloud images use either /dev/vda1 or /dev/sda1.
VC_GROW_ARG=""
VC_GROW_ARG+="--run-command '"
VC_GROW_ARG+="  for dev in vda sda; do"
VC_GROW_ARG+="    [ -b /dev/\$dev ] || continue;"
VC_GROW_ARG+="    echo \", +\" | sfdisk -N 1 --no-reread /dev/\$dev 2>/dev/null && break;"
VC_GROW_ARG+="  done;"
VC_GROW_ARG+="  partprobe /dev/vda 2>/dev/null || partprobe /dev/sda 2>/dev/null || true;"
VC_GROW_ARG+="  resize2fs /dev/vda1 2>/dev/null || resize2fs /dev/sda1 2>/dev/null || true"
VC_GROW_ARG+="' "

if [ -n "${TZ:-}" ]; then
  echo "       Setting timezone to $TZ..."
  eval "virt-customize -a \"$IMG_NAME\" $VC_GROW_ARG --timezone \"$TZ\""
else
  eval "virt-customize -a \"$IMG_NAME\" $VC_GROW_ARG"
fi

if [ "$SETX11" = "yes" ]; then
  echo "       Setting keyboard layout ($X11LAYOUT/$X11MODEL) and locale ($LOCALLANG)..."
  virt-customize -a "$IMG_NAME" \
    --firstboot-command "localectl set-locale LANG=$LOCALLANG" \
    --firstboot-command "localectl set-x11-keymap $X11LAYOUT $X11MODEL"
fi

echo "       Updating packages and installing: $VIRTPKG (this may take a while)..."
virt-customize -a "$IMG_NAME" --update --install "$VIRTPKG"

echo "       Uploading Proxmox Cloud-init datasource config..."
cat > "$WORK_DIR/99_pve.cfg" << 'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive ]
EOF
virt-customize -a "$IMG_NAME" --upload "$WORK_DIR/99_pve.cfg:/etc/cloud/cloud.cfg.d/"

echo "       Running template hygiene..."
"$__dir/sysprep-ubuntu-resolute-template.sh" "$WORK_DIR/$IMG_NAME"

echo "       Image customization complete."

# --- VM Notes ---
mapfile -d '' NOTES << 'EOF'
## Template hygiene (automated during creation)
The creation script automatically cleans the image via sysprep-ubuntu-resolute-template.sh:
- apt cache cleanup
- cloud-init state reset
- machine-ID truncation
- SSH host key regeneration scheduled for first boot

To clean a qcow2 image independently:
  ./proxmox/sysprep-ubuntu-resolute-template.sh <image.qcow2>

## Manual cleanup (after modifying a running clone)
If you boot a clone, modify it, and want to re-template it, clean up inside the guest:
```cloud-init clean --logs && fstrim -av && shutdown now```
Then run virt-sysprep on the PVE host (see below).

## virt-sysprep
For offline image cleanup, sysprep-ubuntu-resolute-template.sh is preferred.
virt-sysprep is a heavier alternative.

### LVM
```virt-sysprep --colours -a /dev/pve/vm-######-disk-# --network --update --operations defaults --firstboot-command 'dpkg-reconfigure openssh-server'```

### Ceph
```virt-sysprep --colours -a rbd://localhost:3300/ceph/vm-######-disk-1 --network --update --operations defaults --firstboot-command 'dpkg-reconfigure openssh-server'```

As of 2024-08-23 I couldn't get virt-sysprep to load an image from Ceph, so I moved the disk onto local-lvm, ran virt-sysprep, and then moved it back onto Ceph.

## Sources
* https://manpages.ubuntu.com/manpages/jammy/man1/virt-sysprep.1.html
* https://libguestfs.org/virt-sysprep.1.html
* https://libguestfs.org/guestfish.1.html#adding-remote-storage
EOF

# --- Destroy Existing VM (if any) ---
echo "[3/7] Checking for existing VM $VMID..."
if qm status "$VMID" &>/dev/null; then
  echo "       Destroying existing VM $VMID..."
  qm stop "$VMID" &>/dev/null || true
  qm destroy "$VMID" --purge
else
  echo "       No existing VM $VMID found."
fi

# --- Create VM ---
echo "[4/7] Creating VM $VMID ($TEMPL_NAME)..."

qm create "$VMID" \
  --name "$TEMPL_NAME" \
  --memory "$MEM" \
  --balloon "$BALLOON" \
  --cores "$CORES" \
  --bios "$BIOS" \
  --machine "$MACHINE" \
  --cpu host \
  --net0 "virtio,mtu=1,bridge=${NET_BRIDGE}${VLAN:+,tag=$VLAN}"

qm set "$VMID" --ostype "$OS_TYPE"
qm set "$VMID" --agent "enabled=${AGENT_ENABLE},fstrim_cloned_disks=${FSTRIM}"

# Configure network and DNS via Cloud-Init
qm set "$VMID" --ipconfig0 ip=dhcp
qm set "$VMID" --nameserver "$NAMESERVER" --searchdomain "$SEARCHDOMAIN"

# Import disk from local qcow2 into Ceph storage
echo "[5/7] Importing disk to Ceph storage..."
qm importdisk "$VMID" "$WORK_DIR/$IMG_NAME" "$DISK_STOR" -format qcow2

# Attach imported disk as scsi0
# Ceph pool: no VMID folder prefix, no file extension in disk path
qm set "$VMID" --scsihw virtio-scsi-single
qm set "$VMID" --scsi0 "${DISK_STOR}:vm-${VMID}-disk-0,cache=writeback,discard=on,iothread=1,ssd=1"

# Cloud-Init drive
qm set "$VMID" --scsi1 "${DISK_STOR}:cloudinit"

# EFI disk (required for OVMF/UEFI boot)
qm set "$VMID" --efidisk0 "${DISK_STOR}:0,efitype=4m,format=qcow2,pre-enrolled-keys=1,size=4M"

# RNG device (prevents entropy starvation in guest)
qm set "$VMID" --rng0 source=/dev/urandom

# Cloud-Init credentials
qm set "$VMID" --ciuser "$CLOUD_USER"
qm set "$VMID" --cipassword "$CLOUD_PASSWORD"

# Boot order
qm set "$VMID" --boot c --bootdisk scsi0

# Notes / description
qm set "$VMID" --description "$NOTES"

# Inject SSH public key
echo "[6/7] Injecting SSH key..."
tmpfile=$(mktemp /tmp/sshkey.XXX.pub)
echo "$SSHKEY" > "$tmpfile"
qm set "$VMID" --sshkeys "$tmpfile"
rm -f "$tmpfile"

# Resize disk to target size
echo "       Resizing scsi0 to $DISK_SIZE..."
qm resize "$VMID" scsi0 "$DISK_SIZE"

# --- Convert to Template ---
echo "[7/7] Converting VM $VMID to template..."
qm template "$VMID"

# --- Cleanup ---
echo "Cleaning up temporary files..."
if [ "$DELETEIMG" = "yes" ]; then
  rm -fv "$WORK_DIR/$IMG_NAME"
  rm -fv "$WORK_DIR/$SRC_IMG"
  rm -fv "$WORK_DIR/99_pve.cfg"
else
  echo "       DELETEIMG=no: keeping image files in $WORK_DIR"
fi

echo ""
echo "=== Template $TEMPL_NAME (VMID: $VMID) is ready. ==="
echo "Clone with: qm clone $VMID <new-vmid> --name <new-vm-name> --full"
