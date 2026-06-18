# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.

**Last updated:** 2026-06-18
**Milestone:** v0.2 (in development)

## Current focus

Merging two parallel development lines onto MINIS/UM870 (the VT-d host):
1. **MINIS line** — the working compartmentalization stack (netVM, personalVM,
   segmented networking, host desktop). This is the documented project plus the
   live system confirmed by direct inspection.
2. **Acer line** — GUI/desktop layer (Hyprland + CYBRland theme + Plymouth).
   Hyprland/CYBRland layer now ported to MINIS (2026-06-18); Plymouth theme
   still pending.

Direction set: target IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## Confirmed live state (MINIS/UM870, inspected 2026-06-17, desktop 2026-06-18)

**Host** (`archlinux`, Arch):
- Kernel **`linux` 7.0.12-arch1-1** — migration to `linux-hardened` pending
  (opportunistic, not blocking). While on stock `linux`, `aio=io_uring` works
  and is in use; `aio=threads` adaptation applies only once hardened lands.
- Ryzen 7 8745H, ~30 GiB RAM, 12 GiB swap. AMD-Vi present; vfio in use.
- LUKS2 → `cryptroot` → `vg0`: `root` 100G, `swap` 12G, `vm_pool` thin pool
  700G (tmeta 88M). In-pool: `vm_personal_home` 40G, `vm_tpl_all_root_golden`
  30G, `vm_tpl_debian` 10G. Out-of-pool template/root LVs: `vm_tpl_all_root`,
  `vm_tpl_personal_root`, `vm_tpl_net_root` (+ others).
- Desktop: **Hyprland + CYBRland** (dual head DP-3 / HDMI-A-1), kitty, fish,
  micro. Sway config retained as fallback — it is the ADR-016 default-profile
  target (not yet built out).
- waypipe-client: socket-activated `--user` service, vsock port 1024,
  multiplexes per peer CID (one `client-conn` per connection).
- Host nft: input policy drop; `tcp dport 22 accept` is open (dev convenience,
  not a permanent policy — to be reviewed before power-user release).
- Bridge `br-personal` carries `tap-personal` (personalVM) + `tap0` (netVM
  inner leg).

**netVM** (CID 3, Debian 13 trixie, kernel 6.12.69+deb13):
- Launched as host `--user` service `netVM.service` → `/home/host/net.con`.
- **q35** machine (not microvm), 1 vCPU, ~1 GiB RAM.
- **USB-NIC passthrough**: `usb-host vendorid=0x0bda productid=0x8153` (Realtek
  r8152) → guest `enx00e04c3961b8`, gets `10.3.1.3/24`, default gw `10.3.1.1`.
- **WireGuard / ProtonVPN** terminates here (`proton` iface `10.2.0.2/32`,
  wg-quick), NAT masquerade out `proton`, ip_forward=1.
- Inner segment leg `enp0s4` (virtio via tap0) `10.100.1.1/32`.
- nft: input drop + wg port 51820; forward limited to segment↔proton.
- vm-agent runs here (non-GUI: SHUTDOWN, file transfer, control).
- 9p `hostshare` mount of `/home/host`.

**personalVM** (CID 4, Debian 13 trixie, kernel 6.12.69+deb13):
- **microvm** machine, 2 vCPU, 4G (hugepages-backed).
- `eth0` (virtio via tap-personal) `10.100.1.2/32`, gw `10.100.1.1` (netVM
  inner leg), DNS `10.2.0.1` → routed through netVM/Proton.
- vm-agent (user service) → waypipe server → firefox-esr tree; logind creates
  `/run/user/1000` at boot, no interactive login needed.
- nft empty (relies on netVM for filtering).
- Disks: vda 10G root (qcow2 overlay), vdb 40G /home (raw LV).

**Desktop layer (CYBRland/Hyprland — ported & working 2026-06-18):**
CYBRland Hyprland config now operational on MINIS dual-head (DP-3 + HDMI-A-1).
The port was not blocked by blur/shadow/driver/version (all ruled out) but by a
recurring pattern: **Acer-specific hardcodes that did not survive the move.**
Fixes applied (all in `~/.config/`):
- **waybar read the wrong config file** — a hand-made `config` shadowed the
  CYBRland `config.jsonc` (waybar prefers `config` over `config.jsonc`).
  Renamed `config` → `config.disabled`.
- **`config.jsonc` output = `eDP-1`** (Acer's panel, absent on MINIS) — bar
  rendered to a non-existent monitor. Removed `output` line → bar on both heads.
- **persistent-workspaces bound to `eDP-1`** → `"*"` (workspaces 1–4 on both
  bars).
- **`/home/sch` hardcoded paths** (CYBRland author) in `modules.jsonc`
  brightness scripts → `sed` to `/home/host`.
- **volume module** — event-driven `pulseaudio` module raced wireplumber at
  start (empty until clicked). Replaced with `custom/volume` polling
  `wpctl get-volume` (interval 2s, U+F028 glyph, `pavucontrol` on left-click,
  `wpctl set-mute` on right-click, scroll for volume). Installed `jq`,
  `wireplumber`, `pavucontrol`.
- **dropped laptop-only modules** (battery, bluetooth, custom/brightness) —
  MINIS is a desktop; these had no data source.
- Desktop config lives **only in `~/.config/`** — not yet in git.
- Known quirk: `hyprctl reload` does not fully apply changes here; only a full
  TTY session restart does. waybar autostart wired in `hypr/hyprland.conf`
  (`$bar = waybar`) + `hypr/scripts/services`.
- **Decision: ADR-016** — two desktop profiles, shared visual layer, Sway
  default + Hyprland optional. Current build: Hyprland. Sway profile: recorded
  target, not built, not next step.

## Confirmed Acer-line assets (inspected 2026-06-17)

**Desktop layer** — ported to MINIS 2026-06-18 (Hyprland/CYBRland working;
Plymouth still pending):
- greetd + tuigreet login manager
- Hyprland 0.55.2 + **CYBRland** theme (`github.com/scherrer-txt/cybrland`)
  — `~/.config/hypr/{hyprland.conf,theme.conf,vars.conf,plugins/,scripts/}`
- hypridle, hyprlock, hyprpaper, hyprpicker, pyprland
- Rofi (launcher, powermenu, clipboard, wallpaper, keybindings, screenshot,
  emoji scripts)
- waybar, swaync (notifications)
- Plymouth "katmate" theme (boot splash) — **still to transfer**
- kitty, yazi, obsidian, fish, micro

**Build pipeline** (already in git):
- `build/config.sh` — Debian trixie, snapshot pin `20260601T000000Z`,
  waypipe v0.11.0, bare ext4 on whole NBD device
- `build/lib.sh` — nbd_connect/mount/chroot helpers, cleanup trap

**Acer hardware note:** N4200 (not N4000 as previously documented), VT-x only
— confirmed not a target platform post ADR-015.

## Open problems

1. **Desktop config not in git.** CYBRland/Hyprland desktop layer is live on
   MINIS but lives only in `~/.config/`. Bring the shared visual layer into the
   repo. Plymouth theme port still pending. (Migration itself: done — ADR-016.)
2. **Kernel migration `linux` → `linux-hardened`** on MINIS (opportunistic).
   Re-validate io_uring/aio on hardened; suspend/resume regression to recheck.
3. **Installer secrets** (v0.2 blocker): WireGuard key, WiFi PSK, credentials —
   must be removed before power-user release. Rotate burned WG key; drop
   `Hidden=true`.
4. **SSH open on MINIS host** (`tcp dport 22 accept`) — dev convenience, not
   shipped policy; close or gate before power-user release.
5. **"Enoch OS"** description string in live `vm-agent.service` (personalVM) —
   pre-alpha artifact, remove.
6. **Acer-hardcode sweep** across remaining CYBRland configs (rofi / hypr /
   hyprlock): `grep -rn 'eDP-1\|/home/sch' ~/.config/` — catch them all at once
   rather than one per session.

## Next steps

- Plymouth theme port (Acer → MINIS); bring desktop config into git.
- Resume vm-agent design block (protocol.h source-of-truth for CID/port,
  `allowed_path` traversal fix, socket/bind/listen error handling).
- Kernel migration to linux-hardened on MINIS (opportunistic).
- Secrets removal from installer (v0.2 blocker).

## Notes

- Doc reconciliation pass completed 2026-06-17: ARCHITECTURE (networking,
  desktop, hardware floor), INSTALL (HW matrix N4000→N4200, postinstall VSOCK
  module), SECURITY-MODEL (VPN gap #3 resolved, SSH gap added), ROADMAP (v0.3
  networking items moved to live state).
- vm-agent runs on all domains (GUI and non-GUI) as the general control channel.
- netVM uses USB-NIC passthrough (r8152), not PCIe RTL8125 — RTL8125 vfio
  path documented in memory as blocked; live system uses the simpler USB path.
- Desktop: two-profile model decided (ADR-016). "click N → all monitors to
  workspace N" still needs a script (per-monitor by default in both
  compositors).
