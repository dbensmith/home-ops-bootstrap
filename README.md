# home-ops-bootstrap

Infrastructure bootstrapping scripts for Proxmox home lab. Runs on Proxmox hosts to create VM templates before Ansible takes over.

## Quick Start

```bash
# Prerequisites on Proxmox host
apt-get install libguestfs-tools
# Install 1Password CLI from https://1password.com/downloads/command-line/
op signin

# Build Ubuntu Resolute amd64v3 template
./build-ubuntu-resolute-template
```

## Structure

```
home-ops-bootstrap/
├── build-ubuntu-resolute-template    # Entry point. 1Password wrapper.
└── proxmox/
    ├── build-ubuntu-resolute-template.sh    # Builder. Reads env vars, runs qm commands.
    ├── build-ubuntu-resolute-template.env.tpl  # 1Password secret references
    └── sysprep-ubuntu-resolute-template.sh  # Reusable. Cleans Debian/Ubuntu qcow2 images.
```

## Call Chain

```
./build-ubuntu-resolute-template
  │
  ├─ op run --env-file=proxmox/build-ubuntu-resolute-template.env.tpl
  │     Resolves op:// references to env vars (SSHKEY, NS1, NS2, SEARCHDOMAIN, TZ)
  │
  └─ proxmox/build-ubuntu-resolute-template.sh
        │  Validates env vars, downloads image, virt-customize (packages, locale, cloud-init config)
        │
        ├─ proxmox/sysprep-ubuntu-resolute-template.sh <qcow2>
        │     virt-customize cleanup: apt cache, cloud-init reset, machine-ID truncation,
        │     SSH host key regeneration on first boot
        │
        └─ qm create / qm set / qm importdisk / qm resize / qm template
```

## Key Commands

```bash
# Build Ubuntu Resolute amd64v3 template (default VMID: 526040)
./build-ubuntu-resolute-template

# Clean a qcow2 image independently (any Debian/Ubuntu image)
./proxmox/sysprep-ubuntu-resolute-template.sh <image.qcow2> [image2.qcow2 ...]
```

## What It Does

The builder creates a Proxmox VM template with:

| Component | Detail |
|-----------|--------|
| **OS** | Ubuntu Resolute (26.04) server cloud image, amd64v3 |
| **Storage** | Ceph-backed (`ceph` pool) |
| **Boot** | OVMF/UEFI (q35 machine type) |
| **CPU** | host type, 2 cores |
| **RAM** | 4096 MB (balloonable to 1024 MB) |
| **Disk** | 16 GB, SCSI with virtio-scsi-single, writeback cache, discard, iothread, SSD emulation |
| **Network** | virtio on vmbr10, VLAN 100, DHCP via Cloud-Init |
| **Guest Agent** | qemu-guest-agent enabled, fstrim on cloned disks |
| **Packages** | qemu-guest-agent, cloud-utils, cloud-guest-utils |
| **Timezone** | Configurable via `TZ` env var |
| **Locale** | en_CA.UTF-8, US keyboard layout |
| **Cloud-Init** | NoCloud + ConfigDrive datasources |

## 1Password Integration

Secrets stored as `op://` references in `.env.tpl` files. `op run --env-file` resolves them at runtime. Scripts read `$SSHKEY`, `$NS1`, etc. directly — zero `op read` calls in the builder.

Required 1Password secrets:
- `SSHKEY` — SSH public key injected into template
- `NS1`, `NS2` — DNS servers for Cloud-Init
- `SEARCHDOMAIN` — internal network domain
- `TZ` — timezone (optional)

Auth methods:
- **Local:** `op signin` (interactive)
- **Headless/CI:** `OP_SERVICE_ACCOUNT_TOKEN` env var

## sysprep Operations

Offline image cleanup via `virt-customize`:
- `apt-get clean && apt-get autoclean`
- `cloud-init clean --logs`
- Truncate `/etc/machine-id` and `/var/lib/dbus/machine-id`
- Schedule `dpkg-reconfigure openssh-server` on first boot

## Manual Cleanup (after modifying a running clone)

If you boot a clone, modify it, and want to re-template it:
```bash
# Inside the guest
cloud-init clean --logs && fstrim -av && shutdown now

# On the Proxmox host
./proxmox/sysprep-ubuntu-resolute-template.sh <image.qcow2>
```

## Dependencies

### On Proxmox host
- `libguestfs-tools` (provides `virt-customize`)
- `1password-cli` (`op`)

### In template image (installed by `virt-customize`)
- `qemu-guest-agent`
- `cloud-utils`, `cloud-guest-utils`

## Future

```
home-ops-bootstrap/
├── proxmox/          # VM templates
├── pve-host/         # PVE node provisioning (packages, firewall, Ceph init)
├── network/          # VLAN/DNS bootstrap
└── talos/            # Talos Linux cluster bootstrap
```

Pattern per domain: wrapper at root (`build-<thing>`), scripts + `.env.tpl` in domain subdirectory.

## Sources

- https://www.yanboyang.com/clouldinit/
- https://gist.github.com/chriswayg/43fbea910e024cbe608d7dcb12cb8466
- https://cloud-images.ubuntu.com/resolute/
