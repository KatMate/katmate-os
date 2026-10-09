# Installation

## Requirements

- x86-64 UEFI machine with VT-d / AMD-Vi (IOMMU required)
- **RAM: 16 GB** (refused below; the check allows for what firmware and an
  integrated GPU reserve, so `MemTotal` must be at least 14 GiB). All guests
  together commit up to 13 GiB (netVM 1, `app_web` 4, and four AppVMs at 2).
  memfd memory without prealloc is allocated on use, so the sum is an upper
  bound, not a requirement (netVM's 1 GiB is the exception: VFIO pins all of
  it at start). No hugepage pool is reserved. **UNVERIFIED** until measured
  on MINIS.
- Disk ≥ 32 GB, and in practice more: after root (15 %, 20–60 G) and swap
  (= RAM), the thin pool must hold the images plus 8 GiB, and netVM's
  linear LV sits beside it. The installer computes this before it touches
  the disk and refuses a disk that is too small.
- **One PCI Ethernet card for netVM.** It is passed through to netVM and the
  host keeps no network of its own after installation. A wireless card cannot
  be assigned in the alpha.
- Arch Linux live ISO environment, online over UTP (archiso DHCP) or, failing
  that, a Wi-Fi network the installer can join (pacstrap needs a network,
  and so does a release fetched from a URL)
- A KatMate release (below), either on a USB stick or reachable as GitHub
  release assets

> **Do not mount anything at `/mnt`** before running the installer (e.g. the
> script USB) — the installer requires `/mnt` free and will abort otherwise.
> Use `/installer` for the USB.

## The release, and the first verification

A release is a flat set of files: `katmate-os-<tag>.tar.gz` (a `git archive`
of the release tag, which holds the installer), the guest images
(`*.img.zst`), their metadata, the kernels, the host binaries, `release.env`
and `images.list`. **`SHA256SUMS`** lists every file, and **`SHA256SUMS.asc`**
is its detached signature by the KatMate release key, fingerprint

```
3F49 AE51 4562 ACD3 FF9D  6049 F884 1B7B 3D3A B436
```

The installer verifies all of this itself, but it is itself in the archive
it verifies: the trust anchor is a check **you** make once, by hand, before
running anything. Get the public key from a source you trust (the release
also carries it as `installer/katmate-release.asc` inside the archive), then,
in the directory holding the release files:

```
gpg --import katmate-release.asc
gpg --fingerprint 3F49AE514562ACD3FF9D6049F8841B7B3D3AB436   # compare with the line above
gpg --verify SHA256SUMS.asc SHA256SUMS                         # "Good signature from KatMate"
sha256sum -c --ignore-missing SHA256SUMS                       # the archive: OK
tar -xzf katmate-os-<tag>.tar.gz -C /root
cd /root/katmate-os-<tag>
```

Run the installer only from that extracted archive. It compares the tree it
runs from with the signed archive and refuses on any difference, so a clone
or an edited copy will not install.

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

Run as root, from the extracted archive: `bash installer/install.sh`.

1. **Sanity checks** — `/mnt` unoccupied, all required tools present
   (`curl`, `gpg`, `zstd`, `openssl` and `loadkeys` among them; `iwctl` only
   if Wi-Fi is needed).
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
4. **Release** — the source is a directory or a URL (default: the latest
   GitHub release; `KM_RELEASE_SRC` overrides the prompt). `SHA256SUMS.asc`
   must verify with the release key alone, by the pinned fingerprint; the
   running tree must equal the signed archive; `netvm.meta` must record
   `NETVM_ROOT_UNLOCKED=no`; `images.list` must carry exactly the five
   images. Every file is checked against `SHA256SUMS` before it is used.
5. **RAM** — refused below 16 GB, before any disk is touched.
6. **Identity** — hostname (RFC 1123 label), username
   (`^[a-z_][a-z0-9_-]{0,31}$`, not `root`) and password (twice, not echoed,
   non-empty), hashed in the live system (`openssl passwd -6`). **root gets
   no password and is locked**; administration is through `sudo` (wheel).
7. **Desktop keyboard layout** — XKB layout name(s) for sway (`si`, `de`,
   `si,us`; default `us`), separate from the console keymap, whose names
   differ.
8. **CPU detection** — vendor → `amd-ucode` / `intel-ucode`, the IOMMU
   parameter ([ADR-040](DECISIONS.md#adr-040)), and on AMD the `topoext`
   drop-in for netVM's unit.
9. **netVM's card** — every PCI Ethernet controller is listed (address,
   vendor:device, driver, IOMMU group); you pick one. A card whose
   vendor:device another Ethernet controller shares is refused; a card that
   shares its IOMMU group with other devices asks for confirmation.
10. **Disk selection** — interactive; the live boot stick is never offered.
11. **Proportional layout** (computed, then confirmed together with the wipe):
    - ESP: 512M
    - root: 15% of disk, clamped to 20–60 G
    - swap: sized = RAM (rounded up)
    - netVM: a linear LV of its image's size, plus 1 GiB left free in `vg0`
    - thin pool `vm_pool`: the rest; metadata 1% of it, clamped 64M–1G;
      refused if it cannot hold the images plus 8 GiB
12. **Partitioning, encryption, LVM, filesystems, mount** — GPT: ESP + LUKS2
    (`cryptlvm`) → `vg0` with `root`, `swap` and `vm_pool`; FAT32 ESP at
    `/boot`, ext4 root, swap on.
13. **Pacstrap** — with the live environment's mirror and download
    configuration as is (the installer does not change it): `base linux-hardened
    linux-hardened-headers linux-firmware <ucode> lvm2 e2fsprogs efibootmgr
    cryptsetup micro sudo nftables qemu-full plymouth`,
    and the desktop: `sway swaybg waybar swaync greetd greetd-tuigreet foot
    pipewire wireplumber pipewire-pulse brightnessctl playerctl grim slurp
    wl-clipboard wf-recorder libnotify xdg-utils polkit otf-geist-mono-nerd
    ttf-nerd-fonts-symbols`. No `iwd` and no `wireguard-tools`: the host
    has no network (until 2026-10-05 both were installed, `iwd` not enabled).
14. **Base config** — fstab, hostname, timezone `Europe/Zurich`, wheel
    sudoers. **No network profile**: no wired or Wi-Fi unit, and neither
    `systemd-networkd` nor `systemd-resolved` is enabled; the host's card
    belongs to netVM. *(Until 2026-10-05 this step wrote a wired DHCP unit,
    `20-wired.network`, and enabled both; operator ruling R11 removed them.)*
15. **Guest images** — each image is fetched into the target's `/var/tmp`
    (URL source), checked, written to its LV (`vm_tpl_foundation`,
    `vm_app_web`, `vm_app_office`, `vm_app_vault` thin, written sparse;
    `vm_sys_netvm` linear) and read back byte for byte; the four thin images
    are then made read-only.
16. **T2** — the images' metadata in `/var/lib/katmate/`, netVM's kernel and
    initrd in `/var/lib/katmate/netvm/`, the MicroVM kernel and its
    provenance sidecar (checked, [ADR-034](DECISIONS.md#adr-034)) in
    `/var/lib/katmate/kernels/`.
17. **T1** — `/etc/katmate/vm/{netvm,app_web,app_personal,app_work,app_vault,app_sandbox}.toml`
    from `installer/t1/`, `root:root 0644`, created and never overwritten
    ([ADR-032](DECISIONS.md#adr-032) §1).
18. **Home LVs and deltas** — `vm_<instance>_home`, 10G thin, ext4, `user/`
    `1000:1000 0700`; `/var/lib/katmate/instances/<instance>.qcow2` over the
    instance's app layer.
19. **KatMate host parts** — `host/usr/` (units and `/usr/lib/katmate/`),
    `ping-client` and the host `waypipe` (`/opt/katmate/bin/`); vfio-pci for
    the chosen card in `/etc/modprobe.d/katmate-vfio.conf`;
    `/etc/sudoers.d/katmate-launch` for the user; the `waypipe-client` user
    unit in `/etc/systemd/user/`.
20. **Desktop** — `/etc/sway/config` (with an empty `outputs.conf` and the
    keyboard include), waybar and its menus, `km-launch`, `km-shot`,
    `sway-session` and `sway-quiet` in `/usr/local/bin/`, wallpapers, greetd
    with the sway session entry, and the KatMate Plymouth theme.

    Monitors are configured by the user after install, in
    `/etc/sway/outputs.conf` ([HOST-CONFIG.md § 8](HOST-CONFIG.md#8-sway-output-configuration)).
    For example, to find the output names and rotate one output:

    ```
    swaymsg -t get_outputs -p | grep -E '^Output|Current mode'
    echo 'output HDMI-A-2 transform 90' | sudo tee /etc/sway/outputs.conf
    swaymsg reload
    ```

    `transform 270` rotates the other way. Where monitors overlap, `pos X Y`
    on each output sets its placement. See `man 5 sway-output`.
21. **Handoff** — writes `/root/install.env` (username, LUKS UUID, ucode,
    keymap; no secrets), copies and runs `postinstall.sh` inside the chroot,
    then removes both — `install.env` also on failure, from the exit trap.
22. **Password** — the hash is piped to `chpasswd -e` in the chroot for the
    user only; it reaches the target only in `/etc/shadow`.
23. **systemd-boot** — `bootctl install`; `loader.conf` with `timeout 0`,
    `editor no`; boot entry with
    `cryptdevice=UUID=<luks>:cryptlvm root=/dev/vg0/root rw quiet splash loglevel=3`
    and the vendor's IOMMU parameter.
24. **Verification** — the boot files, the IOMMU parameters, `splash`; the
    user's `$6$` hash and root's lock; no `install.env`; an empty
    `/etc/systemd/network`; every LV, T1 file, meta, kernel, delta, binary
    and desktop file; `katmate-sys-driver@netvm` and `greetd` enabled, and
    `waypipe-client` enabled globally.

Debugging aid: `KEEP_MOUNTS=yes ./install.sh` leaves `/mnt` mounted for
inspection; otherwise a cleanup trap unmounts and deactivates `vg0`/`cryptlvm`
even on failure. Downloaded release files are removed either way.

## What `postinstall.sh` does

- Hardware clock sync; creates the user in `wheel` (refused if the name
  already exists in the target); **locks root** (`passwd -l`); the user's
  password is set by `install.sh` afterwards
- Locale: `en_US.UTF-8` only (`LANG`); console keymap from the install-time
  prompt (`/etc/vconsole.conf`)
- nftables: default-drop ruleset (see [SECURITY-MODEL.md](SECURITY-MODEL.md#controls-by-component)), enabled
- `vhost_vsock` module autoload via `/etc/modules-load.d/katmate-vsock.conf`
  (AF_VSOCK sole host↔guest channel per [ADR-003](DECISIONS.md#adr-003))
- mkinitcpio: `HOOKS=(base udev autodetect modconf kms keyboard keymap
  plymouth block encrypt lvm2 filesystems fsck)`, `MODULES=(vfio_pci vfio
  vfio_iommu_type1)` → `mkinitcpio -P`. The LUKS passphrase is asked through
  the splash; if Plymouth fails, on the text console (UNVERIFIED until the
  Cubi gate)
- `visudo -c` over the new sudoers rule; enables `katmate-sys-driver@netvm`
  (netVM starts at boot; AppVMs start from the menu) and `greetd`; enables
  `waypipe-client` globally

## Resulting disk layout

| Device | FS | Mount | Size |
|---|---|---|---|
| `p1` (ESP) | FAT32 | `/boot` | 512M |
| `vg0/root` | ext4 | `/` | 15% of disk (20–60 G) |
| `vg0/swap` | swap | — | = RAM |
| `vg0/vm_sys_netvm` | ext4 (guest root) | — | netVM's image size (4G today), linear |
| `vg0/vm_pool` | thin pool | — | the rest, less 1 GiB free in `vg0` |
| `vg0/vm_tpl_foundation`, `vm_app_{web,office,vault}` | ext4 (guest roots), read-only | — | thin, in `vm_pool` |
| `vg0/vm_<instance>_home` × 4 | ext4 | — | 10G thin each, in `vm_pool` |

## Tested / reference hardware

| Machine | CPU | RAM | Role |
|---|---|---|---|
| MINISFORUM UM870 | Ryzen 7 8745H | 32 GB DDR5 | main development system (VT-d) |
| MSI Cubi N6000 | Pentium N6000 | 32 GB DDR4 | bare-metal install test target (VT-d) |
| Dell Latitude 3120 | Pentium N6000 | 8 GB | live install test target (VT-d) |
| Acer ES1-633 | Pentium N4200 | 8 GB | dev scratch |

**netVM's NIC: PCI passthrough only in the alpha.** The installer offers PCI
Ethernet controllers (class `0x0200`) and nothing else; a USB NIC (such as
the r8152 used on development hosts) cannot be assigned to netVM and is not
supported (README, *Known limitations*). PCI passthrough is problematic on
some 2.5 GbE adapters: run `installer/preflight.sh` and check the card's
IOMMU group before installing. *(Until 2026-10-05 this paragraph named USB-NIC
passthrough as the working alternative; that was development practice, and
the alpha installer does not provide it.)*

The Dell Latitude 3120 (8 GB) is below the alpha's 16 GB minimum, and the
installer refuses it.

## Caveats (current installer state)

- **Hardcoded secrets** — removed 2026-10-04: hostname, user and password are
  prompted, and no Wi-Fi or WireGuard secret is in the scripts. *(The R167
  note of 2026-10-03 recorded the WG key and Wi-Fi passphrase as rotated
  (R162); the literals remain in git history, burned.)*
  [SECURITY-MODEL.md, gap #1](SECURITY-MODEL.md#known-gaps-tracked) records
  the same state since 2026-10-05.
- **Hibernation non-functional** — swap is sized = RAM, but there is no
  `resume` hook / kernel parameter. Either add resume support or shrink swap;
  on 32 GB machines this is currently dead disk space.
- **App layers are full copies** — each app layer is installed as its own
  thin LV holding the foundation's blocks too (about 2–3 GB more on disk than
  thin snapshots would take). Importing them as snapshots is post-alpha.
- **Version header** — aligned 2026-10-04: the script header names the
  milestone (v0.2), not a script iteration counter.
