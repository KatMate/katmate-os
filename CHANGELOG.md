# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/). Versions are
project milestones (see [ROADMAP.md](ROADMAP.md)). Dates marked *TBD* should
be backfilled from git history.

## [0.2.0] — Unreleased (in development)

### Added
- vm-agent in C: `PING`, `RUN` (whitelist: firefox-esr, foot, nautilus),
  `FILEGET`/`FILEPUT` (path whitelist, size limits), `SHUTDOWN`
- File transfer over AF_VSOCK
- Template model: versioned immutable base image + per-AppVM overlays;
  `katmate-update` concept with pacman hook trigger (ADR-007)
- Installer: proportional LVM sizing (root 15% clamped 20–60G, swap = RAM,
  thin pool remainder with computed metadata), CPU vendor → ucode
  autodetection, verification block, cleanup trap with `KEEP_MOUNTS` debug mode
- Desktop layer on development machines: greetd/tuigreet, Hyprland 0.55.2,
  Plymouth "katmate" theme (spinner, split password prompt sprites), pacman
  hook for Hyprland plugin rebuilds — not yet installer-integrated

### Changed
- Bootloader: GRUB → systemd-boot (`timeout 0`, `editor no`) (ADR-006)
- Host kernel: `linux` → `linux-hardened` (ADR-004)
- QEMU disk I/O: `aio=io_uring` → `aio=threads` (io_uring disabled by the
  hardened kernel)
- Guest waypipe: 0.9.2 (Debian package) → 0.11.0 built from source,
  version-locked to host (ADR-008)

### Fixed
- Waypipe clipboard crash guest↔host: compression negotiation mismatch from
  version skew; build required `bindgen` (lz4/zstd feature gates) and
  `cargo fetch` before meson (`--frozen` wrapper) (ADR-008)
- Plymouth: password prompt layout (independent sprite centering), throbber
  hidden during password entry, manual zero-padding workaround for scripting
  limitations
- Hyprland: startup log noise suppressed via VT ANSI escapes before exec;
  plugin build failures after version bumps (hyprpm update + pacman hook)

### Known issues
- Suspend/resume failure under `linux-hardened` on a development laptop
  (screen off, unresponsive after resume; S3 confirmed) — diagnosis pending
- Secrets hardcoded in installer scripts (WG private key, WiFi PSK, default
  credentials) — v0.2 blocker, see SECURITY-MODEL gap #1
- PCI passthrough limitations on some 2.5 GbE adapters

## [0.1.0] — date TBD

### Added
- Arch installer: GPT, EFI, LUKS encryption, ext4, Arch bootstrap, GRUB
- Custom MicroVM kernel (virtio-blk/net/vsock, ext4, tmpfs, namespaces)
- Debian MicroVM with direct kernel boot
- AF_VSOCK host↔guest communication channel
- Waypipe over VSOCK proof of concept
- Base services: systemd-networkd/-resolved, iwd, nftables, WireGuard
