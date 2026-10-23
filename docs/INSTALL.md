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
  be assigned in this release.
- The **KatMate install medium** of the release's tag on a USB stick
  (*The install medium*, below). It installs offline. The fallback is the
  stock Arch Linux live ISO, which needs a network for pacstrap
  (*Fallback: the stock Arch ISO*).
- A KatMate release (below), either on a `KMRELEASE` filesystem (a second
  stick, or a partition on the medium's stick) or reachable as GitHub release
  assets. A release from a URL needs a network: UTP (archiso DHCP) or, failing
  that, a Wi-Fi network the installer can join.

> **Do not mount anything at `/mnt`** before running the installer (e.g. the
> script USB) — the installer requires `/mnt` free and will abort otherwise.
> Use `/installer` for the USB.

## The release, and the first verification

A release is a flat set of files: `katmate-os-<tag>.tar.gz` (a `git archive`
of the release tag, which holds the installer), the guest images
(`*.img.zst`), their metadata, the kernels, the host binaries, `release.env`,
`images.list` and the install medium `katmate-install-<tag>-x86_64.iso`.
**`SHA256SUMS`** lists every file, and **`SHA256SUMS.asc`**
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
sha256sum -c --ignore-missing SHA256SUMS                       # the archive (and the ISO, if here): OK
tar -xzf katmate-os-<tag>.tar.gz -C /root
cd /root/katmate-os-<tag>
```

Run the installer only from that extracted archive. It compares the tree it
runs from with the signed archive and refuses on any difference, so a clone
or an edited copy will not install. The install medium carries the archive of
its own tag and unpacks it itself; the same comparison makes a medium and a
release of different tags refuse each other.

## The install medium

The decision and its measurements: [ADR-042](adr/ADR-042.md). The medium is
UEFI only. It carries the installer (the tag's archive) and an offline
package repository, and no guest images: those stay in the release files.

**Where it comes from.** It is a release file, verified with the rest by the
two commands above when it sits in the same directory. It is built by
`build/iso.sh`, run as root on an Arch host from the release tag's archive:

```
sudo build/iso.sh --archive <dir>/katmate-os-<tag>.tar.gz --out <empty dir>
```

It writes `katmate-install-<tag>-x86_64.iso` and its `.sha256`. In a release
the ISO has no signature of its own: it is listed in the signed `SHA256SUMS`,
and the `.sha256` is not a release file ([ADR-042](adr/ADR-042.md), revision
note of 2026-10-23).

**Write it to a stick** (this erases the stick; check the device name with
`lsblk` first):

```
dd if=katmate-install-<tag>-x86_64.iso of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
```

**Put the release files on a `KMRELEASE` filesystem**, all of them at its
root (`SHA256SUMS`, `SHA256SUMS.asc`, the archive, the images and the rest;
the ISO is not needed there).
A second stick:

```
parted -s /dev/sdY mklabel gpt mkpart KMRELEASE fat32 1MiB 100%
mkfs.fat -F 32 -n KMRELEASE /dev/sdY1
mkdir -p /tmp/kmrel && mount /dev/sdY1 /tmp/kmrel
cp <release dir>/* /tmp/kmrel/ && umount /tmp/kmrel
```

or a third partition in the free space behind the ISO on the medium's own
stick (`sgdisk -e /dev/sdX` moves the backup GPT header to the end of the
stick; then `sgdisk -n 0:0:0 -t 0:0700 /dev/sdX`, and `mkfs.fat -F 32 -n
KMRELEASE` on the new partition as `lsblk` names it). **UNVERIFIED:** iso1
measured a separate release disk only; the same-stick layout has not been
built or booted. FAT32 limits a single file to 4 GiB.

The installer uses exactly one `KMRELEASE` filesystem without asking, and
refuses if there is more than one; `KM_RELEASE_SRC` overrides it. With none,
it asks for a source and offers the GitHub release of the medium's own tag.
A disk holding a `KMRELEASE` filesystem is never an install target.

**Booting it.** The boot entry already carries `intel_iommu=on`
([ADR-040](adr/ADR-040.md)); nothing needs to be edited. On tty1, root is
logged in and a launcher starts the installer after 5 s; any key gives a
shell instead, and `katmate-install --now` starts it from there. tty2–6 offer
a root login with an **empty password**, as on the Arch ISO.

**The live system's firmware is network firmware only**
(`linux-firmware-{intel,realtek,atheros,mediatek,broadcom}`), for its own NIC
and Wi-Fi when the release comes from a URL. The installed host gets the full
`linux-firmware` from the offline repository.

**Validity window.** The medium's packages are signed by Arch packager keys
that expire. `build/iso.sh` records the earliest expiry as `ISO_VALID_UNTIL`
(UTC) and refuses to build a medium with fewer than 60 days left. From that
date on, `install.sh` refuses before the first question and before touching
any disk, with no override:

```
This install medium expired on <date> (UTC); the clock says <today>. Its packages are signed by keys that are no longer valid. Get a newer medium, or check the clock.
```

`build/iso.sh` prints the date on every build, and the medium carries it in
`/etc/katmate-iso/iso.env`.

## Fallback: the stock Arch ISO

The Arch Linux live ISO still works. It needs a network for the keyring
refresh and for pacstrap, which then uses the live environment's mirrors; the
release may come from a URL, a `KMRELEASE` filesystem or a directory. On
Intel, the IOMMU parameter is added to the boot entry by hand (*Preflight*).
Verify the release and extract the archive as shown above, then run
`bash installer/install.sh` from it.

## Preflight

`installer/preflight.sh` checks the hardware **before** `install.sh`, from the
same live environment, and changes nothing: no module is loaded, no driver is
bound, nothing is installed. It covers CPU virtualisation, UEFI, KVM, the
IOMMU (ACPI table, activity, interrupt remapping), every IOMMU group, the
isolation of each Ethernet, Wi-Fi and USB controller, NIC identity (MAC,
slot path, udev path), the GPU, RAM, CPUs and disks.

**Boot the live system with the IOMMU on, or the result is not meaningful.**
The install medium's boot entry already carries `intel_iommu=on`. On the stock
Arch ISO on Intel, edit its boot entry and append `intel_iommu=on`. On AMD the
IOMMU is on by default (`amd_iommu=on` is not a valid option; the kernel logs it as
unknown). If the IOMMU is off because of the boot line, the preflight says so,
distinctly from a firmware with VT-d / AMD-Vi disabled.

**It writes one file, and it needs a writable place for it.** The live
medium is read-only, and the live system's `/tmp` is in RAM and lost at
reboot. On the install medium, take the shell (any key at the launcher) and
unpack the tree first if the launcher has not:
`tar -xzf /usr/share/katmate-iso/katmate-os-<tag>.tar.gz -C /root`; the
preflight is then `/root/katmate-os-<tag>/installer/preflight.sh`. On the
stock Arch ISO, run it as root from the script USB, if that stick is mounted
read-write:

```
cd /installer
bash preflight.sh
```

or write to `/tmp` and copy the file to a second stick before rebooting:

```
bash /installer/preflight.sh -o /tmp/preflight.txt
```

A disk holding a `KMRELEASE` filesystem is marked `(release medium)` and is
not counted as an install candidate. The default name is
`katmate-preflight-<hostname>-<UTC time>.txt` in the current directory. If the file cannot be created, or already exists, the
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

Run as root, from the extracted archive: `bash installer/install.sh`. On the
install medium the launcher does this (*The install medium*).

1. **Sanity checks** — `/mnt` unoccupied, all required tools present
   (`curl`, `gpg`, `zstd`, `openssl` and `loadkeys` among them; `iwctl` only
   if Wi-Fi is needed). On the install medium also its offline pacman
   configuration and the validity window, before the first question
   (*The install medium*).
2. **Keymap** — prompted, default `us`, checked against `localectl
   list-keymaps` when available, and loaded into the live console at once,
   so every passphrase that follows — the LUKS one above all — is typed under
   the layout the installed system's initramfs will use.
3. **Release source** — resolved before the network, because a local release
   on the install medium needs none. `KM_RELEASE_SRC` if set; else exactly one
   `KMRELEASE` filesystem, mounted read-only at `/run/katmate/release` without
   a question (more than one: refused); else a prompt for a directory or a
   URL. The default URL is the latest GitHub release, or on the install medium
   the release of the medium's own tag.
4. **Network** — on the install medium only for a URL source; elsewhere
   always, because pacstrap needs it. A check, not a configuration. Online
   test over HTTPS (`curl` to `archlinux.org`, 5 s; ICMP is not used). If
   online, the interface carrying the default route is logged and Wi-Fi is
   skipped. If offline, an iwd station device is required (otherwise: connect
   UTP), SSID and passphrase are prompted (passphrase not echoed), a visible
   and then a hidden connect is tried, and the HTTPS check is repeated.
   Nothing about the install-time network is written to the target.
5. **Release** — `SHA256SUMS.asc` must verify with the release key alone,
   by the pinned fingerprint; the running tree must equal the signed archive; `netvm.meta` must record
   `NETVM_ROOT_UNLOCKED=no`; `images.list` must carry exactly the five
   images. Every file is checked against `SHA256SUMS` before it is used.
6. **RAM** — refused below 16 GB, before any disk is touched.
7. **Identity** — hostname (RFC 1123 label), username
   (`^[a-z_][a-z0-9_-]{0,31}$`, not `root`) and password (twice, not echoed,
   non-empty), hashed in the live system (`openssl passwd -6`). **root gets
   no password and is locked**; administration is through `sudo` (wheel).
8. **Desktop keyboard layout** — XKB layout name(s) for sway (`si`, `de`,
   `si,us`; default `us`), separate from the console keymap, whose names
   differ.
9. **CPU detection** — vendor → `amd-ucode` / `intel-ucode`, the IOMMU
   parameter ([ADR-040](adr/ADR-040.md)), and on AMD the `topoext`
   drop-in for netVM's unit.
10. **netVM's card** — every PCI Ethernet controller is listed (address,
   vendor:device, driver, IOMMU group); you pick one. A card whose
   vendor:device another Ethernet controller shares is refused; a card that
   shares its IOMMU group with other devices asks for confirmation.
11. **Disk selection** — interactive; the live boot stick and any disk
    holding a `KMRELEASE` filesystem are refused as targets.
12. **Proportional layout** (computed, then confirmed together with the wipe):
    - ESP: 512M
    - root: 15% of disk, clamped to 20–60 G
    - swap: sized = RAM (rounded up)
    - netVM: a linear LV of its image's size, plus 1 GiB left free in `vg0`
    - thin pool `vm_pool`: the rest; metadata 1% of it, clamped 64M–1G;
      refused if it cannot hold the images plus 8 GiB
13. **Partitioning, encryption, LVM, filesystems, mount** — GPT: ESP + LUKS2
    (`cryptlvm`) → `vg0` with `root`, `swap` and `vm_pool`; FAT32 ESP at
    `/boot`, ext4 root, swap on.
14. **Pacstrap** — the package set in
    [`installer/lib/packages.sh`](../installer/lib/packages.sh), with the
    vendor's microcode, each package with its reason there. On the install
    medium it is offline, from the medium's repository
    (`/etc/katmate-iso/pacman-offline.conf`), and the keyring refresh is
    skipped. Elsewhere `pacman -Syy` and `archlinux-keyring` come first, and
    pacstrap uses the live environment's mirror and download configuration as
    is (the installer does not change it). Retried up to three times. No
    `iwd` and no `wireguard-tools`: the host has no network (until
    2026-10-05 both were installed, `iwd` not enabled).
15. **Base config** — fstab, hostname, timezone `Europe/Zurich`, wheel
    sudoers. **No network profile**: no wired or Wi-Fi unit, and neither
    `systemd-networkd` nor `systemd-resolved` is enabled; the host's card
    belongs to netVM. *(Until 2026-10-05 this step wrote a wired DHCP unit,
    `20-wired.network`, and enabled both; operator ruling R11 removed them.)*
16. **Guest images** — each image is fetched into the target's `/var/tmp`
    (URL source), checked, written to its LV (`vm_tpl_foundation`,
    `vm_app_web`, `vm_app_office`, `vm_app_vault` thin, written sparse;
    `vm_sys_netvm` linear) and read back byte for byte; the four thin images
    are then made read-only.
17. **T2** — the images' metadata in `/var/lib/katmate/`, netVM's kernel and
    initrd in `/var/lib/katmate/netvm/`, the MicroVM kernel and its
    provenance sidecar (checked, [ADR-034](adr/ADR-034.md)) in
    `/var/lib/katmate/kernels/`.
18. **T1** — `/etc/katmate/vm/{netvm,app_web,app_personal,app_work,app_vault,app_sandbox}.toml`
    from `installer/t1/`, `root:root 0644`, created and never overwritten
    ([ADR-032](adr/ADR-032.md) §1).
19. **Home LVs and deltas** — `vm_<instance>_home`, 10G thin, ext4, `user/`
    `1000:1000 0700`; `/var/lib/katmate/instances/<instance>.qcow2` over the
    instance's app layer.
20. **KatMate host parts** — `host/usr/` (units and `/usr/lib/katmate/`),
    `ping-client` and the host `waypipe` (`/opt/katmate/bin/`); vfio-pci for
    the chosen card in `/etc/modprobe.d/katmate-vfio.conf`;
    `/etc/sudoers.d/katmate-launch` for the user; the `waypipe-client` user
    unit in `/etc/systemd/user/`.
21. **Desktop** — `/etc/sway/config` (with an empty `outputs.conf` and the
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
22. **Handoff** — writes `/root/install.env` (username, LUKS UUID, ucode,
    keymap; no secrets), copies and runs `postinstall.sh` inside the chroot,
    then removes both — `install.env` also on failure, from the exit trap.
23. **Password** — the hash is piped to `chpasswd -e` in the chroot for the
    user only; it reaches the target only in `/etc/shadow`.
24. **systemd-boot** — `bootctl install`; `loader.conf` with `timeout 0`,
    `editor no`; boot entry with
    `cryptdevice=UUID=<luks>:cryptlvm root=/dev/vg0/root rw quiet splash loglevel=3`
    and the vendor's IOMMU parameter.
25. **Verification** — the boot files, the IOMMU parameters, `splash`; the
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
  (AF_VSOCK sole host↔guest channel per [ADR-003](adr/ADR-003.md))
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

**netVM's NIC: PCI passthrough only in this release.** The installer offers PCI
Ethernet controllers (class `0x0200`) and nothing else; a USB NIC (such as
the r8152 used on development hosts) cannot be assigned to netVM and is not
supported (README, *Known limitations*). PCI passthrough is problematic on
some 2.5 GbE adapters: run `installer/preflight.sh` and check the card's
IOMMU group before installing. *(Until 2026-10-05 this paragraph named USB-NIC
passthrough as the working alternative; that was development practice, and
the installer does not provide it.)*

The Dell Latitude 3120 (8 GB) is below the 16 GB minimum, and the
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
  thin snapshots would take). Importing them as snapshots is later work.
- **Version header** — aligned 2026-10-04: the script header names the
  milestone (v0.2), not a script iteration counter.
