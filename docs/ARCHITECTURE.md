# Architecture

## Overview

```
                          Internet
                             │
                        [ NetVM ]            target (v0.3) — today: WireGuard on host
                             │
┌──────────────────── Host — Arch Linux (linux-hardened) ────────────────────┐
│  systemd-boot · LUKS2 + LVM · nftables · QEMU/KVM · waypipe · Hyprland     │
└──┬──────────────┬──────────────┬──────────────┬────────────────────────────┘
   │              │              │              │       AF_VSOCK only:
[Browser VM]  [Office VM]    [Dev VM]   [Disposable VM]   control · files · GUI
                 Debian MicroVMs — custom LTS kernel, direct kernel boot
```

The host owns VM lifecycle, storage, policy enforcement, GUI compositing and
network routing. Guests execute applications and hold isolated user data.
All host↔guest communication crosses explicitly exposed VSOCK channels.

## Host

- Arch Linux with the `linux-hardened` kernel ([ADR-004](DECISIONS.md#adr-004)),
  systemd-boot (no menu: `timeout 0`, `editor no` — [ADR-006](DECISIONS.md#adr-006)).
- Core stack: systemd, systemd-networkd/-resolved, nftables, WireGuard, QEMU/KVM.
- QEMU is currently installed as `qemu-full`; reduction to `qemu-base` is under
  evaluation to shrink the TCB (MicroVM machine type needs no GUI frontends).
- Operational consequence of the hardened kernel: io_uring is disabled
  (`kernel.io_uring_disabled = 2`), so VM launch scripts use `aio=threads`
  instead of `aio=io_uring`.

### Storage layout

```
GPT
├── p1  ESP (FAT32, 512M)            → /boot
└── p2  LUKS2 → /dev/mapper/cryptlvm
        └── LVM vg0
            ├── root      ext4, 15% of disk (clamped 20–60 G)  → /
            ├── swap      sized = RAM
            └── thinpool  remainder (metadata 1%, clamped 64M–1G)
                          → VM storage (base images, overlays, persistent data)
```

Current direction for VM storage (formalization pending, [ADR-010](DECISIONS.md#adr-010)):
qcow2 root overlays for AppVMs backed by the immutable base image; raw thin LVs
for persistent home data.

## Guest MicroVMs

- Debian stable, minimal userspace, treated as an **appliance**: stability and
  predictability over freshness ([ADR-002](DECISIONS.md#adr-002), [ADR-005](DECISIONS.md#adr-005)).
- Custom kernel built from Debian LTS sources
  (`vmlinuz-katmate-microvm-amd64-6.12.x`), MicroVM-optimized config:
  virtio-blk / virtio-net / virtio-vsock, ext4, tmpfs, user namespaces, cgroups.
  Goals: fast direct kernel boot, low memory footprint, minimal attack surface.

## Base image & template model

([ADR-007](DECISIONS.md#adr-007))

```
katmate-base-YYYYMMDD.img        immutable, versioned, shared read-only
  ├── Debian stable userspace (minimal)
  ├── custom MicroVM kernel (Debian LTS sources)
  ├── waypipe X.Y.Z  — version-locked to host
  └── vm-agent

AppVM  =  base image (RO)  +  appvm-<name> overlay (RW, user data only)
```

| Component | Lives in |
|---|---|
| OS, kernel, waypipe, vm-agent | base image |
| Application data, configuration, documents | overlay |

Update flow:

1. Host updates waypipe (pacman) → pacman hook triggers `katmate-update`.
2. `katmate-update` compares host waypipe version against the active base image.
3. On mismatch: rebuild `katmate-base-YYYYMMDD+1.img`, recycle AppVM overlays
   onto the new base. The user gets a notification — no action required.
4. Debian LTS kernel security patch → rebuild guest kernel → included in the
   next base image release.

Principles: immutability, reproducibility (base rebuilt from defined sources,
never hand-edited), strict system/data separation, user transparency, minimal TCB.

### Guest waypipe build (part of the base image pipeline)

Waypipe in the guest is built from source and pinned to the host version
([ADR-008](DECISIONS.md#adr-008)):

```
apt install -y meson ninja-build libwayland-dev pkg-config liblz4-dev \
               libzstd-dev git libgbm-dev cargo bindgen
git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git
cd waypipe && git checkout v0.11.0
cargo fetch --manifest-path Cargo.toml      # required: build wrapper uses --frozen
meson setup build && ninja -C build && ninja -C build install
```

`bindgen` is mandatory — without it the lz4/zstd feature gates resolve to
`false` and compression negotiation with the host fails. Expected result:
`lz4: true, zstd: true`.

## Communication

AF_VSOCK exclusively ([ADR-003](DECISIONS.md#adr-003)). Channels: control
(vm-agent), file transfer, GUI forwarding. No TCP exposure; guests have no
network path to the host control plane.

### VM agent

Minimal command channel, implemented in C. Commands:

| Command | Purpose |
|---|---|
| `PING` | health check |
| `RUN` | launch whitelisted GUI applications (`firefox-esr`, `foot`, `nautilus`) |
| `FILEGET` / `FILEPUT` | file transfer VM↔host, path-whitelisted, size-limited |
| `SHUTDOWN` | graceful VM shutdown |

Security controls are specified in [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component).

## GUI forwarding

Waypipe over AF_VSOCK; host side is a socket-activated systemd user service.
Guest runs waypipe 0.11.0 built from source; the version **must** match the
host ([ADR-008](DECISIONS.md#adr-008)) — mismatched versions negotiate
incompatible compression and the connection is refused or crashes.
Benefits: no X11, no network listener, native Wayland path. Clipboard
(copy/paste) between guest applications and host is functional.

## Networking

- **Current (v0.2):** host-side systemd-networkd/-resolved, nftables with
  default-drop input policy, WireGuard (ProtonVPN) on the host.
- **Target (v0.3, [ADR-009](DECISIONS.md#adr-009)):** NetVM as the sole
  network-facing domain — DHCP, DNS, VPN, firewalling, routing. AppVMs receive
  connectivity only through the NetVM. Host-side VPN is transitional.

## Disposable VMs (planned, v0.3)

Created on demand, temporary storage, automatic destruction. Use cases:
unknown PDFs, suspicious downloads, throwaway browsing sessions.

## Desktop layer (development state)

greetd + tuigreet → Hyprland 0.55.2 (Wayland), Plymouth boot splash
("katmate" theme), fish shell. Currently configured on development machines
only; installer integration is planned and will require adding `kms` to the
mkinitcpio `HOOKS` for Plymouth.

## Target hardware class

x86-64 UEFI with VT-x/AMD-V. Performance floor: Gemini Lake-class
(Celeron N4000, 8 GB RAM). Full matrix of reference machines:
[INSTALL.md](INSTALL.md#tested--reference-hardware).
