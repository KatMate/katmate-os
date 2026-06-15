# Installation

## Requirements

- x86-64 UEFI machine with VT-x / AMD-V
- Disk ≥ 32 GB (enforced by the installer)
- RAM: 8 GB practical minimum (low-end reference class), more for multiple concurrent VMs
- Arch Linux live ISO environment, WiFi or wired connectivity
- The two scripts from `installer/`: `install.sh` (run in the live environment)
  and `postinstall.sh` (invoked automatically via `arch-chroot`)

> **Do not mount anything at `/mnt`** before running the installer (e.g. the
> script USB) — the installer requires `/mnt` free and will abort otherwise.
> Use `/installer` for the USB.

## What `install.sh` does

1. **Sanity checks** — `/mnt` unoccupied, all required tools present.
2. **WiFi** — connects via iwd (currently hardcoded SSID/PSK — see Caveats).
3. **CPU detection** — vendor → `amd-ucode` / `intel-ucode` automatically.
4. **Disk selection** — interactive, with an explicit wipe confirmation.
5. **Proportional layout** (computed, then confirmed interactively):
   - ESP: 512M
   - root: 15% of disk, clamped to 20–60 G
   - swap: sized = RAM (rounded up)
   - thin pool: remainder; metadata 1% of pool, clamped 64M–1G;
     aborts if the pool would be < 8 G
6. **Partitioning** — GPT: ESP + LUKS partition; `partprobe`.
7. **Encryption & LVM** — LUKS2 (`cryptlvm`) → `vg0` with `root`, `swap`, and
   a thin pool (single `lvcreate --type thin-pool -l 100%FREE
   --poolmetadatasize`, so LVM sizes data + metadata + pmspare together).
8. **Filesystems & mount** — FAT32 ESP at `/boot`, ext4 root, swap on.
9. **Mirror refresh** — `ParallelDownloads = 5`; `reflector`
   (CH/DE/AT, https, sorted by rate) refreshes the mirrorlist before pacstrap,
   with a static geo-close fallback. Mitigates flaky upstream mirrors.
10. **Pacstrap** — `base linux-hardened linux-hardened-headers linux-firmware
   <ucode> lvm2 efibootmgr cryptsetup iwd micro sudo nftables wireguard-tools
   qemu-full`.
11. **Base config** — fstab, hostname, timezone `Europe/Zurich`, wired DHCP
    network unit, wheel sudoers.
12. **Handoff** — writes `/root/install.env`, copies and runs `postinstall.sh`
    inside the chroot.
13. **resolv.conf fix** — symlinks to `stub-resolv.conf` *after* leaving the
    chroot (deliberately not touched inside it).
14. **systemd-boot** — `bootctl install`; `loader.conf` with `timeout 0`,
    `editor no`; boot entry with
    `cryptdevice=UUID=<luks>:cryptlvm root=/dev/vg0/root rw quiet loglevel=3`.
15. **Verification** — asserts EFI binary, boot entry, kernel, initramfs and
    the cryptdevice string exist; prints the boot file tree.

Debugging aid: `KEEP_MOUNTS=yes ./install.sh` leaves `/mnt` mounted for
inspection; otherwise a cleanup trap unmounts and deactivates `vg0`/`cryptlvm`
even on failure.

## What `postinstall.sh` does

- Hardware clock sync; root and user passwords; user in `wheel`
- Enables `systemd-networkd`, `systemd-resolved`, `iwd`
- iwd: PSK profile (AutoConnect, currently `Hidden=true`) and `main.conf` with
  `EnableNetworkConfiguration=true`
- Locales: `LANG=en_US.UTF-8`, regional `LC_*` set to `sl_SI.UTF-8`;
  console keymap `slovene`
- nftables: default-drop ruleset (see [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component)), enabled
- WireGuard: ProtonVPN profile + `wg-quick@proton` enabled (transitional —
  target is NetVM, [ADR-009](DECISIONS.md#adr-009))
- mkinitcpio: `HOOKS=(base udev autodetect keyboard keymap modconf block
  encrypt lvm2 filesystems fsck)` → `mkinitcpio -P`

## Resulting disk layout

| Device | FS | Mount | Size |
|---|---|---|---|
| `p1` (ESP) | FAT32 | `/boot` | 512M |
| `vg0/root` | ext4 | `/` | 15% of disk (20–60 G) |
| `vg0/swap` | swap | — | = RAM |
| `vg0/thinpool` | thin pool | — | remainder (VM storage) |

## Tested / reference hardware

| Machine | CPU | RAM | Role |
|---|---|---|---|
| MINISFORUM UM870 | Ryzen 7 8745H | 32 GB DDR5 | main development system |
| MSI Cubi N6000 | Pentium N6000 | 32 GB DDR4 | bare-metal install test target |
| Acer ES1-633 | Celeron N4000 | 8 GB | low-end reference (alpha floor) |
| Dell Latitude 3120 | Pentium N6000 | 8 GB | live test target |

Known hardware limitation: PCI passthrough is problematic on some 2.5 GbE
adapters.

## Caveats (current installer state)

- **Hardcoded secrets** — hostname/user/password defaults, WiFi SSID+PSK and a
  WireGuard private key are embedded in the scripts. These must move to
  install-time prompts / generation (`wg genkey`); the committed WG key is
  burned and must be rotated. Tracked as a v0.2 blocker
  ([SECURITY-MODEL.md, gap #1](SECURITY-MODEL.md#known-gaps-tracked)).
- **Desktop layer not yet installed** — greetd/Hyprland/Plymouth are a manual
  post-step on development machines. Integration will require `kms` in the
  mkinitcpio `HOOKS`.
- **Hibernation non-functional** — swap is sized = RAM, but there is no
  `resume` hook / kernel parameter. Either add resume support or shrink swap;
  on 32 GB machines this is currently dead disk space.
- **Version header** — the installer script header (v0.3) is a script
  iteration counter, not the project milestone (v0.2); to be aligned at the
  next `install.sh` edit.
