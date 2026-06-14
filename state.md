# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.

**Last updated:** 2026-06-14
**Milestone:** v0.2 (in development)

## Current focus

Host stack validated on bare metal (Dell) and pipeline skeleton in repo.
Installer drift (docs vs code) resolved. Next: VM launcher — the Faza 1 gate.

## Recently resolved

- ADR-014 (AppVM domain model + three-layer image composition), ADR-010/011
  Accepted. Pipeline skeleton in repo: `build/{config,lib,foundation,app-layer}.sh`,
  `manifests/{web,vault}.list`, `Makefile` (commits c899f37, cf6c079).
- Host validated on bare metal: LUKS → cryptlvm → vg0 (root/swap/thinpool),
  linux-hardened, systemd-boot, KVM, vhost_vsock, qemu-full — all confirmed.
- **Installer sync (commit b1f1ede):** `installer/install.sh` + `postinstall.sh`
  in git were stale (old GRUB/cryptroot/plain-linux, no lvm2). Replaced with the
  documented systemd-boot/cryptlvm/linux-hardened/qemu-full versions from project
  knowledge. Added `vhost_vsock` autoload (`/etc/modules-load.d/katmate-vsock.conf`)
  — AF_VSOCK is the only host↔guest channel (ADR-003), must load at boot.
  Now docs = git.

## Open problems

1. **Dell still on old GRUB install** from 2026-06-13 (stale scripts). Works,
   but not aligned. Fix = reinstall from current `installer/` (systemd-boot/
   cryptlvm/qemu-full). No launcher dependency.
2. **Suspend/resume failure under `linux-hardened`** (Acer, Intel iGPU): screen
   off, unresponsive after resume; `mem_sleep` `[deep]`/S3. Next: capture
   `journalctl -b -1 -k`, compare against stock `linux`.
3. **Installer secrets** (v0.2 blocker, deliberate dev convenience): WireGuard
   key, WiFi PSK, credentials — out before opening to power users. Rotate burned
   WG key; drop `Hidden=true`.

## Next steps

- **VM launcher (Faza 1 gate):** instance overlay on app-web + `-kernel` +
  AF_VSOCK + waypipe host-side systemd user service. First actual VM from the
  three-layer chain.
- Kernel sub-pipeline → `out/linux-image-katmate-microvm-amd64.deb` (hook).
- vm-agent build → `out/vm-agent` (hook, C, gcc).
- Reinstall Dell from current installer.
- `katmate-update` MVP (Faza 2); unblocks RTL8125 passthrough (Faza 3).

## Deferred (tracked, not now)

- Installer hardening: reflector + ParallelDownloads before pacstrap (mirror
  "fails first try" pattern, seen 3×); package verification after pacstrap
  (atomic pacstrap silently dropped qemu once). Own commit, after base is synced.
- `/dev/vsock` is `root root` not `root kvm` → udev rule, decided with launcher
  privilege model (user vs root).
- `vhost_net` autoload → add when NetVM TAP/bridge lands (don't preload now).

## Open questions

ADR-012 (image distribution), ADR-013 (image signing) — still Proposed.
vm-agent RUN whitelist → per-manifest (vault needs keepassxc, not on current
global whitelist; Faza 4).

## Session log notes

- 2026-06-14: installer sync (b1f1ede); discovered git installer was 2 generations
  behind docs (GRUB era). Root cause of yesterday's cryptroot/GRUB confusion:
  correct systemd-boot scripts lived only in project knowledge, never committed.
  Acer confirmed clean (LVM-on-LUKS, lvm2 in HOOKS correct). `less` not in Arch
  base — use `git --no-pager` or install it.
