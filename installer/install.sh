#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Katmate OS — Installer v0.3
# ---------------------------------------------------------------------------

HOSTNAME="cyberdummy"
USERNAME="user"
PASSWORD="password"

SSID="KatMateAP"
PASS="Lucky5tr1k3G0ld"

# Minimalni pogoji
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
  swapoff -a 2>/dev/null || true

  if [[ "${KEEP_MOUNTS:-no}" == "yes" ]]; then
    echo "KEEP_MOUNTS=yes, leaving /mnt mounted for inspection."
    return 0
  fi

  umount -R /mnt 2>/dev/null || true

  # Deaktiviraj LVM in LUKS če sta odprta
  vgchange -an vg0 2>/dev/null || true
  cryptsetup close cryptlvm 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Preveri orodja
# ---------------------------------------------------------------------------

for c in iwctl parted cryptsetup pvcreate vgcreate lvcreate lvdisplay \
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
# WiFi
# ---------------------------------------------------------------------------

log "WiFi"

WIFI_DEV="$(iwctl device list | awk '/station/ {print $2; exit}')"

if [[ -z "${WIFI_DEV}" ]]; then
  die "No WiFi station device found."
fi

iwctl --passphrase "$PASS" station "$WIFI_DEV" connect-hidden "$SSID"
sleep 3

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
read -rp "WIPE $DISK — vse bo izbrisano (yes/no): " C
[[ "$C" == "yes" ]] || die "Aborted by user."

# ---------------------------------------------------------------------------
# Disk size check in proporcionalni izračun
# ---------------------------------------------------------------------------

log "Disk size check"

DISK_BYTES="$(lsblk -b -d -o SIZE -n "$DISK")"
DISK_GB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))

echo "Disk: ${DISK_GB}G"

(( DISK_GB >= MIN_DISK_GB )) || die "Disk premajhen: ${DISK_GB}G, minimum ${MIN_DISK_GB}G."

# RAM size za swap
RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
# Zaokrožimo navzgor na celo število
(( RAM_KB % (1024*1024) > 0 )) && RAM_GB=$(( RAM_GB + 1 )) || true
SWAP_GB="${RAM_GB}"

# Root: 15% diska, min MIN_ROOT_GB, max MAX_ROOT_GB
ROOT_GB=$(( DISK_GB * 15 / 100 ))
(( ROOT_GB < MIN_ROOT_GB )) && ROOT_GB=${MIN_ROOT_GB}
(( ROOT_GB > MAX_ROOT_GB )) && ROOT_GB=${MAX_ROOT_GB}

# EFI: 512MB = 1G reserva v izračunu (zaokroženo)
EFI_GB=1

# Thinpool: preostanek
THINPOOL_GB=$(( DISK_GB - EFI_GB - ROOT_GB - SWAP_GB ))

(( THINPOOL_GB < 8 )) && die "Premalo prostora za thinpool (${THINPOOL_GB}G). Disk je premahen."

# Thinpool metadata: 1% thinpoola, min 64M, max 1G
TMETA_MB=$(( THINPOOL_GB * 1024 / 100 ))
(( TMETA_MB < 64 ))    && TMETA_MB=64
(( TMETA_MB > 1024 ))  && TMETA_MB=1024

echo ""
echo "Razporeditev:"
echo "  EFI:      512M"
echo "  vg0-root: ${ROOT_GB}G"
echo "  vg0-swap: ${SWAP_GB}G"
echo "  thinpool: ~${THINPOOL_GB}G (data: preostanek 100%FREE, metadata: ${TMETA_MB}M)"
echo ""
read -rp "Potrdi razporeditev (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted by user."

# ---------------------------------------------------------------------------
# Particioniranje
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

# Thin pool: LVM naredi VSE naenkrat (data + meta + pmspare) iz preostanka.
# Ročni meta+data+lvconvert pristop pade, ker lvconvert še interno rezervira
# pmspare (= velikost meta) → 100%FREE pobere prostor, ki ga pmspare rabi.
# --poolmetadatasize nastavi meta eksplicitno; -l 100%FREE da pool ves ostanek.
lvcreate --type thin-pool \
         -l 100%FREE \
         --poolmetadatasize "${TMETA_MB}M" \
         vg0 -n thinpool

# ---------------------------------------------------------------------------
# Filesystemi
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
# Mirror refresh — reflector + ParallelDownloads pred pacstrap
# (fastly mirror nestabilen; brez tega pacstrap pogosto pade prvič)
# ---------------------------------------------------------------------------

log "Mirrorlist refresh"

# ParallelDownloads pospeši + zniža občutljivost na en slab mirror
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || \
  echo 'ParallelDownloads = 5' >> /etc/pacman.conf

# reflector: geo-close, https, sveži, sortirani po hitrosti
if command -v reflector >/dev/null; then
  reflector --country Switzerland,Germany,Austria \
            --protocol https --age 12 --sort rate \
            --save /etc/pacman.d/mirrorlist \
    || echo "reflector failed, keeping existing mirrorlist"
else
  # fallback: ročni geo-close seznam (fastly je danes nestabilen)
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
# Osnovna konfiguracija
# ---------------------------------------------------------------------------

log "Base config"

echo "$HOSTNAME" > /mnt/etc/hostname

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
# install.env za postinstall
# ---------------------------------------------------------------------------

cat >/mnt/root/install.env <<ENV
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
LUKS_UUID="${LUKS_UUID}"
SSID="${SSID}"
PASS="${PASS}"
UCODE="${UCODE}"
ENV

# ---------------------------------------------------------------------------
# Kopiraj postinstall
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m700 "$SCRIPT_DIR/postinstall.sh" /mnt/root/postinstall.sh

# ---------------------------------------------------------------------------
# Chroot → postinstall
# ---------------------------------------------------------------------------

log "Chroot postinstall"

arch-chroot /mnt /root/postinstall.sh

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

# loader.conf — brez menija, direktno boot
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

# Če ni ucode, odstrani prazno initrd vrstico
if [[ -z "$UCODE" ]]; then
  sed -i '/^initrd  \/.img$/d' /mnt/boot/loader/entries/katmate.conf
fi

# ---------------------------------------------------------------------------
# Verifikacija
# ---------------------------------------------------------------------------

log "Verifikacija"

test -f /mnt/boot/EFI/systemd/systemd-bootx64.efi || die "systemd-boot EFI manjka"
test -f /mnt/boot/loader/entries/katmate.conf      || die "boot entry manjka"
test -f /mnt/boot/vmlinuz-linux-hardened           || die "kernel manjka"
test -f /mnt/boot/initramfs-linux-hardened.img     || die "initramfs manjka"

grep -q "cryptdevice=UUID=${LUKS_UUID}:cryptlvm" /mnt/boot/loader/entries/katmate.conf \
  || die "cryptdevice manjka v boot entry"

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
echo "Namestitev uspešna."
echo "Odstrani namestitveni medij in rebootaj."
echo ""
echo "Za pregled pred rebooteom: KEEP_MOUNTS=yes ./install.sh"
