# Installation

## Requirements

- x86-64 UEFI machine with VT-d / AMD-Vi (IOMMU required)
- Disk ≥ 32 GB (enforced by the installer)
- RAM: 8 GB practical minimum (low-end reference class), more for multiple concurrent VMs
- Arch Linux live ISO environment, online over UTP (archiso DHCP) or, failing
  that, a Wi-Fi network the installer can join
- The whole `installer/` directory, copied as is: the scripts share `lib/`

> **Do not mount anything at `/mnt`** before running the installer (e.g. the
> script USB) — the installer requires `/mnt` free and will abort otherwise.
> Use `/installer` for the USB.

## Preflight

`installer/preflight.sh` checks the hardware **before** `install.sh`, from the
same live environment, and changes nothing: no module is loaded, no driver is
bound, nothing is installed. It covers CPU virtualisation, UEFI, KVM, the
IOMMU (ACPI table, activity, interrupt remapping), every IOMMU group, the
isolation of each Ethernet, Wi-Fi and USB controller, NIC identity (MAC,
slot path, udev path), the GPU, RAM, CPUs and disks.

**Boot the live ISO with the IOMMU on, or the result is not meaningful.** On
Intel, edit the ISO's boot entry and append `intel_iommu=on`. On AMD the IOMMU
is on by default (`amd_iommu=on` is not a valid option; the kernel logs it as
unknown). If the IOMMU is off because of the boot line, the preflight says so,
distinctly from a firmware with VT-d / AMD-Vi disabled.

**It writes one file, and it needs a writable place for it.** The Arch ISO
medium is read-only, and the live system's `/tmp` is in RAM and lost at
reboot. Run it as root from the script USB, if that stick is mounted
read-write:

```
cd /installer
bash preflight.sh
```

or write to `/tmp` and copy the file to a second stick before rebooting:

```
bash /installer/preflight.sh -o /tmp/preflight.txt
```

The default name is `katmate-preflight-<hostname>-<UTC time>.txt` in the
current directory. If the file cannot be created, or already exists, the
preflight stops before any check.

**Reading the result.** Every check prints `PASS`, `WARN`, `FAIL` or
`SKIPPED` with its evidence quoted under it, and a summary ends the file:

| Overall | Meaning | Exit |
|---|---|---|
| `GO` | every check passed | 0 |
| `GO-WITH-WARNINGS` | no failure; each `WARN` is for the operator to rule on (e.g. a controller that is not isolable) | 1 |
| `NO-GO` | at least one `FAIL` | 2 |
| `PREFLIGHT ABORTED — NO VERDICT` | the preflight could not run to the end; there is no result | 3 |

## What `install.sh` does

1. **Sanity checks** — `/mnt` unoccupied, all required tools present
   (`curl`, `ip`, `openssl` and `loadkeys` among them; `iwctl` only if Wi-Fi
   is needed).
2. **Keymap** — prompted, default `us`, checked against `localectl
   list-keymaps` when available, and loaded into the live console at once,
   so every passphrase that follows — the LUKS one above all — is typed under
   the layout the installed system's initramfs will use.
3. **Network** — a check, not a configuration. Online test over HTTPS
   (`curl` to `archlinux.org`, 5 s; ICMP is not used). If online, the
   interface carrying the default route is logged and Wi-Fi is skipped. If
   offline, an iwd station device is required (otherwise: connect UTP), SSID
   and passphrase are prompted (passphrase not echoed), a visible and then a
   hidden connect is tried, and the HTTPS check is repeated. Nothing about
   the install-time network is written to the target.
4. **Identity** — hostname (RFC 1123 label), username
   (`^[a-z_][a-z0-9_-]{0,31}$`, not `root`) and password (twice, not echoed,
   non-empty). The password is hashed in the live system
   (`openssl passwd -6`); root gets the same password as the user.
5. **CPU detection** — vendor → `amd-ucode` / `intel-ucode` automatically.
6. **Disk selection** — interactive, with an explicit wipe confirmation.
7. **Proportional layout** (computed, then confirmed interactively):
   - ESP: 512M
   - root: 15% of disk, clamped to 20–60 G
   - swap: sized = RAM (rounded up)
   - thin pool: remainder; metadata 1% of pool, clamped 64M–1G;
     aborts if the pool would be < 8 G
8. **Partitioning** — GPT: ESP + LUKS partition; `partprobe`.
9. **Encryption & LVM** — LUKS2 (`cryptlvm`) → `vg0` with `root`, `swap`, and
   a thin pool (single `lvcreate --type thin-pool -l 100%FREE
   --poolmetadatasize`, so LVM sizes data + metadata + pmspare together).
10. **Filesystems & mount** — FAT32 ESP at `/boot`, ext4 root, swap on.
11. **Mirror refresh** — `ParallelDownloads = 5`; `reflector`
   (CH/DE/AT, https, sorted by rate) refreshes the mirrorlist before pacstrap,
   with a static geo-close fallback. Mitigates flaky upstream mirrors.
12. **Pacstrap** — `base linux-hardened linux-hardened-headers linux-firmware
   <ucode> lvm2 efibootmgr cryptsetup iwd micro sudo nftables wireguard-tools
   qemu-full`. (`iwd` is installed but not enabled.)
13. **Base config** — fstab, hostname, timezone `Europe/Zurich`, wired DHCP
    network unit, wheel sudoers.
14. **Handoff** — writes `/root/install.env` (username, LUKS UUID, ucode,
    keymap; no secrets), copies and runs `postinstall.sh` inside the chroot,
    then removes `install.env` — also on failure, from the exit trap.
15. **Passwords** — the hash is piped to `chpasswd -e` in the chroot for root
    and the user; it reaches the target only in `/etc/shadow`.
16. **resolv.conf fix** — symlinks to `stub-resolv.conf` *after* leaving the
    chroot (deliberately not touched inside it).
17. **systemd-boot** — `bootctl install`; `loader.conf` with `timeout 0`,
    `editor no`; boot entry with
    `cryptdevice=UUID=<luks>:cryptlvm root=/dev/vg0/root rw quiet loglevel=3`
    and the vendor's IOMMU parameter ([ADR-040](DECISIONS.md#adr-040)).
18. **Verification** — asserts EFI binary, boot entry, kernel, initramfs, the
    cryptdevice string and the IOMMU parameters; a `$6$` hash in
    `/etc/shadow` for root and the user; no `/root/install.env`; prints the
    boot file tree.

Debugging aid: `KEEP_MOUNTS=yes ./install.sh` leaves `/mnt` mounted for
inspection; otherwise a cleanup trap unmounts and deactivates `vg0`/`cryptlvm`
even on failure.

## What `postinstall.sh` does

- Hardware clock sync; creates the user in `wheel` (refused if the name
  already exists in the target); passwords are set by `install.sh` afterwards
- Enables `systemd-networkd`, `systemd-resolved`
- No Wi-Fi profile and no VPN on the host. *(Until 2026-10-04 it wrote an iwd
  PSK profile and a ProtonVPN WireGuard config with `wg-quick@proton`; the
  R164 correction of 2026-10-03 recorded why the latter was wrong.)* A VPN is
  an optional, user-supplied WireGuard config in netVM
  ([ADR-037](DECISIONS.md#adr-037)).
- Locale: `en_US.UTF-8` only (`LANG`); console keymap from the install-time
  prompt (`/etc/vconsole.conf`)
- nftables: default-drop ruleset (see [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component)), enabled
- `vhost_vsock` module autoload via `/etc/modules-load.d/katmate-vsock.conf`
  (AF_VSOCK sole host↔guest channel per [ADR-003](DECISIONS.md#adr-003))
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
| MINISFORUM UM870 | Ryzen 7 8745H | 32 GB DDR5 | main development system (VT-d) |
| MSI Cubi N6000 | Pentium N6000 | 32 GB DDR4 | bare-metal install test target (VT-d) |
| Dell Latitude 3120 | Pentium N6000 | 8 GB | live install test target (VT-d) |
| Acer ES1-633 | Pentium N4200 | 8 GB | dev scratch |

Known hardware limitation: PCI passthrough is problematic on some 2.5 GbE
adapters; USB-NIC passthrough (r8152) is the working alternative for NetVM.

## Caveats (current installer state)

- **Hardcoded secrets** — removed 2026-10-04: hostname, user and password are
  prompted, and no Wi-Fi or WireGuard secret is in the scripts. *(The R167
  note of 2026-10-03 recorded the WG key and Wi-Fi passphrase as rotated
  (R162); the literals remain in git history, burned.)*
  [SECURITY-MODEL.md, gap #1](SECURITY-MODEL.md#known-gaps-tracked) is not
  updated by this change.
- **Desktop layer not yet installed** — greetd/Hyprland/Plymouth are a manual
  post-step on development machines. Integration will require `kms` in the
  mkinitcpio `HOOKS`.
- **Hibernation non-functional** — swap is sized = RAM, but there is no
  `resume` hook / kernel parameter. Either add resume support or shrink swap;
  on 32 GB machines this is currently dead disk space.
- **Version header** — aligned 2026-10-04: the script header names the
  milestone (v0.2), not a script iteration counter.
