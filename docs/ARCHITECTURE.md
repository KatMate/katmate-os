# Architecture

## Overview

```
                          Internet
                             │
                        [ NetVM ]            USB-NIC (r8152) passthrough; WireGuard/ProtonVPN
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
- Core stack: systemd, systemd-networkd/-resolved, nftables, QEMU/KVM.
- QEMU is currently installed as `qemu-full`; reduction to `qemu-base` is under
  evaluation to shrink the TCB (MicroVM machine type needs no GUI frontends).
- Operational consequence of the hardened kernel: io_uring is disabled
  (`kernel.io_uring_disabled = 2`), so VM launch scripts use `aio=threads`
  instead of `aio=io_uring`. (Live MINIS still runs stock `linux`, where
  `aio=io_uring` is active; the `aio=threads` switch lands with the hardened
  migration.)

### Storage layout

```
GPT
├── p1  ESP (FAT32, 512M)            → /boot
└── p2  LUKS2 → /dev/mapper/cryptlvm
        └── LVM vg0
            ├── root      ext4, 15% of disk (clamped 20–60 G)  → /
            ├── swap      sized = RAM
            └── thinpool  remainder (metadata 1%, clamped 64M–1G)
                          → VM storage (foundation, app snapshots,
                            instance deltas, persistent home LVs)
```

VM storage uses a three-level LVM-thin chain for system images and raw thin LVs
for persistent home ([ADR-010](DECISIONS.md#adr-010)): `foundation` (thin, RO)
← `app-<type>` (thin snapshot of foundation, RO-frozen) ← per-instance qcow2 RW
delta. See **Base image & template model** below.

## Guest MicroVMs

- Debian stable (trixie), minimal userspace, treated as an **appliance**:
  stability and predictability over freshness
  ([ADR-002](DECISIONS.md#adr-002), [ADR-005](DECISIONS.md#adr-005)).
- Custom kernel built from Debian LTS sources
  (`vmlinuz-katmate-microvm-amd64-6.12.x`), MicroVM-optimized config:
  virtio-blk / virtio-net / virtio-vsock, ext4, tmpfs, user namespaces, cgroups.
  Goals: fast direct kernel boot, low memory footprint, minimal attack surface.
- The kernel is **monolithic** — the listed subsystems are builtin, with no
  loadable modules. It is passed to QEMU via `-kernel` at launch and does
  **not** live inside the guest rootfs; the foundation image therefore carries
  no kernel and no `/lib/modules` tree.

## Base image & template model

([ADR-007](DECISIONS.md#adr-007), [ADR-010](DECISIONS.md#adr-010),
[ADR-011](DECISIONS.md#adr-011))

The base is an **LVM thin volume** (`foundation`), not a `.img` file. AppVM
system layers are thin snapshots of it; user data is a separate RW delta.

```
foundation                        thin LV, RO-frozen, shared by all AppVMs
  ├── Debian stable userspace (minimal, debootstrap)
  ├── waypipe — project-pinned tag + patch queue (ADR-019), source build
  └── vm-agent
        ▲
        │ lvcreate --snapshot  (thin snapshot, RO-frozen, + manifest packages)
        │
  app-<type>                      e.g. app-personal, app-net, app-work
        ▲
        │ qemu-img create -f qcow2 -F raw -b <app-snapshot>
        │
  instance                        per-VM qcow2 RW delta (system)
                                  + separate raw thin LV (persistent /home)

custom MicroVM kernel             external to the image, passed via -kernel
```

| Component | Lives in |
|---|---|
| OS userspace, waypipe, vm-agent | foundation (thin, RO) |
| Per-type application package set | app-`<type>` thin snapshot (RO) |
| System RW changes (ephemeral) | instance qcow2 delta |
| Application data, documents | raw thin home LV (RW, persistent) |
| Custom MicroVM kernel | host filesystem, passed via `-kernel` |

Update flow ([ADR-019](DECISIONS.md#adr-019)):

Waypipe is a project-maintained component: a pinned upstream tag plus a small
KatMate patch queue, built into **both** binaries from the same tree — guest
in the foundation chroot, host at `/opt/katmate/bin/waypipe` (outside the
package manager). Version drift is impossible by construction; there is no
pacman hook and nothing to detect.

1. A version bump is a deliberate release act: bump the pin → rebase the
   patch queue → build the host binary → rebuild `foundation` → re-snapshot
   each `app-<type>` → recreate instance deltas. Home LVs untouched.
   `katmate-update` orchestrates this chain.
2. `foundation.sh` records the active versions (waypipe tag + patch level,
   guest kernel, build date) in `/var/lib/katmate/foundation.meta` at
   RO-freeze time.
3. Instance launch preflights host `waypipe --version` against
   `foundation.meta` and refuses to start the VM loudly on mismatch — the
   lock is enforced where the two ends meet.
4. Debian LTS kernel security patch → rebuild guest kernel → shipped as the
   new external `-kernel` for the next foundation release. Waypipe fixes
   that do not build on trixie are backported onto the pinned tag (same
   practice).

Principles: immutability, reproducibility (foundation rebuilt from defined
sources, never hand-edited), strict system/data separation, user transparency,
minimal TCB.

### Guest waypipe build (part of the base image pipeline)

Waypipe in the guest is built from source, version-locked to the host
([ADR-008](DECISIONS.md#adr-008)); both binaries come from the same
project-pinned tree — upstream tag + KatMate patch queue
([ADR-019](DECISIONS.md#adr-019)). Built inside the foundation chroot so it
links against the foundation's own (trixie) libraries. The host binary is
built from the identical tree on the host and installed at
`/opt/katmate/bin/waypipe`.

```
apt install -y git meson ninja-build gcc pkg-config \
               libwayland-dev liblz4-dev libzstd-dev libgbm-dev \
               cargo rustc bindgen
git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git
cd waypipe && git checkout v0.11.0   # project pin (ADR-019)
for p in /path/to/third_party/waypipe/patches/*.patch; do git apply "$p"; done
cargo fetch                                  # build wrapper passes --frozen
meson setup build -Dbuildtype=release \
      -Dwith_lz4=enabled -Dwith_zstd=enabled \
      -Dwith_gbm=disabled -Dwith_dmabuf=disabled -Dwith_video=disabled
ninja -C build && ninja -C build install
waypipe --version          # expect: lz4: true, zstd: true
```

Build gotchas (each cost a failed build, recorded so they stay solved):

1. **Not pure C since ≥ 0.11** — the build needs `cargo` + `rustc` +
   `bindgen`. Without `bindgen`, meson errors out (`Program 'bindgen' not
   found`).
2. **Compression features must be explicit.** `with_lz4` / `with_zstd` default
   to `auto`, which can silently resolve to a build with `lz4: false`. Force
   them to `enabled` so a missing lib fails loudly instead of producing a
   binary that cannot talk to the host.
3. **gbm wrapper is compiled unconditionally.** Even with
   `-Dwith_gbm=disabled`, the `wrap-gbm` Cargo workspace member's `build.rs`
   calls `pkg-config gbm` and panics if absent. Install `libgbm-dev` to satisfy
   it; the feature stays off in the final binary (confirmed via
   `waypipe --version` and `ldd` — no gbm linkage).
4. **`cargo fetch` before `ninja`.** The compile wrapper runs cargo with
   `--frozen`, so crates must already be in the local cache or the build fails
   with "attempting to make an HTTP request, but --frozen was specified".
5. **Host/guest lz4 must match.** The host runs waypipe with `-c lz4`; if the
   guest binary has `lz4: false`, the vsock connection drops. This is the whole
   reason features are forced in step 2.

The build toolchain (gcc, cargo, rustc, bindgen, meson, ninja, `*-dev`) is
purged + `autoremove`d before the foundation is RO-frozen, so the immutable
base carries runtime libs only (libzstd1, liblz4-1, libgcc-s1, libc6,
libxxhash0) and no compiler. Verify with `ldd` after purge; a missing runtime
lib means reinstalling the non-`-dev` variant before freeze.

## Communication

AF_VSOCK exclusively ([ADR-003](DECISIONS.md#adr-003)). Channels: control
(vm-agent), file transfer, GUI forwarding. No TCP exposure; guests have no
network path to the host control plane.

### VM agent

Minimal command channel, implemented in C (Rust rewrite planned while the
codebase is still small). Commands:

| Command | Purpose |
|---|---|
| `PING` | health check |
| `RUN` | launch whitelisted GUI applications (`firefox-esr`, `foot`, `nautilus`) |
| `FILEGET` / `FILEPUT` | file transfer VM↔host, path-whitelisted, size-limited |
| `SHUTDOWN` | graceful VM shutdown |

Security controls are specified in [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component).

## GUI forwarding

Waypipe over AF_VSOCK; host side is a socket-activated systemd user service.
Guest runs waypipe built from source; the version **must** match the host
([ADR-008](DECISIONS.md#adr-008)) — mismatched versions negotiate
incompatible compression and the connection is refused or crashes. Both
binaries are built from the same project-pinned tree and the launch preflight
enforces the match against `foundation.meta`
([ADR-019](DECISIONS.md#adr-019)).
Benefits: no X11, no network listener, native Wayland path. Clipboard
(copy/paste) between guest applications and host is functional.

## Networking

**Live state (MINIS/UM870, v0.2):** NetVM is operational and is the sole
network-facing domain — as targeted by [ADR-009](DECISIONS.md#adr-009).
WireGuard (ProtonVPN) terminates in the NetVM, not on the host.

NetVM topology:
- **External leg:** USB-NIC passthrough (Realtek r8152, `usb-host`) — physical
  uplink `10.3.1.3/24`, gw `10.3.1.1`.
- **VPN:** `wg-quick@proton`, iface `10.2.0.2/32`; NAT masquerade out `proton`;
  `ip_forward=1`.
- **Inner segment:** virtio NIC via TAP bridge on host, `10.100.1.1/32`;
  AppVMs connect here and route all traffic through the VPN.
- nft: input drop (+ WireGuard port 51820); forward limited to segment↔proton.

AppVMs (e.g. personalVM) have a virtio NIC on the inner segment (`10.100.1.2/32`),
DNS via `10.2.0.1` (ProtonVPN resolver). No direct host network access.

Note: NetVM currently runs as a **q35** machine (not MicroVM), 1 vCPU, ~1 GiB
RAM. MicroVM migration is a future cleanup item.

## Disposable VMs (planned, v0.3)

Created on demand, temporary storage, automatic destruction. Use cases:
unknown PDFs, suspicious downloads, throwaway browsing sessions. CID allocated
dynamically from the pool ([ADR-017](DECISIONS.md#adr-017)).

## Desktop layer

greetd + tuigreet login manager → Hyprland 0.55.2 (Wayland compositor),
Plymouth boot splash ("katmate" theme), fish shell.

The Hyprland configuration uses the **CYBRland** theme
(`github.com/scherrer-txt/cybrland`): teal/cyan accent palette, GeistMono
Nerd Font, single-monitor layout (eDP-1), animations disabled for performance.
Supporting tools: hypridle, hyprlock, hyprpaper, hyprpicker, pyprland, Rofi,
waybar, swaync, kitty, yazi.

Two-profile model ([ADR-016](DECISIONS.md#adr-016)): a shared visual layer with
**Sway** as the stable default and **Hyprland/CYBRland** as the optional
profile. MINIS currently runs Sway (dual head DP-3 / HDMI-A-1); the CYBRland
Hyprland layer is configured on the Acer dev machine and migration to MINIS is
in progress. Installer integration will require adding `kms` to the mkinitcpio
`HOOKS` for Plymouth.

## Target hardware class

x86-64 UEFI with **VT-d / AMD-Vi** (IOMMU required — VT-x-only platforms
frozen per ADR-015). Performance floor: Apollo Lake-class (Pentium N6000,
8 GB RAM). Full matrix of reference machines:
[INSTALL.md](INSTALL.md#tested--reference-hardware).
