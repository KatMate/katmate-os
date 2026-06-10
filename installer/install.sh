#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="cyberdummy"
USERNAME="user"
PASSWORD="password"
USE_LUKS="yes"

SSID="KatMateAP"
PASS="Lucky5tr1k3G0ld"

log() {
  echo -e "\n==> $1"
}

require() {
  command -v "$1" >/dev/null || {
    echo "Missing command: $1"
    exit 1
  }
}

if findmnt /mnt >/dev/null 2>&1; then
  echo "/mnt already occupied. Do NOT mount script USB there. Use /installer."
  exit 1
fi

cleanup() {
  swapoff -a 2>/dev/null || true

  if [[ "${KEEP_MOUNTS:-no}" == "yes" ]]; then
    echo "KEEP_MOUNTS=yes, leaving /mnt mounted for inspection."
    return 0
  fi

  umount -R /mnt 2>/dev/null || true
}
trap cleanup EXIT

for c in iwctl parted cryptsetup pacstrap genfstab lsblk blkid mkfs.fat mkfs.ext4 arch-chroot; do
  require "$c"
done

log "WiFi"

WIFI_DEV="$(iwctl device list | awk '/station/ {print $2; exit}')"

if [[ -z "${WIFI_DEV}" ]]; then
  echo "No WiFi station device found."
  exit 1
fi

iwctl --passphrase "$PASS" station "$WIFI_DEV" connect-hidden "$SSID"

log "Disk selection"

lsblk -d -o NAME,SIZE,MODEL
read -rp "Disk (e.g. nvme0n1): " D
DISK="/dev/$D"

read -rp "WIPE $DISK (yes/no): " C
[[ "$C" == "yes" ]]

log "Partitioning"

wipefs -af "$DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart ROOT 513MiB 100%

if [[ "$DISK" == *nvme* ]]; then
  EFI="${DISK}p1"
  ROOT="${DISK}p2"
else
  EFI="${DISK}1"
  ROOT="${DISK}2"
fi

partprobe "$DISK"
sleep 2

log "LUKS"

cryptsetup luksFormat "$ROOT"
cryptsetup open "$ROOT" cryptroot

ROOT_DEV="/dev/mapper/cryptroot"
LUKS_UUID="$(blkid -s UUID -o value "$ROOT")"

log "Filesystems"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT_DEV"

log "Mount target"

mount "$ROOT_DEV" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

mountpoint -q /mnt || {
  echo "/mnt not mounted"
  exit 1
}

mountpoint -q /mnt/boot || {
  echo "EFI /boot not mounted"
  exit 1
}

log "Pacman keyring"

pacman -Syy --noconfirm
pacman -S --noconfirm archlinux-keyring

log "Pacstrap"

pacstrap /mnt \
  base linux linux-firmware intel-ucode \
  grub efibootmgr cryptsetup iwd micro sudo nftables wireguard-tools

log "fstab"

genfstab -U /mnt >> /mnt/etc/fstab

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

cat >/mnt/root/install.env <<ENV
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
USE_LUKS="$USE_LUKS"
LUKS_UUID="$LUKS_UUID"
SSID="$SSID"
PASS="$PASS"
ENV

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m700 "$SCRIPT_DIR/postinstall.sh" /mnt/root/postinstall.sh

log "Chroot postinstall"

arch-chroot /mnt /root/postinstall.sh

log "Fix resolv.conf outside chroot"

rm -f /mnt/etc/resolv.conf || true
ln -sfn /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

log "Install GRUB"

mountpoint -q /mnt/boot || {
  echo "/mnt/boot is not mounted"
  exit 1
}

arch-chroot /mnt grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=Katmate \
  --removable \
  --recheck

log "Generate GRUB config"

arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

log "Verify bootloader"

test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI || {
  echo "Missing /mnt/boot/EFI/BOOT/BOOTX64.EFI"
  exit 1
}

test -f /mnt/boot/grub/grub.cfg || {
  echo "Missing /mnt/boot/grub/grub.cfg"
  exit 1
}

grep -q "cryptdevice=UUID=${LUKS_UUID}:cryptroot" /mnt/boot/grub/grub.cfg || {
  echo "cryptdevice missing from grub.cfg"
  exit 1
}

log "Boot files"

find /mnt/boot -maxdepth 4 -type f | sort

log "DONE"
echo "Install finished successfully."
echo "If you want to inspect before reboot next time, run with:"
echo "KEEP_MOUNTS=yes ./install.sh"
