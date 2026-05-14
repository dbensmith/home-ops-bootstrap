#!/bin/bash
set -euo pipefail

# sysprep for Debian/Ubuntu cloud images.
# Runs virt-customize operations to clean a qcow2 image before converting to
# a Proxmox template or redistributing.
#
# Usage: ./sysprep-ubuntu-resolute-template.sh <image.qcow2> [image2.qcow2 ...]
#
# Operations:
#   1. Clean apt package cache
#   2. Reset cloud-init state
#   3. Truncate machine-IDs (forces regeneration on first boot)
#   4. Schedule SSH host key regeneration on first boot
#
# Prerequisites: apt-get install libguestfs-tools

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <image.qcow2> [image2.qcow2 ...]" >&2
    exit 1
fi

REQUIRED_PKG="libguestfs-tools"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' "$REQUIRED_PKG" 2>/dev/null | grep "install ok installed")
if [ -z "$PKG_OK" ]; then
    echo "Error: $REQUIRED_PKG not installed. Run: apt-get install $REQUIRED_PKG" >&2
    exit 1
fi

for IMG in "$@"; do
    if [ ! -f "$IMG" ]; then
        echo "Error: image not found: $IMG" >&2
        exit 1
    fi

    echo "=== Cleaning $IMG ==="

    echo "  Cleaning apt cache..."
    virt-customize -a "$IMG" \
        --run-command 'apt-get clean && apt-get autoclean'

    echo "  Resetting cloud-init state..."
    virt-customize -a "$IMG" \
        --run-command 'cloud-init clean --logs'

    echo "  Truncating machine-IDs..."
    virt-customize -a "$IMG" \
        --truncate /etc/machine-id \
        --truncate /var/lib/dbus/machine-id

    echo "  Scheduling SSH host key regeneration on first boot..."
    virt-customize -a "$IMG" \
        --firstboot-command 'dpkg-reconfigure openssh-server'

    echo "  Done: $IMG"
    echo ""
done

echo "All images cleaned."
