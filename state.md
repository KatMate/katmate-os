# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Last updated:** 2026-06-22 (vm-agent rewritten C → Rust, committed)
**Milestone:** v0.2 (in development)

## Current focus

Hardening the appliance vertical slice on MINIS/UM870 (the VT-d host) and
migrating the live AppVMs onto the new foundation chain.

The full GUI chain is proven end-to-end (2026-06-21): `foundation (thin RO) ←
vm_app_web (thin snapshot RO) ← qcow2 delta` → custom microvm kernel → vm-agent
→ waypipe-over-VSOCK → host Hyprland, with `nautilus` rendered as non-root user
1000. This validated the central architectural claim (waypipe-over-VSOCK as the
GUI trust boundary). Details and diagnostic path: git `9526091` and earlier.

vm-agent has since been rewritten C → Rust (2026-06-22, see below).

Direction: target IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only frozen
(ADR-015). MINIS is primary host and merge target. Acer-line desktop assets
(Hyprland + CYBRland + Plymouth) inspected 2026-06-17, migration still pending.

## Live state (MINIS/UM870) — summary

- **Host** (Arch): kernel stock `linux` (hardened migration opportunistic),
  Ryzen 7 8745H, AMD-Vi + vfio. `vg0`: `root` 100G, `swap` 12G, `vm_pool`
  thin pool 700G. Desktop: Hyprland (dual head). Custom microvm kernel
  `6.12.87` deployed at `/home/host/katmate-kernels/` (monolithic, `-kernel`,
  no initrd). Host nft input drop; SSH open (dev, Open problem #4).
- **netVM** (CID 3, Debian trixie, q35): USB-NIC passthrough (r8152),
  WireGuard/ProtonVPN terminates here, inner segment routing. Non-GUI vm-agent.
- **personalVM** (CID 4, Debian trixie, microvm): inner-segment networking via
  netVM, vm-agent user service → waypipe → firefox-esr. qcow2 overlay + raw
  home LV.
- **Disk chain**: target three-level LVM-thin chain proven live. `vm_tpl_-
  foundation` (10G thin RO) built + frozen; `vm_app_web` (thin snapshot RO,
  first app-layer) built + frozen; instance deltas in
  `/var/lib/katmate/instances/`. Older live AppVMs (personal/net) still on the
  pre-foundation linear-root model — re-pointing is the remaining migration.
  Full inventory + build recipes: git history, ADR-010/011/014.

## vm-agent: Rust rewrite (2026-06-22, ADR-018)

Rewritten C → Rust (`std` + `libc` only, no async runtime). The text
line-protocol is replaced by a versioned little-endian length-prefixed binary
frame (PROTOCOL_VERSION 1): all length fields bounds-checked before allocation;
`posix_spawn` instead of fork-then-work; `SIGCHLD=SIG_IGN` kernel-side reaping;
atomic FILEPUT (temp + fsync + rename); traversal-safe path confinement without
`canonicalize`; debug logging stripped from release builds via
`cfg!(debug_assertions)`. Synchronous, single-client by design.

- Committed as `01b70e9` under `agent/`; the C agent (`agent/vm-agent.c`) is
  kept as reference until the Rust binary is validated on a live host.
- Two intentional dead-code warnings (`write_ok_payload`, `read_raw`) — API
  surface for the planned streaming path and host-side client.
- **Not yet deployed:** the frozen foundation still ships the **C** binary.
  Building the Rust binary into the foundation + re-freeze + live `PING`/`RUN`
  validation is an open item (Next steps).

## Open problems

1. **Desktop migration Acer → MINIS** — CYBRland Hyprland config + Plymouth
   theme to port; greetd swap; Hyprland + deps on MINIS.
2. **Kernel migration `linux` → `linux-hardened`** on MINIS (opportunistic);
   re-validate io_uring/aio; recheck suspend/resume regression.
3. **Installer secrets** (v0.2 blocker): WireGuard key, WiFi PSK, credentials
   must be removed before release; rotate burned WG key; drop `Hidden=true`.
   SECURITY-MODEL gap #1.
4. **SSH open on MINIS host** — dev convenience, not shipped policy. Fix
   identified (`iif enp1s0 ip saddr 10.3.1.0/24`), not applied. SECURITY-MODEL
   gap #4.
5. **"Enoch OS"** description string in live `vm-agent.service` (personalVM) —
   pre-alpha artifact, remove.
6. Disk model + GUI chain are **resolved** end-to-end (2026-06-21). What remains
   is build hardening + migration (tracked in Next steps), not the mechanism.

## Next steps

- **vm-agent deploy/validate:** build the Rust binary into the foundation,
  re-freeze, live-validate (`PING`/`RUN`) on a real guest. Follow-ups: FILEPUT
  streaming (currently buffers the payload in memory), the `vm-power-helper`
  security story, and a binary host-side client speaking the same frame (the
  protocol module is structured for promotion to a shared `katmate-protocol`
  crate once that client exists).
- **App-layer build hardening (unblocks unattended GUI launch):** bake user
  1000 + vm-agent as a systemd **user** unit (carrying `XDG_RUNTIME_DIR` +
  session bus) into the app-layer build, mirroring personalVM; re-freeze
  `vm_app_web`. This is what makes `RUN <app>` work without the manual
  `runuser`/`dbus-run-session` dance. Recipe: git `9526091`.
- **Kernel rebuild (6.12.87 → next):** add `CONFIG_HW_RANDOM_VIRTIO=y` and
  `CONFIG_SECURITY_LANDLOCK=y`; keep confirmed builtins (`VIRTIO_VSOCKETS`,
  `VIRTIO_MMIO`, `NET_9P_VIRTIO`, `EXT4_FS`).
- **Launch daemon / privilege split:** fold activation + tap setup into the
  AppVM systemd unit (`ExecStartPre=+` runs `lvchange -K -ay` as root, QEMU as
  `host`); declarative `tap-<type>` on `br-personal`; shared
  `katmate-foundation.service` oneshot.
- **udisks2 check:** confirm nautilus lists the 9p hostshare with udisks2
  stopped, then bake `systemctl disable udisks2` into the app-layer build.
- **`/home` cleanup + migration:** move live overlays into
  `/var/lib/katmate/instances/`; re-point live personal/net deltas onto the new
  foundation/app-layer chain (off the old `vm_tpl_*_root` linear roots).
- **Desktop:** port CYBRland + Plymouth from Acer to MINIS.
- **Installer:** secrets removal (v0.2 blocker); create `/var/lib/katmate/`.

## Invariants & gotchas (quick reminders — detail in git/ADRs)

- **Thin-LV activation:** an RO-frozen thin LV keeps the skip-activation `k`
  flag permanently; `lvchange -K -ay <lv>` is mandatory before every instance
  boot, on both the app-layer AND the foundation, or QEMU fails with "Could not
  open backing image". Almost certainly the root of the Feb/Mar blocker.
- **GUI launch:** GTK apps refuse to run as root; require user 1000 in a real
  session (`XDG_RUNTIME_DIR` + session bus via `dbus-run-session` or the user
  unit). waypipe ≥0.11 self-resolves the host CID (no `2:` prefix).
- **VSOCK ports:** 1025 = vm-agent control channel, 1024 = waypipe GUI channel
  — two distinct purposeful ports.
- **Custom microvm kernel** is monolithic and passed via `-kernel` (no initrd,
  no `/lib/modules`); this is why the stock modular Debian kernel failed in the
  module-less foundation and 6.12.87 (vsock builtin) succeeded.
- **Reproducibility** (apt snapshot pin) deferred until a rebuild pipeline
  (`katmate-update`) exists; the RO-frozen image is itself the pin. ADR-011.
- **Abstract vs concrete naming:** ADRs use `foundation`/`app`/`instance`;
  concrete LVM names (`vm_tpl_foundation`, `vm_app_web`) only here and in live
  inspection.
