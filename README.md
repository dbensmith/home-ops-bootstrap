# home-ops-bootstrap

Infrastructure bootstrapping scripts for Proxmox home lab. Creates VM templates on Proxmox hosts before Ansible takes over.

## Quick Start

**Run these commands on your Proxmox host** (SSH into it):

```bash
# 1. Install prerequisites
apt-get install libguestfs-tools
# Install 1Password CLI: https://1password.com/downloads/command-line/

# 2. Authenticate 1Password
op signin
# OR export OP_SERVICE_ACCOUNT_TOKEN=...  (headless/CI)

# 3. Build template (downloads latest from GitHub, no clone needed)
bash <(curl -fsSL https://raw.githubusercontent.com/dbensmith/home-ops-bootstrap/main/build-ubuntu-resolute-template)
```

That's it. The script auto-detects it's running remotely, downloads the builder scripts from GitHub into a temp directory, resolves secrets via 1Password, and builds the template.

## What This Repo Does

This repo contains three scripts that work together:

| File | Role | Run where |
|------|------|-----------|
| `build-ubuntu-resolute-template` | Entry point — checks prerequisites, resolves 1Password secrets, launches builder | Proxmox host |
| `proxmox/build-ubuntu-resolute-template.sh` | Builder — downloads Ubuntu cloud image, customizes it, creates Proxmox VM template | Proxmox host (called by wrapper) |
| `proxmox/sysprep-ubuntu-resolute-template.sh` | Utility — cleans a qcow2 image (apt cache, cloud-init reset, machine-IDs, SSH keys) | Proxmox host or any Debian/Ubuntu host |

## Call Chain

```
build-ubuntu-resolute-template
  │
  ├─ (auto-downloads proxmox/*.sh from GitHub if no local checkout)
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

## Two Ways to Run

### A) Remote (curl pipe) — no clone

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dbensmith/home-ops-bootstrap/main/build-ubuntu-resolute-template)
```

Downloads the builder scripts into a temp dir, runs, cleans up. Always pulls latest from `main`.

### B) Local (cloned repo) — for development

```bash
git clone git@github.com:dbensmith/home-ops-bootstrap.git
cd home-ops-bootstrap
./build-ubuntu-resolute-template
```

Uses local `proxmox/` files. Edit scripts and test without pushing first.

## What You Need to Customize

The `.env.tpl` file references `op://` URIs from **dbensmith's** 1Password vault. To use your own:

1. **Fork the repo** (or just edit locally)
2. **Create 1Password items** for these fields:
   - `SSHKEY` — your SSH public key
   - `NS1`, `NS2` — DNS server IPs
   - `SEARCHDOMAIN` — internal domain (e.g. `home.arpa`)
   - `TZ` — timezone (optional, e.g. `America/New_York`)
3. **Update `.env.tpl`** with your own `op://` URIs
4. Run the builder

Alternatively, you can skip the `.env.tpl` and set these as plain environment variables:

```bash
export SSHKEY="ssh-ed25519 AAAA..."
export NS1="10.0.0.1"
export NS2="10.0.0.2"
export SEARCHDOMAIN="home.arpa"
export TZ="America/New_York"
```

> **Note:** The wrapper uses `op run --env-file` which only supports `op://` URIs. If you want plain env vars, run the builder script directly:
> ```bash
> ./proxmox/build-ubuntu-resolute-template.sh
> ```

## VM Template Spec

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

## Key Commands

```bash
# Build Ubuntu Resolute amd64v3 template (default VMID: 526040)
./build-ubuntu-resolute-template

# Clean a qcow2 image independently (any Debian/Ubuntu image)
./proxmox/sysprep-ubuntu-resolute-template.sh <image.qcow2> [image2.qcow2 ...]
```

## 1Password Integration

Secrets stored as `op://` references in `.env.tpl` files. `op run --env-file` resolves them at runtime. Scripts read `$SSHKEY`, `$NS1`, etc. directly — zero `op read` calls in the builder.

Required 1Password secrets:
- `SSHKEY` — SSH public key injected into template
- `NS1`, `NS2` — DNS servers for Cloud-Init
- `SEARCHDOMAIN` — internal network domain
- `TZ` — timezone (optional)

Auth methods:
- **Interactive:** `op signin`
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

### Required on Proxmox host
- `libguestfs-tools` (provides `virt-customize`)
- `1password-cli` (`op`)

### Installed in template image (by `virt-customize`)
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
