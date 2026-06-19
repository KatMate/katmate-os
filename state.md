# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.

**Last updated:** 2026-06-17
**Milestone:** v0.2 (in development)

## Current focus

Merging two parallel development lines onto MINIS/UM870 (the VT-d host):
1. **MINIS line** — the working compartmentalization stack (netVM, personalVM,
   segmented networking, host desktop). This is the documented project plus the
   live system confirmed by direct inspection.
2. **Acer line** — GUI/desktop layer (Hyprland + CYBRland theme + Plymouth).
   Inspection completed 2026-06-17; assets to migrate to MINIS.

Direction set: target IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## Confirmed live state (MINIS/UM870, inspected 2026-06-17)

**Host** (`archlinux`, Arch):
- Kernel **`linux` 7.0.12-arch1-1** — migration to `linux-hardened` pending
  (opportunistic, not blocking). While on stock `linux`, `aio=io_uring` works
  and is in use; `aio=threads` adaptation applies only once hardened lands.
- Ryzen 7 8745H, ~30 GiB RAM, 12 GiB swap. AMD-Vi present; vfio in use.
- LUKS2 → `cryptroot` → `vg0`: `root` 100G, `swap` 12G, `vm_pool` thin pool
  700G (tmeta 88M). In-pool: `vm_personal_home` 40G, `vm_tpl_all_root_golden`
  30G, `vm_tpl_debian` 10G. Out-of-pool template/root LVs: `vm_tpl_all_root`,
  `vm_tpl_personal_root`, `vm_tpl_net_root` (+ others).
- Desktop: **Sway** (dual head DP-3 / HDMI-A-1), kitty, fish, micro.
  Target: Hyprland + CYBRland (migration from Acer pending).
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

## Disk model (live vs target)

**Live (inspected 2026-06-19, MINIS):** two-level, not yet the target chain.

- `vm_tpl_all_root` (31G), `vm_tpl_personal_root` / `vm_tpl_net_root` /
  `vm_tpl_work_root` (10G each): **linear** LVs, RO-frozen (`-ri`, `blockdev
  --getro` = 1), **out of pool**, no snapshot/origin relation between them —
  current app layers are standalone hard-copies, not snapshots of a base.
- `vm_tpl_all_root_golden` (30G): the only **thin** RO base
  (`Vri`, in `vm_pool`), currently **detached** — not the origin of any live
  app layer.
- Per-VM RW delta: `vm_personal_overlay.qcow2` (backing =
  `/dev/vg0/vm_tpl_personal_root`, format raw, ~2.78G used),
  `vm_net_overlay.qcow2` (backing = `vm_tpl_net_root`, ~182M).
- Per-VM home: raw thin LV in `vm_pool` (`vm_personal_home` 40G;
  `vm_work_home` 40G linear, out of pool).

So the live read path is **linear RO LV ← qcow2 delta** — fastest possible
system read (single device-map lookup, no qcow2 chain walk under the OS),
which is why it was built this way for the two current domains.

**Target (ADR-010, revised):** three-level LVM-thin chain:
`all_root` (thin, RO base) ← `app-<type>_root` (thin **snapshot** of
`all_root`, RO-frozen) ← per-instance qcow2 RW delta. Moves block sharing
across N app layers into the pool (one base stored once) at the cost of a
small thin-metadata indirection on reads — worth it once N > 2 domains.
The thin-snapshot link base→app is **not yet implemented**; see Open
problems.

## Confirmed Acer-line assets (inspected 2026-06-17)

**Desktop layer** — to migrate to MINIS:
- greetd + tuigreet login manager
- Hyprland 0.55.2 + **CYBRland** theme (`github.com/scherrer-txt/cybrland`)
  — `~/.config/hypr/{hyprland.conf,theme.conf,vars.conf,plugins/,scripts/}`
- hypridle, hyprlock, hyprpaper, hyprpicker, pyprland
- Rofi (launcher, powermenu, clipboard, wallpaper, keybindings, screenshot,
  emoji scripts)
- waybar, swaync (notifications)
- Plymouth "katmate" theme (boot splash) — to transfer alongside Hyprland
- kitty, yazi, obsidian, fish, micro

**Build pipeline** (already in git):
- `build/config.sh` — Debian trixie, snapshot pin `20260601T000000Z`,
  waypipe v0.11.0, bare ext4 on whole NBD device
- `build/lib.sh` — nbd_connect/mount/chroot helpers, cleanup trap

**Acer hardware note:** N4200 (not N4000 as previously documented), VT-x only
— confirmed not a target platform post ADR-015.

## Open problems

1. **Desktop migration Acer → MINIS.** CYBRland Hyprland config + Plymouth
   theme to port; Sway replaced by Hyprland. Requires Hyprland + deps install
   on MINIS; greetd swap.
2. **Kernel migration `linux` → `linux-hardened`** on MINIS (opportunistic).
   Re-validate io_uring/aio on hardened; suspend/resume regression to recheck.
3. **Installer secrets** (v0.2 blocker): WireGuard key, WiFi PSK, credentials —
   must be removed before power-user release. Rotate burned WG key; drop
   `Hidden=true`.
4. **SSH open on MINIS host** (`tcp dport 22 accept`) — dev convenience, not
   shipped policy; close or gate before power-user release.
5. **"Enoch OS"** description string in live `vm-agent.service` (personalVM) —
   pre-alpha artifact, remove.
6. **Disk model not at target** (ADR-010): app layers are standalone linear RO
   hard-copies, not thin snapshots of `all_root`; `all_root_golden` thin base
   is detached. Target is `lvcreate --snapshot` base→app + RO freeze
   (ADR-011). Migration: rebuild base as thin `all_root`, re-create each app
   layer as a frozen thin snapshot, re-point qcow2 deltas. Home LVs untouched.

## Next steps

- Port CYBRland desktop layer + Plymouth theme from Acer to MINIS.
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
