# home-ops-bootstrap

Infrastructure bootstrapping scripts. Runs on Proxmox hosts before Ansible takes over.

## Structure

```
home-ops-bootstrap/
├── build-ubuntu-resolute-template          # Entry point. op run wrapper.
└── proxmox/
    ├── build-ubuntu-resolute-template.sh    # Builder. Reads env vars, runs qm commands.
    ├── build-ubuntu-resolute-template.env.tpl  # 1Password secret references
    └── sysprep-ubuntu-resolute-template.sh  # Reusable. Cleans Debian/Ubuntu qcow2 images.
```

## Call chain

```
./build-ubuntu-resolute-template
  │
  ├─ op run --env-file=proxmox/build-ubuntu-resolute-template.env.tpl
  │     Resolves op:// references → env vars (SSHKEY, NS1, NS2, SEARCHDOMAIN, TZ)
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

## Key commands

```bash
# Build Ubuntu Resolute amd64v3 template
./build-ubuntu-resolute-template

# Clean a qcow2 image independently (any Debian/Ubuntu image)
./proxmox/sysprep-ubuntu-resolute-template.sh <image.qcow2> [image2.qcow2 ...]
```

## Conventions

### 1Password
- Secrets stored as `op://` references in `.env.tpl` files
- `op run --env-file` resolves them at runtime → env vars
- Scripts read `$SSHKEY`, `$NS1`, etc. directly — zero `op read` calls in builder
- Auth: `op signin` (local) or `OP_SERVICE_ACCOUNT_TOKEN` (headless/CI)

### Template creation
- Ceph-backed storage assumed (`DISK_STOR="ceph"`)
- OVMF/UEFI boot required (`--bios ovmf --efidisk0`)
- virt-customize installs `qemu-guest-agent,cloud-utils,cloud-guest-utils`
- Builder validates required env vars before starting
- Destroys existing VMID before creating (idempotent re-runs)
- Converts to Proxmox template (`qm template`) at end

### sysprep operations (offline, via virt-customize)
- `apt-get clean && apt-get autoclean`
- `cloud-init clean --logs`
- Truncate `/etc/machine-id`, `/var/lib/dbus/machine-id`
- `dpkg-reconfigure openssh-server` on first boot

## Commit conventions

ALL commits use Conventional Commits format. Load caveman-commit skill before writing any commit message — compress subject ≤50 chars, imperative mood, body only when why not obvious. No AI attribution, no emoji, no fluff. Breaking changes demand body with migration notes.
<!-- commit-conventions -->

## Dependencies

### On Proxmox host
- `libguestfs-tools` (virt-customize)
- `1password-cli` (op)

### In template image (installed by virt-customize)
- `qemu-guest-agent`
- `cloud-utils`, `cloud-guest-utils`

## Growth

Future directories for other bootstrap domains:
```
home-ops-bootstrap/
├── proxmox/          # VM templates
├── pve-host/         # PVE node provisioning (packages, firewall, Ceph init)
├── network/          # VLAN/DNS bootstrap
└── talos/            # Talos Linux cluster bootstrap
```

Pattern per domain: wrapper at root (`build-<thing>`), scripts + `.env.tpl` in domain subdirectory.
