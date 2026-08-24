# Architecture

## Overview

```
                          Internet
                             │
                    ┌────────┴────────┐
                    │  NetVM (sysVM)  │  q35 · RTL8125 vfio passthrough
                    │  CID 3          │  WireGuard/ProtonVPN · nftables
                    └────────┬────────┘
                             │  per-AppVM /32 p2p links
┌──────────────────── Host — Arch Linux (linux-hardened) ────────────────────┐
│  systemd-boot · LUKS2 + LVM · nftables · QEMU/KVM · waypipe · Sway         │
└──┬──────────────┬──────────────┬──────────────┬────────────────────────────┘
   │              │              │              │       AF_VSOCK only:
[Browser VM]  [Office VM]    [Dev VM]   [Disposable VM]   control · files · GUI
                 Debian MicroVMs — custom LTS kernel, direct kernel boot
```

The host owns VM lifecycle, storage, policy enforcement, GUI compositing and
**the network topology**. Guests execute applications and hold isolated user
data. All host↔guest communication crosses explicitly exposed VSOCK channels.

## Object model

([ADR-022](DECISIONS.md#adr-022))

The core defines five object classes. The network is a **graph of VMs**; the
physical NIC is an **assignable host resource**. Topology is data, not structure
baked into code.

| Class | Nature | Fields / notes |
|---|---|---|
| `Nic` | host inventory | PCI address, IOMMU group, binding (host / `vfio-pci`), `assigned_to: Option<VmRef>`. Assignable to **at most one** VM. The same shape later serves USB controllers and audio. |
| `Image` | build artifact | foundation (thin, RO) / `app-<type>` (thin snapshot, RO) / sysVM image (linear RW LV) / instance qcow2 delta. Orthogonal to runtime. |
| `Vm` | runtime unit | name, class (`app` \| `sys`), CID, image ref, resources, **`netvm: Option<VmRef>`**, **`provides_network: bool`**. |
| `Link` | runtime, host-owned | one p2p segment: TAP, `/32` addressing, the fragment delivered by NETCFG. Created at launch, destroyed at teardown. Owned by the launch daemon; never by a guest. |
| `Policy` | two-layer | (a) compile-time opcode set per VM class (absent-not-disabled); (b) the static nft ruleset **baked into a netVM image**. |

The entire topology is two fields on `Vm`: `netvm` (whom do I route through) and
`provides_network` (may others route through me). A graph edge is a `Link`.

**Consequences of the model:**

- **Policy is a netVM, not a rule.** An AppVM's network *access* is exactly
  which netVM it attaches to. Each netVM image bakes one fixed policy
  (`netvm-vpn`, `netvm-clearnet`, `netvm-lan-only`, …). The nft ruleset inside a
  netVM never changes as AppVMs come and go; isolation is carried by **topology**
  (per-AppVM `/32` p2p links), never by per-AppVM firewall rules
  ([ADR-021](DECISIONS.md#adr-021)).
- **`netvm: None` is a first-class offline AppVM.** No `Link`, no TAP, no route.
  Air-gap is the *absence of an object*, not a rule denying traffic.
- **One physical NIC = one q35 driver domain.** A VM holding a passed-through NIC
  runs `-machine q35` (PCI topology for vfio), full systemd + networkd +
  initramfs + firmware — and holds **no secrets**.
- **Proxy netVMs are microVMs and may be chained.** A netVM with no physical NIC
  (VPN terminator, aggregating firewall) has only virtio links → no PCI topology
  → **microvm**. Its uplink is just another `Link`. Chaining
  (`appVM → netvm-vpn → netvm-driver → NIC`) is therefore cheap here.
- **The launch daemon is the only component that understands the graph.** It
  walks `netvm` references, allocates CIDs and `/32`s, creates `Link`s, calls
  NETCFG on each node of the path at launch and teardown, and refuses to tear
  down a `provides_network` VM while dependents run. Agents stay dumb executors.
- **v1 instantiates the simplest graph:** one driver domain terminating the
  uplink and carrying the VPN — exactly the netVM running today. The split
  driver/VPN chain is a post-v1 *paranoid profile*, not a v1 blocker.

## Host

- Arch Linux with the `linux-hardened` kernel ([ADR-004](DECISIONS.md#adr-004)),
  systemd-boot (no menu: `timeout 0`, `editor no` — [ADR-006](DECISIONS.md#adr-006)).
- Core stack: systemd, systemd-networkd/-resolved, nftables, QEMU/KVM.
- QEMU is currently installed as `qemu-full`; reduction to `qemu-base` is under
  evaluation to shrink the TCB (MicroVM machine type needs no GUI frontends).
- Operational consequence of the hardened kernel: io_uring is disabled
  (`kernel.io_uring_disabled = 2`), so VM launch scripts use `aio=threads`
  instead of `aio=io_uring`. Live on MINIS since 2026-07-23. Not merely a
  constraint: io_uring is among the most CVE-dense kernel subsystems and this
  path runs host-side, driven by guest I/O patterns.

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

VM storage uses a three-level LVM-thin chain for AppVM images and raw thin LVs
for persistent home ([ADR-010](DECISIONS.md#adr-010)): `foundation` (thin, RO)
← `app-<type>` (thin snapshot of foundation, RO-frozen) ← per-instance qcow2 RW
delta. See **Base image & template model** below.

sysVMs are **outside** this chain: a netVM lives on a **standalone linear RW LV**
(not thin, not frozen, nobody's backing store — [ADR-021](DECISIONS.md#adr-021)),
so none of the `-K -ay` skip-activation handling applies to it.

## VM classes

| Class | Machine | Init | Storage | Kernel | Agent |
|---|---|---|---|---|---|
| **AppVM** | `microvm` | `katmate-init` | thin chain + qcow2 delta | custom monolithic, `-kernel` | `vm-agent` (uid 1000, whitelist) |
| **sysVM — driver domain** | `q35` (vfio needs PCI) | systemd | standalone linear RW LV | stock Debian `linux-image-amd64` + initrd, `-kernel`/`-initrd` | `netvm-agent` (`CAP_NET_ADMIN`+ CAP_KILL) |
| **sysVM — proxy** (post-v1) | `microvm` (no PCI needed) | open (`katmate-init` viable) | standalone linear RW LV | custom monolithic, `-kernel` | `netvm-agent` `netvm-agent` (caps TBD — no ADR; note `microvm` has no ACPI, so `SHUTDOWN` will be needed) |

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
- `CONFIG_HW_RANDOM_VIRTIO` and `CONFIG_SECURITY_LANDLOCK` are **live** (built
  2026-07-01, re-confirmed in the 2026-07-13 boot log: `landlock: Up and
  running`, `crng init done` @ 0.010s). No rebuild pending.
- Proxy sysVMs ([ADR-022](DECISIONS.md#adr-022)) will require `CONFIG_WIREGUARD`
  + the nft/netfilter set in this same shared kernel. That code is unreachable
  from an AppVM (uid 1000, no `CAP_NET_ADMIN`) but *present* — a conscious
  departure from absent-not-disabled at the kernel level, taken up when the first
  proxy is built.

  # Base image & template model

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

`katmate-update` **never touches sysVMs**: netVM has no waypipe and no shared
foundation. It has its own track, `netvm-update`, driven by Debian security
updates and network-configuration changes ([ADR-021](DECISIONS.md#adr-021)).

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

### sysVM build

netVM is built by its own declarative pipeline, `build/netvm.sh`
([ADR-021](DECISIONS.md#adr-021)): debootstrap onto a standalone linear RW LV →
mount → chroot → bake from a netVM-specific package + config manifest → export
`vmlinuz` + `initrd` to a host-side artifact → unmount. Full systemd (not
`--variant=minbase`), `non-free-firmware` enabled (`firmware-realtek` is
**mandatory** for the RTL8125), an initramfs (`MODULES=most`), **no waypipe, no
katmate-init**. The image is **AppVM-agnostic**: it bakes no internal topology
at all — every internal route arrives at runtime via NETCFG.

## Communication

AF_VSOCK exclusively ([ADR-003](DECISIONS.md#adr-003)). No TCP exposure; guests
have no network path to the host control plane.

| Port | Channel |
|---|---|
| 1024 | GUI forwarding (waypipe) |
| 1025 | control (agent) |
| 1026 | audio (planned) |

### CID allocation

([ADR-017](DECISIONS.md#adr-017), re-scoped by [ADR-022](DECISIONS.md#adr-022))

| Range | Class |
|---|---|
| 2 | host |
| 3–19 | sysVMs (3 = primary/default netVM) |
| 20–99 | fixed persistent AppVMs |
| ≥ 100 | dynamic disposable AppVM pool |

The launch daemon and the domain indicator both read this map. It replaces the
earlier single-sysVM scheme (3 = netVM, 4–8 = fixed AppVM): fixed AppVMs move to
20+ to leave room for chained sysVMs.

### VM agents

Rust Cargo workspace ([ADR-021](DECISIONS.md#adr-021)): a shared
`katmate-protocol` crate (framing, VSOCK transport, error types, opcode
wire-value registry) plus **two** bin crates. The split is a security measure —
*absent code paths are stronger than disabled ones*. Opcode enums and handlers
are per-binary; a forbidden opcode fails at **decode** (`TryFrom<u8>`), not at a
runtime gate.

| Opcode | `vm-agent` (AppVM, uid 1000) | `netvm-agent` (sysVM, `CAP_NET_ADMIN`) |
|---|---|---|
| `PING` | handler | handler |
| `RUN` (whitelist: `firefox-esr`, `foot`, `nautilus`) | handler | **absent** |
| `FILEGET` / `FILEPUT` (path-whitelisted, size-limited) | handler | **absent** |
| `SHUTDOWN` | handler (microvm has no ACPI) | handler — `kill(1, SIGRTMIN+4)` under `CAP_KILL` ([ADR-024](DECISIONS.md#adr-024)); the QMP `system_powerdown` path is inert without dbus |
| `NETCFG` | **absent** | handler (privileged) |

`NETCFG` describes **a link, never an AppVM** ([ADR-023](DECISIONS.md#adr-023)):
a structured p2p link payload (interface match, local/peer address, `/32`
prefix, route, metric) with `add` / `remove` operations and no `modify`. It
carries **no policy** — no nft rule, no shell string, no VM name, no role. The
same opcode therefore serves an AppVM downlink, a proxy uplink and a future
sysVM-to-sysVM edge. The host is always the caller.

Security controls: [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component).

## GUI forwarding

Waypipe over AF_VSOCK (port 1024); host side is a socket-activated systemd user
service. Guest runs waypipe built from source; the version **must** match the
host ([ADR-008](DECISIONS.md#adr-008)) — mismatched versions negotiate
incompatible compression and the connection is refused or crashes. Both
binaries are built from the same project-pinned tree and the launch preflight
enforces the match against `foundation.meta`
([ADR-019](DECISIONS.md#adr-019)).
Benefits: no X11, no network listener, native Wayland path. Clipboard
(copy/paste) between guest applications and host is functional.

## Networking

**Live state (MINIS/UM870, v0.2):** netVM is operational and is the sole
network-facing domain ([ADR-009](DECISIONS.md#adr-009)). WireGuard (ProtonVPN)
terminates in netVM, not on the host. netVM is a **sysVM**
([ADR-021](DECISIONS.md#adr-021)) and, in [ADR-022](DECISIONS.md#adr-022) terms,
a **driver domain**.

netVM topology:
- **Uplink:** RTL8125 (`10ec:8125`, IOMMU group 12) passed through via
  `vfio-pci` (`disable_idle_d3=1`, `softdep r8169 pre: vfio-pci`). The guest's
  own `r8169` needs `firmware-realtek` (`rtl_nic/rtl8125b-2.fw`) or the PHY stays
  down. `20-uplink.network` matches by **MAC**, not interface name, so a PCI
  slot change cannot break it. DHCP.
- **VPN:** `wg-quick@proton`; NAT masquerade out `proton`; `ip_forward=1`.
- **Internal segment:** `10.100.1.0/24`. Each AppVM gets its own p2p `Link` with
  a link-scoped `/32` route, delivered by **NETCFG at launch** and withdrawn at
  teardown. **Nothing is baked** — on a clean boot netVM has no internal route,
  which is correct: with no AppVMs running there is nowhere to route.
- **What carries a link — proposed, not settled**
  ([ADR-033](DECISIONS.md#adr-033), PROPOSED): a link is a pair of **AF_UNIX
  datagram sockets**, one end opened by each QEMU by path at start. **The host
  holds no network object for it** — no tap, no bridge, no namespace, and no
  privileged network step in an AppVM's start path. netVM starts with a **fixed
  pool of link slots**, allocated and reconciled the way CIDs are
  ([ADR-017](DECISIONS.md#adr-017)); an AppVM takes a free slot at launch and
  releases it at teardown. **The pool size is open** pending ADR-033's M2
  measurement. Until that ADR is accepted the mechanism of record is the one the
  `Link` row in § *Object model* states — TAP — and the two are deliberately left
  disagreeing rather than reconciled early.
- **nft:** static, AppVM-agnostic. Input drop; forward limited to
  segment ↔ `proton`, referencing only the aggregate `10.100.1.0/24`, never a
  per-AppVM rule. Per-`/32` isolation is **topology**, not firewall.

AppVMs have no direct host network access and no guest-to-guest path.

**Known v1 co-location** ([ADR-022](DECISIONS.md#adr-022)): the WireGuard key and
the `r8169` driver + Realtek firmware blob share one address space. Resolved
post-v1 by splitting into a driver domain (hardware, no secrets) and a proxy
netVM (secrets, no hardware).

## Disposable VMs (planned, v0.3)

Created on demand, temporary storage, automatic destruction. Use cases:
unknown PDFs, suspicious downloads, throwaway browsing sessions. CID allocated
dynamically from the ≥ 100 pool.

## Desktop layer

The host compositor is **part of the TCB**: it hosts waypipe windows and draws
the domain indicator that visually guarantees the boundary between domains. That
indicator must be drawn by trusted host-side code keyed on **waypipe CID
identity** — never on guest-controlled properties (`app_id`, window title are
spoofable).

**Sway is the single shipped profile** ([ADR-016](DECISIONS.md#adr-016)): stable
config format, conservative churn, one implementation of the security-critical
indicator to write and audit. greetd + tuigreet → Sway, Plymouth boot splash,
fish shell.

**Hyprland/CYBRland is a dev/demo profile, not a release artifact** — configured
on the Acer (`github.com/scherrer-txt/cybrland`: teal/cyan palette, GeistMono
Nerd Font, waybar, rofi, swaync, hyprpaper). It stands as proof that the DE
profile is a replaceable contract, and becomes a second shipped profile only
when its indicator implementation is separately verified.

The DE profile contract: (1) host waypipe client per domain, (2) domain identity
hook keyed on waypipe CID, host-side — the *carrier* is compositor-specific and
is not part of the contract (Sway offers per-window border width, opacity and
marks; border colour is global and therefore only usable for the focused
window), (3) bar module reading launch-daemon state, (4) keybindings → katmate
CLI.

Installer integration will require adding `kms` to the mkinitcpio `HOOKS` for
Plymouth.

## Target hardware class

x86-64 UEFI with **VT-d / AMD-Vi** (IOMMU required — VT-x-only platforms frozen
per [ADR-015](DECISIONS.md#adr-015)). Because a driver domain requires the NIC to
sit in a **cleanly isolable IOMMU group**
([ADR-022](DECISIONS.md#adr-022)), IOMMU-group quality is a hard hardware
requirement, not an implementation detail — implying an HCL and an installer
preflight check. Performance floor: Apollo Lake-class (Pentium N6000, 8 GB RAM).
Reference machines: [INSTALL.md](INSTALL.md#tested--reference-hardware).
