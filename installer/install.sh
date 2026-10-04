#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KatMate OS — installer (milestone v0.2)
# ---------------------------------------------------------------------------

# Minimum requirements
MIN_DISK_GB=32
MIN_ROOT_GB=20
MAX_ROOT_GB=60

# ---------------------------------------------------------------------------

log() {
  echo -e "\n==> $1"
}

die() {
  echo -e "\nERROR: $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null || die "Missing command: $1"
}

# ---------------------------------------------------------------------------
# Sanity check /mnt
# ---------------------------------------------------------------------------

if findmnt /mnt >/dev/null 2>&1; then
  die "/mnt already occupied. Do NOT mount script USB there. Use /installer."
fi

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------

cleanup() {
  # install.env must not survive on the target, whatever happened to
  # postinstall.sh. Before the KEEP_MOUNTS return, so it holds there too.
  rm -f /mnt/root/install.env 2>/dev/null || true

  swapoff -a 2>/dev/null || true

  if [[ "${KEEP_MOUNTS:-no}" == "yes" ]]; then
    echo "KEEP_MOUNTS=yes, leaving /mnt mounted for inspection."
    return 0
  fi

  umount -R /mnt 2>/dev/null || true

  # Deactivate LVM and close LUKS if they are open
  vgchange -an vg0 2>/dev/null || true
  cryptsetup close cryptlvm 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Required tools
# ---------------------------------------------------------------------------

# iwctl is not listed: it is needed only on the offline branch below, which
# checks for it itself.
for c in loadkeys curl ip openssl parted cryptsetup pvcreate vgcreate lvcreate lvdisplay \
          pacstrap genfstab lsblk blkid mkfs.fat mkfs.ext4 arch-chroot \
          bootctl awk grep readlink; do
  require "$c"
done

# Live boot medium resolution, shared with preflight.sh (lib/live-medium.sh).
LM_LIB="$(dirname "$(readlink -f -- "$0")")/lib/live-medium.sh"
[[ -r "$LM_LIB" ]] || die "Missing $LM_LIB: copy the whole installer/ directory, not single scripts (install.sh and preflight.sh share lib/)."
# shellcheck source=installer/lib/live-medium.sh
source "$LM_LIB"

# ---------------------------------------------------------------------------
# Keymap
# ---------------------------------------------------------------------------
# Asked first and loaded into the live console at once, so every passphrase
# typed from here on (Wi-Fi, user password, LUKS) is typed under the same
# layout the installed system uses. The LUKS passphrase in particular is set
# here and typed again in the initramfs, which takes its layout from
# vconsole.conf through the keymap hook.

log "Keymap"

KEYMAPS=""
if command -v localectl >/dev/null; then
  KEYMAPS="$(localectl list-keymaps 2>/dev/null || true)"
fi
[[ -n "$KEYMAPS" ]] || echo "localectl list-keymaps unavailable: the keymap is taken as given."

while :; do
  read -rp "Console keymap [us]: " KEYMAP
  KEYMAP="${KEYMAP:-us}"
  # It is written to install.env, which postinstall.sh sources.
  if [[ ! "$KEYMAP" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Not a keymap name: '$KEYMAP'."
    continue
  fi
  if [[ -n "$KEYMAPS" ]] && ! grep -qxF -- "$KEYMAP" <<<"$KEYMAPS"; then
    echo "Unknown keymap '$KEYMAP' (see: localectl list-keymaps)."
    continue
  fi
  loadkeys "$KEYMAP" && break
  echo "loadkeys $KEYMAP failed (run the installer on the console, not over SSH)."
done
echo "Keymap: $KEYMAP (loaded in the live console)"

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
# A check, not a configuration: if the live system is already online (UTP,
# DHCP by archiso), nothing is done. Wi-Fi is set up only when it is offline.
# Nothing about the install-time network is written to the target.
# The test is HTTPS, not ICMP: ICMP is filtered on some segments.

log "Network"

online() {
  curl -fsS -m 5 -o /dev/null https://archlinux.org >/dev/null 2>&1
}

default_route_dev() {
  ip -o route show default 2>/dev/null \
    | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}'
}

if online; then
  echo "Online (HTTPS to archlinux.org): default route via $(default_route_dev || true). Wi-Fi skipped."
else
  echo "Offline: HTTPS to archlinux.org failed."
  command -v iwctl >/dev/null || die "Offline, and iwctl is missing: connect UTP."

  WIFI_DEV="$(iwctl device list | awk '/station/ {print $2; exit}')"
  [[ -n "$WIFI_DEV" ]] || die "Offline, no Wi-Fi device: connect UTP."
  echo "Wi-Fi station device: $WIFI_DEV"

  WIFI_SSID=""
  while [[ -z "$WIFI_SSID" ]]; do
    read -rp "Wi-Fi SSID: " WIFI_SSID
  done
  read -rsp "Wi-Fi passphrase (empty for an open network): " WIFI_PASS
  echo ""

  # The passphrase is on iwctl's command line, so it is visible in the live
  # system's process list while iwctl runs. Live system only; never persisted.
  WIFI_ARGS=()
  [[ -n "$WIFI_PASS" ]] && WIFI_ARGS=(--passphrase "$WIFI_PASS")

  iwctl station "$WIFI_DEV" scan || true
  sleep 3
  # A visible network first; if iwctl cannot connect to it as one, as hidden.
  if ! iwctl "${WIFI_ARGS[@]}" station "$WIFI_DEV" connect "$WIFI_SSID"; then
    echo "Not connected as a visible network, trying as hidden."
    iwctl "${WIFI_ARGS[@]}" station "$WIFI_DEV" connect-hidden "$WIFI_SSID" \
      || die "Wi-Fi: cannot connect to '$WIFI_SSID' on $WIFI_DEV."
  fi
  unset WIFI_PASS WIFI_ARGS

  # DHCP takes a moment after association.
  for _ in 1 2 3 4 5 6; do
    online && break
    sleep 5
  done
  online || die "Still offline after connecting to '$WIFI_SSID': check the passphrase, or connect UTP."
  echo "Online over Wi-Fi ($WIFI_DEV): default route via $(default_route_dev || true)."
fi

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
# Asked before anything is written to a disk, so a bad answer costs nothing.
# The password is hashed here, in the live system; the plaintext never
# reaches the target, and the hash reaches it only through chpasswd's stdin
# after postinstall.sh (no file). Root gets the same password as the user.

log "Identity"

# RFC 1123 label: 1-63 characters, letters, digits and '-', no '-' at
# either end.
while :; do
  read -rp "Hostname: " KM_HOSTNAME
  [[ "$KM_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && break
  echo "Not a valid hostname (RFC 1123 label: letters, digits, '-', 1-63, no '-' at either end)."
done

while :; do
  read -rp "Username: " USERNAME
  if [[ "$USERNAME" == "root" ]]; then
    echo "'root' is not a user account name here."
    continue
  fi
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
  echo "Not a valid username (^[a-z_][a-z0-9_-]{0,31}\$)."
done

while :; do
  read -rsp "Password for $USERNAME and root: " PW1
  echo ""
  if [[ -z "$PW1" ]]; then
    echo "Empty password refused."
    continue
  fi
  read -rsp "Repeat password: " PW2
  echo ""
  [[ "$PW1" == "$PW2" ]] && break
  echo "Passwords do not match."
done

PW_HASH="$(printf '%s' "$PW1" | openssl passwd -6 -stdin)"
unset PW1 PW2
# shellcheck disable=SC2016  # '$6$' is a literal prefix
[[ "$PW_HASH" == '$6$'* ]] || die "openssl passwd -6 did not return a SHA-512 crypt hash."

# ---------------------------------------------------------------------------
# CPU vendor detect → ucode
# ---------------------------------------------------------------------------

log "CPU detect"

CPU_VENDOR="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')"

# The IOMMU parameter follows the vendor (ADR-040): Intel needs intel_iommu=on,
# AMD needs nothing (amd_iommu=on is not an option), and iommu=pt is never set.
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
  UCODE="amd-ucode"
  IOMMU_PARAM=""
  echo "CPU: AMD → amd-ucode"
  echo "IOMMU: AMD-Vi is on by default, no parameter (ADR-040)"
elif [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
  UCODE="intel-ucode"
  IOMMU_PARAM="intel_iommu=on"
  echo "CPU: Intel → intel-ucode"
  echo "IOMMU: intel_iommu=on (ADR-040)"
else
  die "Unknown CPU vendor (${CPU_VENDOR:-none}): no known IOMMU path (ADR-040), so this machine cannot be a KatMate host."
fi

# ---------------------------------------------------------------------------
# Disk selection
# ---------------------------------------------------------------------------

log "Disk selection"

# The archiso stick this system booted from is never a target. Any other
# disk, USB included, may be (operator, 2026-10-04).
lm_resolve "$(cat /proc/cmdline)"
for l in "${LM_LINES[@]}"; do echo "  $l"; done
if (( LM_ARCHISO )) && [[ -z "$LM_DISK" ]]; then
  die "Archiso boot ($LM_PARAMS), but the boot medium resolves to no disk: cannot prove the target is not the boot stick."
fi
echo ""

lsblk -d -o NAME,SIZE,TRAN,MODEL
echo ""
read -rp "Disk (e.g. sda, nvme0n1): " D
DISK="/dev/$D"

[[ -b "$DISK" ]] || die "Device $DISK does not exist."

if (( LM_ARCHISO )); then
  TARGET_DISK="$(lm_disk_of "$DISK")" \
    || die "Cannot resolve $DISK to a disk: cannot prove it is not the boot stick."
  # Every disk any method resolved to is refused, not only the first.
  if [[ " $LM_SEEN " == *" $TARGET_DISK "* ]]; then
    die "$DISK is on $TARGET_DISK, the live boot medium this system booted from. Refusing."
  fi
fi

echo ""
read -rp "WIPE $DISK — everything on it will be erased (yes/no): " C
[[ "$C" == "yes" ]] || die "Aborted by user."

# ---------------------------------------------------------------------------
# Disk size check and proportional layout
# ---------------------------------------------------------------------------

log "Disk size check"

DISK_BYTES="$(lsblk -b -d -o SIZE -n "$DISK")"
DISK_GB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))

echo "Disk: ${DISK_GB}G"

(( DISK_GB >= MIN_DISK_GB )) || die "Disk too small: ${DISK_GB}G, minimum ${MIN_DISK_GB}G."

# RAM size, for swap
RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
# Round up to a whole GiB
(( RAM_KB % (1024*1024) > 0 )) && RAM_GB=$(( RAM_GB + 1 )) || true
SWAP_GB="${RAM_GB}"

# Root: 15% of the disk, min MIN_ROOT_GB, max MAX_ROOT_GB
ROOT_GB=$(( DISK_GB * 15 / 100 ))
(( ROOT_GB < MIN_ROOT_GB )) && ROOT_GB=${MIN_ROOT_GB}
(( ROOT_GB > MAX_ROOT_GB )) && ROOT_GB=${MAX_ROOT_GB}

# EFI: 512M, reserved as 1G in the calculation (rounded up)
EFI_GB=1

# Thin pool: the remainder
THINPOOL_GB=$(( DISK_GB - EFI_GB - ROOT_GB - SWAP_GB ))

(( THINPOOL_GB < 8 )) && die "Not enough space for the thin pool (${THINPOOL_GB}G): the disk is too small."

# Thin pool metadata: 1% of the pool, min 64M, max 1G
TMETA_MB=$(( THINPOOL_GB * 1024 / 100 ))
(( TMETA_MB < 64 ))    && TMETA_MB=64
(( TMETA_MB > 1024 ))  && TMETA_MB=1024

echo ""
echo "Layout:"
echo "  EFI:      512M"
echo "  vg0-root: ${ROOT_GB}G"
echo "  vg0-swap: ${SWAP_GB}G"
echo "  thinpool: ~${THINPOOL_GB}G (data: remainder 100%FREE, metadata: ${TMETA_MB}M)"
echo ""
read -rp "Confirm layout (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted by user."

# ---------------------------------------------------------------------------
# Partitioning
# ---------------------------------------------------------------------------

log "Partitioning"

wipefs -af "$DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart LUKS 513MiB 100%

if [[ "$DISK" == *nvme* ]]; then
  EFI="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  EFI="${DISK}1"
  ROOT_PART="${DISK}2"
fi

partprobe "$DISK"
sleep 2

# ---------------------------------------------------------------------------
# LUKS
# ---------------------------------------------------------------------------

log "LUKS"

cryptsetup luksFormat --type luks2 "$ROOT_PART"
cryptsetup open "$ROOT_PART" cryptlvm

LUKS_UUID="$(blkid -s UUID -o value "$ROOT_PART")"

# ---------------------------------------------------------------------------
# LVM
# ---------------------------------------------------------------------------

log "LVM"

pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm

lvcreate -L "${ROOT_GB}G"  vg0 -n root
lvcreate -L "${SWAP_GB}G"  vg0 -n swap

# Thin pool: LVM creates ALL of it at once (data + meta + pmspare) from the
# remainder. The manual meta + data + lvconvert approach fails, because
# lvconvert also reserves pmspare internally (= the metadata size), and
# 100%FREE has already taken the space pmspare needs.
# --poolmetadatasize sets the metadata explicitly; -l 100%FREE gives the pool
# the whole remainder.
lvcreate --type thin-pool \
         -l 100%FREE \
         --poolmetadatasize "${TMETA_MB}M" \
         vg0 -n thinpool

# ---------------------------------------------------------------------------
# Filesystems
# ---------------------------------------------------------------------------

log "Filesystems"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F /dev/vg0/root
mkswap /dev/vg0/swap

# ---------------------------------------------------------------------------
# Mount
# ---------------------------------------------------------------------------

log "Mount target"

mount /dev/vg0/root /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot
swapon /dev/vg0/swap

mountpoint -q /mnt      || die "/mnt not mounted"
mountpoint -q /mnt/boot || die "EFI /boot not mounted"

# ---------------------------------------------------------------------------
# Mirror refresh — reflector + ParallelDownloads before pacstrap
# (the fastly mirror is unstable; without this pacstrap often fails the
# first time)
# ---------------------------------------------------------------------------

log "Mirrorlist refresh"

# ParallelDownloads speeds things up and makes one bad mirror matter less
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || \
  echo 'ParallelDownloads = 5' >> /etc/pacman.conf

# reflector: geo-close, https, fresh, sorted by rate
if command -v reflector >/dev/null; then
  reflector --country Switzerland,Germany,Austria \
            --protocol https --age 12 --sort rate \
            --save /etc/pacman.d/mirrorlist \
    || echo "reflector failed, keeping existing mirrorlist"
else
  # fallback: a manual geo-close list (fastly is unstable)
  cat >/etc/pacman.d/mirrorlist <<'MIRR'
Server = https://mirror.init7.net/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.pseudoform.org/$repo/os/$arch
MIRR
fi

# ---------------------------------------------------------------------------
# Pacman keyring
# ---------------------------------------------------------------------------

log "Pacman keyring"

pacman -Syy --noconfirm
pacman -S --noconfirm archlinux-keyring

# ---------------------------------------------------------------------------
# Pacstrap
# ---------------------------------------------------------------------------

log "Pacstrap"

UCODE_PKG=""
[[ -n "$UCODE" ]] && UCODE_PKG="$UCODE"

pacstrap /mnt \
  base linux-hardened linux-hardened-headers linux-firmware ${UCODE_PKG} \
  lvm2 \
  efibootmgr cryptsetup \
  iwd micro sudo \
  nftables wireguard-tools \
  qemu-full

# ---------------------------------------------------------------------------
# fstab
# ---------------------------------------------------------------------------

log "fstab"

genfstab -U /mnt >> /mnt/etc/fstab

# ---------------------------------------------------------------------------
# Base configuration
# ---------------------------------------------------------------------------

log "Base config"

echo "$KM_HOSTNAME" > /mnt/etc/hostname

ln -sf /usr/share/zoneinfo/Europe/Zurich /mnt/etc/localtime

mkdir -p /mnt/etc/systemd/network
cat >/mnt/etc/systemd/network/20-wired.network <<NET
[Match]
Name=en*

[Network]
DHCP=yes
NET

mkdir -p /mnt/etc/sudoers.d
echo '%wheel ALL=(ALL) ALL' >/mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel

# ---------------------------------------------------------------------------
# install.env for postinstall (no secrets: see Identity)
# ---------------------------------------------------------------------------

cat >/mnt/root/install.env <<ENV
USERNAME="${USERNAME}"
LUKS_UUID="${LUKS_UUID}"
UCODE="${UCODE}"
KEYMAP="${KEYMAP}"
ENV

# ---------------------------------------------------------------------------
# Copy postinstall
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m700 "$SCRIPT_DIR/postinstall.sh" /mnt/root/postinstall.sh

# ---------------------------------------------------------------------------
# Chroot → postinstall
# ---------------------------------------------------------------------------

log "Chroot postinstall"

arch-chroot /mnt /root/postinstall.sh
rm -f /mnt/root/install.env

# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------

log "Passwords"

printf 'root:%s\n%s:%s\n' "$PW_HASH" "$USERNAME" "$PW_HASH" \
  | arch-chroot /mnt chpasswd -e
unset PW_HASH

# ---------------------------------------------------------------------------
# resolv.conf
# ---------------------------------------------------------------------------

log "Fix resolv.conf"

rm -f /mnt/etc/resolv.conf || true
ln -sfn /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# ---------------------------------------------------------------------------
# Systemd-boot
# ---------------------------------------------------------------------------

log "Systemd-boot"

arch-chroot /mnt bootctl install

# loader.conf — no menu, boot directly
cat >/mnt/boot/loader/loader.conf <<LOADER
default katmate.conf
timeout 0
console-mode auto
editor no
LOADER

# Boot entry
mkdir -p /mnt/boot/loader/entries
cat >/mnt/boot/loader/entries/katmate.conf <<ENTRY
title   Katmate OS
linux   /vmlinuz-linux-hardened
initrd  /${UCODE}.img
initrd  /initramfs-linux-hardened.img
options cryptdevice=UUID=${LUKS_UUID}:cryptlvm root=/dev/vg0/root rw quiet loglevel=3${IOMMU_PARAM:+ ${IOMMU_PARAM}}
ENTRY

# Without ucode, remove the empty initrd line
if [[ -z "$UCODE" ]]; then
  sed -i '/^initrd  \/.img$/d' /mnt/boot/loader/entries/katmate.conf
fi

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

log "Verification"

test -f /mnt/boot/EFI/systemd/systemd-bootx64.efi || die "systemd-boot EFI binary missing"
test -f /mnt/boot/loader/entries/katmate.conf      || die "boot entry missing"
test -f /mnt/boot/vmlinuz-linux-hardened           || die "kernel missing"
test -f /mnt/boot/initramfs-linux-hardened.img     || die "initramfs missing"

for u in root "$USERNAME"; do
  # shellcheck disable=SC2016  # literal awk program and '$6$' prefix
  [[ "$(awk -F: -v u="$u" '$1 == u {print substr($2, 1, 3)}' /mnt/etc/shadow)" == '$6$' ]] \
    || die "/etc/shadow: $u has no SHA-512 password hash"
done
[[ ! -e /mnt/root/install.env ]] || die "/root/install.env still present on the target"

grep -q "cryptdevice=UUID=${LUKS_UUID}:cryptlvm" /mnt/boot/loader/entries/katmate.conf \
  || die "cryptdevice missing from the boot entry"

# ADR-040: the vendor's IOMMU parameter is present, and no passthrough or
# AMD enabling parameter is, whatever the vendor.
OPTS=" $(grep '^options' /mnt/boot/loader/entries/katmate.conf | head -n 1) "
if [[ -n "$IOMMU_PARAM" && "$OPTS" != *" $IOMMU_PARAM "* ]]; then
  die "$IOMMU_PARAM missing from the boot entry (ADR-040)"
fi
[[ "$OPTS" != *" iommu=pt "* ]] || die "iommu=pt in the boot entry (ADR-040 forbids it)"
[[ "$OPTS" != *" amd_iommu="* ]] || die "amd_iommu= in the boot entry (ADR-040 forbids it)"

log "Boot files"
find /mnt/boot -maxdepth 4 -type f | sort

log "DONE"
echo ""
echo "Installation complete."
echo "Remove the installation medium and reboot."
echo ""
echo "To inspect the target before rebooting: KEEP_MOUNTS=yes ./install.sh"
