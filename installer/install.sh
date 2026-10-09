#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KatMate OS — installer (milestone v0.2, alpha)
# ---------------------------------------------------------------------------
#
# Installs the alpha system from a signed release onto a fresh disk: the Arch
# host, the desktop, netVM and the five alpha AppVMs (ADR-020; operator
# rulings of 2026-10-05; app_sandbox, 2026-10-06). It builds nothing. The guest images, their T2
# metadata, the kernels and the host binaries come prebuilt from the release,
# and every one of them is checked against the signed SHA256SUMS before use.
#
# Run it from the verified release archive (docs/INSTALL.md), as root, on the
# Arch live ISO, with a network (pacstrap; and the release itself when its
# source is a URL). It refuses to run from a tree that differs from the
# signed archive.
#
# The installed host keeps no network profile (operator ruling R11): its NIC
# belongs to netVM from the first boot on.
# ---------------------------------------------------------------------------

# Release key (ADR-020; installer/katmate-release.asc). The fingerprint is
# pinned here and the key file must carry it.
RELEASE_KEY_FPR="3F49AE514562ACD3FF9D6049F8841B7B3D3AB436"
DEFAULT_RELEASE_URL="https://github.com/KatMate/katmate-os/releases/latest/download"

# Minimum requirements
MIN_DISK_GB=32
MIN_ROOT_GB=20
MAX_ROOT_GB=60
# 16 GB nominal (operator ruling, 2026-10-05, part 3). MemTotal on a 16 GB
# machine reads below 16 GiB by what firmware and an integrated GPU reserve,
# so the floor is 14 GiB of MemTotal, not 16.
MIN_RAM_KB=$(( 14 * 1024 * 1024 ))

VG=vg0
POOL=vm_pool            # build/config.sh POOL (operator ruling R5)
HOME_LV_SIZE=10G        # PARAMETERS.md, Home LV (state.md form of record)
DELTA_SIZE=10G          # PARAMETERS.md, Instance delta
NETVM_MARGIN_MB=1024    # free extents left in vg0 beside netVM's linear LV (R6)
POOL_SLACK_MB=8192      # pool room above the images' allocated size
ALPHA_INSTANCES=(app_web app_personal app_work app_vault app_sandbox)

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

TREE="$(cd "$(dirname "$(readlink -f -- "$0")")/.." && pwd)"

# ---------------------------------------------------------------------------
# Sanity check /mnt
# ---------------------------------------------------------------------------

if findmnt /mnt >/dev/null 2>&1; then
  die "/mnt already occupied. Do NOT mount script USB there. Use /installer."
fi

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------

LIVE_STAGE="/tmp/katmate-release"
TARGET_STAGE="/mnt/var/tmp/katmate-release"

cleanup() {
  # install.env must not survive on the target, whatever happened to
  # postinstall.sh. Before the KEEP_MOUNTS return, so it holds there too.
  rm -f /mnt/root/install.env 2>/dev/null || true
  # Downloaded release files are not part of the installed system.
  rm -rf "$TARGET_STAGE" "$LIVE_STAGE" 2>/dev/null || true

  swapoff -a 2>/dev/null || true

  if [[ "${KEEP_MOUNTS:-no}" == "yes" ]]; then
    echo "KEEP_MOUNTS=yes, leaving /mnt mounted for inspection."
    return 0
  fi

  umount -R /mnt 2>/dev/null || true

  # Deactivate LVM and close LUKS if they are open
  vgchange -an "$VG" 2>/dev/null || true
  cryptsetup close cryptlvm 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Required tools
# ---------------------------------------------------------------------------

# iwctl is not listed: it is needed only on the offline branch below, which
# checks for it itself.
for c in loadkeys curl ip openssl parted cryptsetup pvcreate vgcreate vgs lvcreate lvs lvchange \
          pacstrap genfstab lsblk blkid blockdev mkfs.fat mkfs.ext4 arch-chroot \
          bootctl awk grep sed readlink gpg sha256sum zstd dd cmp tar diff udevadm; do
  require "$c"
done

# Shared with preflight.sh (live-medium.sh); release handling (release.sh).
for l in live-medium.sh release.sh; do
  [[ -r "$TREE/installer/lib/$l" ]] || die "Missing installer/lib/$l: run the installer from the whole release tree."
done
# shellcheck source=installer/lib/live-medium.sh
source "$TREE/installer/lib/live-medium.sh"
# shellcheck source=installer/lib/release.sh
source "$TREE/installer/lib/release.sh"

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
# Release: signature, the running tree, and what the release contains
# ---------------------------------------------------------------------------
# Before any question about the disk: a release that does not verify costs
# nothing. Only the small files are read here; the images are fetched into
# the target once it exists (a URL source) and checked one by one there.

log "Release"

if [[ -n "${KM_RELEASE_SRC:-}" ]]; then
  REL_SOURCE="$KM_RELEASE_SRC"
else
  echo "Release source: a directory holding the release files (USB), or a URL."
  read -rp "Release source [$DEFAULT_RELEASE_URL]: " REL_SOURCE
  REL_SOURCE="${REL_SOURCE:-$DEFAULT_RELEASE_URL}"
fi
REL_SOURCE="${REL_SOURCE%/}"
rel_open "$REL_SOURCE" "$LIVE_STAGE"
echo "Source: $REL_SOURCE"

rel_verify_sums "$TREE/installer/katmate-release.asc" "$RELEASE_KEY_FPR"

rel_check release.env
REL_ENV="$(rel_path release.env)"
[[ "$(rel_env_get "$REL_ENV" KATMATE_RELEASE_VERSION)" == 1 ]] \
  || die "release.env: KATMATE_RELEASE_VERSION is not 1; this installer does not know the format."
RELEASE_TAG="$(rel_env_get "$REL_ENV" RELEASE_TAG)"
ARCHIVE="$(rel_env_get "$REL_ENV" ARCHIVE)"
KERNEL_FILE="$(rel_env_get "$REL_ENV" KERNEL_FILE)"
KERNEL_PROV="$(rel_env_get "$REL_ENV" KERNEL_PROVENANCE)"
[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "release.env: malformed RELEASE_TAG '$RELEASE_TAG'."
[[ "$ARCHIVE" == "katmate-os-$RELEASE_TAG.tar.gz" ]] || die "release.env: ARCHIVE '$ARCHIVE' is not katmate-os-$RELEASE_TAG.tar.gz."
echo "Release: $RELEASE_TAG"

rel_check_tree "$ARCHIVE" "katmate-os-$RELEASE_TAG" "$TREE"

# netVM's image must be the release-clean one (operator ruling R18): its
# metadata, shipped beside the image and covered by the signature, says so.
rel_check netvm.meta
NETVM_ROOT_UNLOCKED="$(rel_env_get "$(rel_path netvm.meta)" NETVM_ROOT_UNLOCKED)"
[[ "$NETVM_ROOT_UNLOCKED" == no ]] \
  || die "netvm.meta records NETVM_ROOT_UNLOCKED=${NETVM_ROOT_UNLOCKED:-<absent>}: a netVM image with an unlocked root is a dev image and is never installed."

# images.list: <file> <lv> <thin|linear> <bytes> <ro|rw> <allocated bytes>
rel_check images.list
declare -A IMG_LV=() IMG_KIND=() IMG_BYTES=() IMG_MODE=()
IMG_FILES=()
THIN_ALLOC=0
NETVM_BYTES=0
while read -r f lv kind bytes mode alloc rest; do
  [[ -n "${f:-}" ]] || continue
  [[ -z "${rest:-}" && "$f" =~ ^[a-z0-9-]+\.img\.zst$ && "$lv" =~ ^[a-z0-9_]+$ \
     && "$kind" =~ ^(thin|linear)$ && "$bytes" =~ ^[0-9]+$ && "$mode" =~ ^(ro|rw)$ \
     && "${alloc:-}" =~ ^[0-9]+$ ]] || die "images.list: malformed line: $f $lv $kind $bytes $mode ${alloc:-} ${rest:-}"
  IMG_FILES+=("$f"); IMG_LV[$f]="$lv"; IMG_KIND[$f]="$kind"; IMG_BYTES[$f]="$bytes"; IMG_MODE[$f]="$mode"
  if [[ "$kind" == thin ]]; then THIN_ALLOC=$(( THIN_ALLOC + alloc )); else NETVM_BYTES=$(( NETVM_BYTES + bytes )); fi
done < "$(rel_path images.list)"
# The set is fixed: the units and metas name these LVs.
for want in "foundation.img.zst vm_tpl_foundation thin ro" "app-web.img.zst vm_app_web thin ro" \
            "app-office.img.zst vm_app_office thin ro" "app-vault.img.zst vm_app_vault thin ro" \
            "netvm.img.zst vm_sys_netvm linear rw"; do
  read -r f lv kind mode <<<"$want"
  [[ "${IMG_LV[$f]:-}" == "$lv" && "${IMG_KIND[$f]}" == "$kind" && "${IMG_MODE[$f]}" == "$mode" ]] \
    || die "images.list does not carry $f as $lv ($kind, $mode)."
done
(( ${#IMG_FILES[@]} == 5 )) || die "images.list carries ${#IMG_FILES[@]} images, expected 5."
THIN_ALLOC_MB=$(( THIN_ALLOC / 1024 / 1024 + 1 ))
NETVM_MB=$(( (NETVM_BYTES + 1024 * 1024 - 1) / 1024 / 1024 ))
echo "Images: 5; ${THIN_ALLOC_MB} MiB allocated in the thin pool after import; netVM ${NETVM_MB} MiB linear."

# ---------------------------------------------------------------------------
# RAM (operator ruling, 2026-10-05, part 3): before anything touches a disk
# ---------------------------------------------------------------------------

RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
(( RAM_KB >= MIN_RAM_KB )) \
  || die "RAM: MemTotal is $(( RAM_KB / 1024 )) MiB. The alpha needs 16 GB (MemTotal at least $(( MIN_RAM_KB / 1024 )) MiB). All guests together commit up to 13 GiB; memfd memory without prealloc is allocated on use, so the sum is an upper bound, not a requirement (UNVERIFIED until measured on MINIS)."
echo "RAM: MemTotal $(( RAM_KB / 1024 )) MiB (minimum $(( MIN_RAM_KB / 1024 )) MiB)"

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
# Asked before anything is written to a disk, so a bad answer costs nothing.
# The password is hashed here, in the live system; the plaintext never
# reaches the target, and the hash reaches it only through chpasswd's stdin
# after postinstall.sh (no file). root gets no password: it is locked, and
# administration is through sudo and wheel (operator ruling R18).

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
  read -rsp "Password for $USERNAME: " PW1
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
# Desktop keyboard layout (XKB) — desktop/README.md, the 10-keyboard contract
# ---------------------------------------------------------------------------
# sway takes an XKB layout name (si, de, us), not the console keymap
# (slovene, de-latin1): the two name spaces differ, and a keymap name given to
# xkb_layout gives no layout. Asked separately; one or more, comma-separated.

log "Desktop keyboard layout"

XKB_LAYOUTS="$(localectl list-x11-keymap-layouts 2>/dev/null || true)"
if [[ -z "$XKB_LAYOUTS" && -r /usr/share/X11/xkb/rules/evdev.lst ]]; then
  XKB_LAYOUTS="$(awk '/^! layout/ {on = 1; next} /^!/ {on = 0} on && NF {print $1}' /usr/share/X11/xkb/rules/evdev.lst)"
fi
[[ -n "$XKB_LAYOUTS" ]] || echo "No XKB layout list in the live system: the layout is taken as given."

while :; do
  read -rp "Desktop keyboard layout(s), XKB names, e.g. si or si,us [us]: " XKB_LAYOUT
  XKB_LAYOUT="${XKB_LAYOUT:-us}"
  if [[ ! "$XKB_LAYOUT" =~ ^[a-z][a-z0-9_]*(,[a-z][a-z0-9_]*)*$ ]]; then
    echo "Not a layout list: '$XKB_LAYOUT'."
    continue
  fi
  bad=""
  if [[ -n "$XKB_LAYOUTS" ]]; then
    IFS=, read -ra parts <<<"$XKB_LAYOUT"
    for p in "${parts[@]}"; do grep -qxF -- "$p" <<<"$XKB_LAYOUTS" || bad+=" $p"; done
  fi
  [[ -z "$bad" ]] && break
  echo "Unknown XKB layout(s):$bad (see: localectl list-x11-keymap-layouts)."
done
echo "Desktop layout: $XKB_LAYOUT"

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
# netVM's NIC (operator ruling R9)
# ---------------------------------------------------------------------------
# The user picks exactly one PCI Ethernet controller (class 0x0200). It is
# bound to vfio-pci at every boot through its vendor:device id, and netVM
# takes it. Wireless controllers (0x0280) are not offered in the alpha.
#
# The binding is by id, so it takes EVERY device with that id: a NIC whose
# vendor:device another Ethernet controller shares is refused, because both
# would be bound and katmate-publish-nics pairs one label with exactly one
# bound device (it refuses otherwise; HOST-CONFIG §3, open problem #9, which
# stays open). The live system's own network is unaffected until the reboot.

log "netVM network card"

NIC_BDFS=()
for d in /sys/bus/pci/devices/*; do
  [[ "$(cat "$d/class" 2>/dev/null)" == 0x0200* ]] && NIC_BDFS+=("$(basename "$d")")
done
(( ${#NIC_BDFS[@]} > 0 )) || die "No PCI Ethernet controller found. netVM needs one (a wireless card is not supported in the alpha)."

nic_id() { printf '%s:%s' "$(sed 's/^0x//' "/sys/bus/pci/devices/$1/vendor")" "$(sed 's/^0x//' "/sys/bus/pci/devices/$1/device")"; }
i=0
for b in "${NIC_BDFS[@]}"; do
  i=$((i + 1))
  drv="$(basename "$(readlink -f "/sys/bus/pci/devices/$b/driver" 2>/dev/null)" 2>/dev/null || true)"
  grp="$(basename "$(readlink -f "/sys/bus/pci/devices/$b/iommu_group" 2>/dev/null)" 2>/dev/null || echo '?')"
  name=""
  command -v lspci >/dev/null && name="$(lspci -s "$b" 2>/dev/null | cut -d' ' -f2- || true)"
  nets=""
  for nd in "/sys/bus/pci/devices/$b/net"/*; do [[ -e "$nd" ]] && nets+="$(basename "$nd") "; done
  printf '  %d) %s  [%s]  driver=%s  iommu_group=%s  %s %s\n' "$i" "$b" "$(nic_id "$b")" "${drv:-none}" "$grp" "${nets:+if: $nets}" "$name"
done
while :; do
  read -rp "Card for netVM (1-${#NIC_BDFS[@]}): " n
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#NIC_BDFS[@]} )) && break
  echo "Pick a number from the list."
done
NIC_BDF="${NIC_BDFS[$((n - 1))]}"
NIC_ID="$(nic_id "$NIC_BDF")"
for b in "${NIC_BDFS[@]}"; do
  [[ "$b" != "$NIC_BDF" && "$(nic_id "$b")" == "$NIC_ID" ]] \
    && die "$b has the same id $NIC_ID as $NIC_BDF. vfio-pci binds by id, so both would go to netVM, and the boot-time label resolution refuses two bound devices (HOST-CONFIG §3). Not supported in the alpha."
done
NIC_DRIVER="$(basename "$(readlink -f "/sys/bus/pci/devices/$NIC_BDF/driver" 2>/dev/null)" 2>/dev/null || true)"
if [[ -z "$NIC_DRIVER" ]]; then
  NIC_DRIVER="$(modprobe --resolve-alias "$(cat "/sys/bus/pci/devices/$NIC_BDF/modalias")" 2>/dev/null | head -n 1 || true)"
fi
[[ "$NIC_DRIVER" =~ ^[A-Za-z0-9_-]+$ && "$NIC_DRIVER" != vfio-pci ]] \
  || die "Cannot determine the host driver of $NIC_BDF (got '${NIC_DRIVER:-none}'): the softdep that keeps it off the card needs its name."
# disable_idle_d3=1 is the RTL8125 workaround (state.md Invariants, FLReset-):
# a card without function-level reset is left half-initialised by vfio's
# reset, and the next VFIO_MAP_DMA fails. Set it when the kernel lists no
# `flr` among the card's reset methods, or cannot say.
NIC_D3=""
if ! grep -qw flr "/sys/bus/pci/devices/$NIC_BDF/reset_method" 2>/dev/null; then
  NIC_D3=" disable_idle_d3=1"
fi
# The rest of the card's IOMMU group, bridges aside (they never disqualify
# a group): preflight.sh rates isolation; this only shows it once more.
GRP_DIR="/sys/bus/pci/devices/$NIC_BDF/iommu_group/devices"
OTHERS=""
for g in "$GRP_DIR"/*; do
  gb="$(basename "$g")"
  [[ "$gb" == "$NIC_BDF" ]] && continue
  [[ "$(cat "$g/class" 2>/dev/null)" == 0x0604* ]] && continue
  OTHERS+=" $gb"
done
echo "netVM card: $NIC_BDF [$NIC_ID], host driver $NIC_DRIVER${NIC_D3:+, no FLR (disable_idle_d3=1)}"
if [[ -n "$OTHERS" ]]; then
  echo "WARNING: its IOMMU group also holds:$OTHERS. vfio can only pass a whole group; check the preflight report."
  read -rp "Continue with this card anyway (yes/no): " C
  [[ "$C" == "yes" ]] || die "Aborted by user."
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

# ---------------------------------------------------------------------------
# Disk size check and proportional layout
# ---------------------------------------------------------------------------

log "Disk size check"

DISK_BYTES="$(lsblk -b -d -o SIZE -n "$DISK")"
DISK_GB=$(( DISK_BYTES / 1024 / 1024 / 1024 ))

echo "Disk: ${DISK_GB}G"

(( DISK_GB >= MIN_DISK_GB )) || die "Disk too small: ${DISK_GB}G, minimum ${MIN_DISK_GB}G."

# Swap = RAM, rounded up to a whole GiB
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
(( RAM_KB % (1024*1024) > 0 )) && RAM_GB=$(( RAM_GB + 1 )) || true
SWAP_GB="${RAM_GB}"

# Root: 15% of the disk, min MIN_ROOT_GB, max MAX_ROOT_GB
ROOT_GB=$(( DISK_GB * 15 / 100 ))
(( ROOT_GB < MIN_ROOT_GB )) && ROOT_GB=${MIN_ROOT_GB}
(( ROOT_GB > MAX_ROOT_GB )) && ROOT_GB=${MAX_ROOT_GB}

# EFI: 512M, reserved as 1G in the calculation (rounded up)
EFI_GB=1

# vg0 outside the thin pool (R6): netVM's linear LV, its size from the
# release's image, plus a margin. The pool gets the rest, less its metadata
# and LVM's pmspare (the same size again).
REST_MB=$(( (DISK_GB - EFI_GB - ROOT_GB - SWAP_GB) * 1024 ))
TMETA_MB=$(( (REST_MB - NETVM_MB - NETVM_MARGIN_MB) / 100 ))
(( TMETA_MB < 64 ))    && TMETA_MB=64
(( TMETA_MB > 1024 ))  && TMETA_MB=1024
POOL_EST_MB=$(( REST_MB - NETVM_MB - NETVM_MARGIN_MB - 2 * TMETA_MB ))
POOL_NEED_MB=$(( THIN_ALLOC_MB + POOL_SLACK_MB ))

(( POOL_EST_MB >= POOL_NEED_MB )) \
  || die "Not enough space for the thin pool: about ${POOL_EST_MB} MiB, and the images need ${THIN_ALLOC_MB} MiB plus ${POOL_SLACK_MB} MiB of room. Use a larger disk."

echo ""
echo "Layout:"
echo "  EFI:        512M"
echo "  vg0/root:   ${ROOT_GB}G"
echo "  vg0/swap:   ${SWAP_GB}G"
echo "  vg0/${POOL}: ~$(( POOL_EST_MB / 1024 ))G thin pool (metadata ${TMETA_MB}M): images ${THIN_ALLOC_MB}M, ${#ALPHA_INSTANCES[@]} 10G home LVs"
echo "  vg0/vm_sys_netvm: ${NETVM_MB}M linear, plus ${NETVM_MARGIN_MB}M left free"
echo ""
read -rp "WIPE $DISK and apply this layout — everything on it will be erased (yes/no): " CONFIRM
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
vgcreate "$VG" /dev/mapper/cryptlvm

lvcreate -L "${ROOT_GB}G"  "$VG" -n root
lvcreate -L "${SWAP_GB}G"  "$VG" -n swap

# Thin pool vm_pool (R5), sized from what vg0 has left, measured now rather
# than estimated: netVM's linear LV and its margin stay outside (R6), and LVM
# needs the metadata size twice (the metadata LV and pmspare).
VG_FREE_MB="$(vgs --noheadings --units m --nosuffix -o vg_free "$VG" | awk '{printf "%d", $1}')"
POOL_MB=$(( VG_FREE_MB - NETVM_MB - NETVM_MARGIN_MB - 2 * TMETA_MB ))
(( POOL_MB >= POOL_NEED_MB )) \
  || die "vg0 has ${VG_FREE_MB} MiB free: the pool would be ${POOL_MB} MiB, below the ${POOL_NEED_MB} MiB the images need."
lvcreate --type thin-pool \
         -L "${POOL_MB}M" \
         --poolmetadatasize "${TMETA_MB}M" \
         "$VG" -n "$POOL"

# ---------------------------------------------------------------------------
# Filesystems
# ---------------------------------------------------------------------------

log "Filesystems"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "/dev/$VG/root"
mkswap "/dev/$VG/swap"

# ---------------------------------------------------------------------------
# Mount
# ---------------------------------------------------------------------------

log "Mount target"

mount "/dev/$VG/root" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot
swapon "/dev/$VG/swap"

mountpoint -q /mnt      || die "/mnt not mounted"
mountpoint -q /mnt/boot || die "EFI /boot not mounted"

# ---------------------------------------------------------------------------
# Pacman keyring
# ---------------------------------------------------------------------------

log "Pacman keyring"

pacman -Syy --noconfirm
pacman -S --noconfirm archlinux-keyring

# ---------------------------------------------------------------------------
# Pacstrap
# ---------------------------------------------------------------------------
# Desktop and session (operator ruling R16): sway with swaybg for its
# wallpaper, waybar, swaync, greetd with tuigreet, foot (R6 of the brief),
# PipeWire with WirePlumber (wpctl) and pipewire-pulse (waybar's volume module
# talks to a pulse server), brightnessctl, playerctl, grim, slurp,
# wl-clipboard, wf-recorder, libnotify (notify-send), xdg-utils (xdg-open, for
# km-shot), polkit, plymouth, and the GeistMono and Symbols Nerd fonts.
# e2fsprogs for the home LVs' ext4. Package names were checked by a web search
# only for otf-geist-mono-nerd, ttf-nerd-fonts-symbols, greetd-tuigreet,
# swaync and wf-recorder; the rest are UNVERIFIED until the Cubi install.
# No iwd and no wireguard-tools (operator ruling, 2026-10-05): the host has no
# network, its NIC is netVM's, and a VPN is the user's config in netVM
# (ADR-037). The live system's iwctl above is install-time only.

log "Pacstrap"

UCODE_PKG=""
[[ -n "$UCODE" ]] && UCODE_PKG="$UCODE"

pacstrap /mnt \
  base linux-hardened linux-hardened-headers linux-firmware ${UCODE_PKG} \
  lvm2 e2fsprogs \
  efibootmgr cryptsetup \
  micro sudo \
  nftables \
  qemu-full \
  plymouth \
  sway swaybg waybar swaync greetd greetd-tuigreet foot \
  pipewire wireplumber pipewire-pulse \
  brightnessctl playerctl grim slurp wl-clipboard wf-recorder libnotify xdg-utils \
  polkit \
  otf-geist-mono-nerd ttf-nerd-fonts-symbols

# ---------------------------------------------------------------------------
# fstab
# ---------------------------------------------------------------------------

log "fstab"

genfstab -U /mnt >> /mnt/etc/fstab

# ---------------------------------------------------------------------------
# Base configuration
# ---------------------------------------------------------------------------
# No network profile (operator ruling R11): the host has no network after
# installation. Its NIC is netVM's; nothing local needs systemd-networkd or
# systemd-resolved (VMs reach each other over AF_UNIX datagram sockets and
# the host over vsock), so neither is enabled, and /etc/resolv.conf is left
# as pacstrap wrote it.

log "Base config"

echo "$KM_HOSTNAME" > /mnt/etc/hostname

ln -sf /usr/share/zoneinfo/Europe/Zurich /mnt/etc/localtime

mkdir -p /mnt/etc/sudoers.d
echo '%wheel ALL=(ALL) ALL' >/mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel

# ---------------------------------------------------------------------------
# Guest images → LVs
# ---------------------------------------------------------------------------
# Each image is fetched (URL source) into the target's /var/tmp, checked
# against the signed SHA256SUMS, written to a fresh LV and read back byte for
# byte. Thin LVs are written sparse, so zero blocks stay unallocated in the
# pool; that is sound only because an unprovisioned thin block reads as
# zeros. netVM's linear LV is written in full: skipped blocks there would
# keep whatever the disk held, and the read-back would refuse it.
#
# The app layers arrive as full images and become standalone thin LVs, not
# thin snapshots of the foundation (operator ruling R4: delta export is
# post-alpha). Nothing at launch reads the snapshot origin.

log "Guest images"

rel_stage "$TARGET_STAGE"

import_image() {
  local f="$1" lv="${IMG_LV[$1]}" kind="${IMG_KIND[$1]}" bytes="${IMG_BYTES[$1]}" mode="${IMG_MODE[$1]}"
  local dev="/dev/$VG/$lv" src
  rel_check "$f"
  src="$(rel_path "$f")"
  ! lvs "$VG/$lv" >/dev/null 2>&1 || die "$VG/$lv already exists."
  if [[ "$kind" == thin ]]; then
    lvcreate -q -T "$VG/$POOL" -V "${bytes}B" -n "$lv"
  else
    lvcreate -q -y -L "${bytes}B" -n "$lv" "$VG"
  fi
  udevadm settle
  [[ -b "$dev" ]] || lvchange -K -ay "$VG/$lv"
  [[ -b "$dev" ]] || die "$dev did not appear."
  (( $(blockdev --getsize64 "$dev") >= bytes )) || die "$dev is smaller than $bytes bytes."
  if [[ "$kind" == thin ]]; then
    zstd -q -dc "$src" | dd of="$dev" bs=4M iflag=fullblock conv=sparse,fsync status=none
  else
    zstd -q -dc "$src" | dd of="$dev" bs=4M iflag=fullblock conv=fsync status=none
  fi
  cmp -n "$bytes" <(zstd -q -dc "$src") "$dev" || die "$dev does not read back as $f."
  [[ "$mode" == ro ]] && lvchange -q -p r "$VG/$lv"
  (( REL_IS_URL )) && rm -f -- "$src"
  echo "  $f -> $dev ($bytes bytes, $kind, $mode), read back equal"
}

for f in foundation.img.zst app-web.img.zst app-office.img.zst app-vault.img.zst netvm.img.zst; do
  import_image "$f"
done

# ---------------------------------------------------------------------------
# T2: image metadata, kernels (ADR-032 §5)
# ---------------------------------------------------------------------------

log "T2 metadata and kernels"

KS=/mnt/var/lib/katmate
install -d -m 0755 "$KS" "$KS/kernels" "$KS/netvm" "$KS/instances"

for m in foundation.meta app-web.meta app-office.meta app-vault.meta; do
  rel_check "$m"
  install -m 0644 "$(rel_path "$m")" "$KS/$m"
done
install -m 0644 "$(rel_path netvm.meta)" "$KS/netvm/netvm.meta"
rel_check netvm-vmlinuz
rel_check netvm-initrd.img
install -m 0644 "$(rel_path netvm-vmlinuz)" "$KS/netvm/vmlinuz"
install -m 0644 "$(rel_path netvm-initrd.img)" "$KS/netvm/initrd.img"

# The metas name the paths and LVs the units will use; read them back
# against what was just installed.
meta() { rel_env_get "$1" "$2"; }
[[ "$(meta "$KS/netvm/netvm.meta" NETVM_KERNEL)" == /var/lib/katmate/netvm/vmlinuz \
   && "$(meta "$KS/netvm/netvm.meta" NETVM_INITRD)" == /var/lib/katmate/netvm/initrd.img \
   && "$(meta "$KS/netvm/netvm.meta" NETVM_LV)" == "$VG/vm_sys_netvm" ]] \
  || die "netvm.meta names other paths or another LV than this installer placed."
[[ "$(meta "$KS/foundation.meta" FOUNDATION_LV)" == "$VG/vm_tpl_foundation" ]] \
  || die "foundation.meta does not name $VG/vm_tpl_foundation."
for t in web office vault; do
  [[ "$(meta "$KS/app-$t.meta" APP_LV)" == "$VG/vm_app_$t" ]] || die "app-$t.meta does not name $VG/vm_app_$t."
done

# The shared MicroVM kernel and its provenance sidecar (ADR-034: verification
# happens at install). A sidecar must describe this kernel; an absent one is
# allowed and recorded as such in foundation.meta.
KVER="$(meta "$KS/foundation.meta" KERNEL_VERSION)"
[[ "$KERNEL_FILE" == "vmlinuz-katmate-microvm-amd64-$KVER" ]] \
  || die "release.env KERNEL_FILE=$KERNEL_FILE, foundation.meta requires kernel $KVER."
rel_check "$KERNEL_FILE"
install -m 0644 "$(rel_path "$KERNEL_FILE")" "$KS/kernels/$KERNEL_FILE"
[[ "$(meta "$KS/foundation.meta" KERNEL_PROVENANCE)" == "$KERNEL_PROV" ]] \
  || die "release.env KERNEL_PROVENANCE=$KERNEL_PROV disagrees with foundation.meta."
if [[ "$KERNEL_PROV" == recorded ]]; then
  rel_check "$KERNEL_FILE.provenance"
  ksum="$(sed -n 's/^KERNEL_SHA256=//p' "$(rel_path "$KERNEL_FILE.provenance")" | head -n 1)"
  [[ "$ksum" == "$(sha256sum "$KS/kernels/$KERNEL_FILE" | awk '{print $1}')" ]] \
    || die "$KERNEL_FILE.provenance describes a different kernel (ADR-034)."
  install -m 0644 "$(rel_path "$KERNEL_FILE.provenance")" "$KS/kernels/$KERNEL_FILE.provenance"
  echo "  $KERNEL_FILE, provenance recorded and matching"
else
  [[ "$KERNEL_PROV" == absent ]] || die "release.env KERNEL_PROVENANCE='$KERNEL_PROV' is neither recorded nor absent."
  echo "  $KERNEL_FILE, provenance absent (ADR-034 allows it; foundation.meta says so)"
fi

# ---------------------------------------------------------------------------
# T1: /etc/katmate/vm/ (ADR-032 §1; operator ruling R10)
# ---------------------------------------------------------------------------
# Created from installer/t1/*.toml.in. The installer may CREATE a T1 file and
# never OVERWRITE one it did not create in the same run; on a fresh root
# there is none, and a file already present is a refusal, not a merge.

log "T1 instance properties"

install -d -m 0755 /mnt/etc/katmate /mnt/etc/katmate/vm
T1_CREATED=()
for tpl in "$TREE"/installer/t1/*.toml.in; do
  name="$(basename "$tpl" .toml.in)"
  dst="/mnt/etc/katmate/vm/$name.toml"
  [[ ! -e "$dst" && ! -L "$dst" ]] || die "$dst exists and was not created by this run: not overwritten (ADR-032 §1)."
  install -m 0644 -o root -g root "$tpl" "$dst"
  T1_CREATED+=("$name")
done
(( ${#T1_CREATED[@]} == 6 )) || die "Created ${#T1_CREATED[@]} T1 files, expected 6."
echo "  created: ${T1_CREATED[*]}"

# The manifest of each alpha instance, from its own T1 file: one source.
t1_manifest() { sed -n 's/^manifest[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "/mnt/etc/katmate/vm/$1.toml"; }

# ---------------------------------------------------------------------------
# Home LVs and instance deltas (operator ruling R7)
# ---------------------------------------------------------------------------
# The state.md form of record: vm_<instance>_home, 10G thin in vm_pool,
# ext4 with default options, user/ 1000:1000 0700. The delta is a qcow2 over
# the instance's app layer, as PARAMETERS.md records it, root:root 0644
# (QEMU runs as root; on MINIS they were made as `host`).

log "Home LVs and instance deltas"

HM="$(mktemp -d)"
for inst in "${ALPHA_INSTANCES[@]}"; do
  lv="vm_${inst}_home"
  lvcreate -q -V "$HOME_LV_SIZE" -T "$VG/$POOL" -n "$lv"
  udevadm settle
  attr="$(lvs --noheadings -o lv_attr "$VG/$lv" | tr -d ' ')"
  [[ "${attr:4:1}" == a ]] || die "$VG/$lv is not active after creation (lv_attr $attr)."
  mkfs.ext4 -q "/dev/$VG/$lv"
  mount "/dev/$VG/$lv" "$HM"
  install -d -o 1000 -g 1000 -m 0700 "$HM/user"
  umount "$HM"

  manifest="$(t1_manifest "$inst")"
  [[ "$manifest" =~ ^(web|office|vault)$ ]] || die "/etc/katmate/vm/$inst.toml: manifest '$manifest' has no app layer."
  arch-chroot /mnt qemu-img create -q -f qcow2 -F raw -b "/dev/$VG/vm_app_$manifest" \
    "/var/lib/katmate/instances/$inst.qcow2" "$DELTA_SIZE"
  chmod 0644 "/mnt/var/lib/katmate/instances/$inst.qcow2"
  echo "  $inst: $VG/$lv (ext4, user/ 1000:1000 0700), delta over $VG/vm_app_$manifest"
done
rmdir "$HM"

# ---------------------------------------------------------------------------
# KatMate host parts (T4) and host binaries
# ---------------------------------------------------------------------------
# host/usr/ is copied as it is in the signed tree, modes kept, owned root
# (HOST-CONFIG, ADR-032 §1). Read back: every path 0:0, nothing group- or
# world-writable.

log "KatMate host parts"

cp -a --no-preserve=ownership "$TREE/host/usr/." /mnt/usr/
HOSTN=0
while IFS= read -r -d '' rel; do
  m="$(stat -c '%u:%g %a' -- "/mnt/usr/$rel")" || die "/usr/$rel is in host/usr but not on the target."
  [[ "${m%% *}" == 0:0 ]] || die "/usr/$rel is owned ${m%% *} on the target."
  (( (8#${m##* } & 8#022) == 0 )) || die "/usr/$rel is mode ${m##* } on the target: group- or world-writable."
  HOSTN=$((HOSTN + 1))
done < <(cd "$TREE/host/usr" && find . -mindepth 1 -printf '%P\0')
echo "  $HOSTN paths from host/usr, all 0:0, none group/world-writable"

rel_check ping-client
rel_check waypipe
install -D -m 0755 "$(rel_path ping-client)" /mnt/usr/lib/katmate/ping-client
install -D -m 0755 "$(rel_path waypipe)" /mnt/opt/katmate/bin/waypipe

# netVM's card: bound to vfio-pci at every boot, before its own driver.
install -d -m 0755 /mnt/etc/modprobe.d
cat >/mnt/etc/modprobe.d/katmate-vfio.conf <<EOF
# Written by the KatMate installer (operator ruling R9): netVM's NIC,
# $NIC_BDF [$NIC_ID] at install time. Bound by id, so any card with this id.
options vfio-pci ids=$NIC_ID$NIC_D3
softdep $NIC_DRIVER pre: vfio-pci
EOF
chmod 0644 /mnt/etc/modprobe.d/katmate-vfio.conf

# topoext on AMD hosts only (operator ruling R9): katmate-sys-driver@'s
# -cpu host${KM_CPU_FLAGS}.
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
  install -d -m 0755 /mnt/etc/systemd/system/katmate-sys-driver@.service.d
  printf '[Service]\nEnvironment=KM_CPU_FLAGS=,topoext=on\n' \
    >/mnt/etc/systemd/system/katmate-sys-driver@.service.d/10-cpu.conf
  chmod 0644 /mnt/etc/systemd/system/katmate-sys-driver@.service.d/10-cpu.conf
fi

# The menu's one sudo rule, for the user created here (HOST-CONFIG §13,
# SECURITY-MODEL gap 17; operator ruling R12). Checked with visudo in the
# chroot by postinstall.sh, before anything relies on it.
printf '%s ALL=(root) NOPASSWD: /usr/lib/katmate/katmate-launch\n' "$USERNAME" \
  >/mnt/etc/sudoers.d/katmate-launch
chmod 0440 /mnt/etc/sudoers.d/katmate-launch

# The GUI path's host end, for every user's manager (R12; HOST-CONFIG §11).
install -D -m 0644 "$TREE/installer/files/waypipe-client.service" /mnt/etc/systemd/user/waypipe-client.service

# ---------------------------------------------------------------------------
# Desktop (desktop/README.md, Deployment; operator rulings R13, R14)
# ---------------------------------------------------------------------------
# System paths only: no file names a user's home.

log "Desktop"

DT="$TREE/desktop"
install -D -m 0644 "$DT/sway/config" /mnt/etc/sway/config
# sway/config includes outputs.conf, resolved beside it. Empty: outputs are
# configured per machine, and nothing is known about them at install (R13).
install -m 0644 /dev/null /mnt/etc/sway/outputs.conf
install -d -m 0755 /mnt/etc/sway/config.d
{
  echo "# Written by the KatMate installer: the desktop keyboard layout (desktop/README.md)."
  echo "input type:keyboard {"
  printf '    xkb_layout  "%s"\n' "$XKB_LAYOUT"
  echo "}"
} >/mnt/etc/sway/config.d/10-keyboard.conf
chmod 0644 /mnt/etc/sway/config.d/10-keyboard.conf

install -m 0644 -D -t /mnt/etc/xdg/waybar/ \
  "$DT/waybar/config-sway.jsonc" "$DT/waybar/modules-cybrbar.jsonc" \
  "$DT/waybar/modules-sway.jsonc" "$DT/waybar/modules-katmate.jsonc" \
  "$DT/waybar/style-cybrbar.css" "$DT/waybar/style-sway.css"
install -m 0644 -D -t /mnt/etc/xdg/waybar/svg/ "$DT/waybar/svg/no1-right.svg" \
  "$DT/waybar/svg/no1-cut-br.svg" "$DT/waybar/svg/katmate-mark.svg"
install -m 0644 -D -t /mnt/usr/share/katmate/waybar/ "$DT/waybar/katmate-menu.xml" "$DT/waybar/power-menu.xml"
install -m 0755 -D -t /mnt/usr/local/bin/ \
  "$DT/bin/km-launch" "$DT/bin/km-shot" "$DT/bin/sway-session" "$DT/bin/sway-quiet"
install -m 0644 -D -t /mnt/usr/share/backgrounds/katmate/ "$DT"/wallpapers/*.jpg

install -m 0644 -D "$DT/greetd/config.toml" /mnt/etc/greetd/config.toml
install -m 0644 -D -t /mnt/etc/greetd/sessions/ "$DT/greetd/wayland-sessions/sway.desktop"

# Plymouth (operator ruling R15): the two-step theme, built from the spinner
# theme's images and the 256 px logo as its watermark.
SPIN=/mnt/usr/share/plymouth/themes/spinner
PT=/mnt/usr/share/plymouth/themes/katmate
compgen -G "$SPIN/*.png" >/dev/null || die "No spinner theme images in $SPIN: the plymouth package layout is not the one this installer expects."
install -d -m 0755 "$PT"
install -m 0644 "$SPIN"/*.png "$PT/"
install -m 0644 "$DT/plymouth/logo-256.png" "$PT/watermark.png"
install -m 0644 "$DT/plymouth/katmate.plymouth" "$PT/katmate.plymouth"
install -d -m 0755 /mnt/etc/plymouth
printf '[Daemon]\nTheme=katmate\n' >/mnt/etc/plymouth/plymouthd.conf
chmod 0644 /mnt/etc/plymouth/plymouthd.conf

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

install -m700 "$TREE/installer/postinstall.sh" /mnt/root/postinstall.sh

# ---------------------------------------------------------------------------
# Chroot → postinstall
# ---------------------------------------------------------------------------

log "Chroot postinstall"

arch-chroot /mnt /root/postinstall.sh
rm -f /mnt/root/install.env /mnt/root/postinstall.sh

# ---------------------------------------------------------------------------
# Password (the user only; root is locked by postinstall.sh)
# ---------------------------------------------------------------------------

log "Password"

printf '%s:%s\n' "$USERNAME" "$PW_HASH" | arch-chroot /mnt chpasswd -e
unset PW_HASH

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

# Boot entry. `splash` starts plymouth (operator ruling R15); if plymouthd
# fails, the encrypt hook asks for the passphrase on the text console.
mkdir -p /mnt/boot/loader/entries
cat >/mnt/boot/loader/entries/katmate.conf <<ENTRY
title   Katmate OS
linux   /vmlinuz-linux-hardened
initrd  /${UCODE}.img
initrd  /initramfs-linux-hardened.img
options cryptdevice=UUID=${LUKS_UUID}:cryptlvm root=/dev/$VG/root rw quiet splash loglevel=3${IOMMU_PARAM:+ ${IOMMU_PARAM}}
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

# shellcheck disable=SC2016  # literal awk program and '$6$' prefix
[[ "$(awk -F: -v u="$USERNAME" '$1 == u {print substr($2, 1, 3)}' /mnt/etc/shadow)" == '$6$' ]] \
  || die "/etc/shadow: $USERNAME has no SHA-512 password hash"
# Root is locked: its password field starts with '!' (passwd -l), whatever
# passwd reported (R18).
[[ "$(awk -F: '$1 == "root" {print substr($2, 1, 1)}' /mnt/etc/shadow)" == '!' ]] \
  || die "/etc/shadow: root is not locked"
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
[[ "$OPTS" == *" splash "* ]] || die "splash missing from the boot entry"

# No network profile on the host (R11).
[[ -z "$(ls -A /mnt/etc/systemd/network 2>/dev/null)" ]] || die "/etc/systemd/network on the target is not empty: the host keeps no network profile"

# The alpha's KatMate set.
for lv in vm_tpl_foundation vm_app_web vm_app_office vm_app_vault vm_sys_netvm \
          vm_app_web_home vm_app_personal_home vm_app_work_home vm_app_vault_home \
          vm_app_sandbox_home; do
  lvs "$VG/$lv" >/dev/null 2>&1 || die "LV $VG/$lv missing"
done
for f in /mnt/etc/katmate/vm/{netvm,app_web,app_personal,app_work,app_vault,app_sandbox}.toml \
         /mnt/var/lib/katmate/{foundation,app-web,app-office,app-vault}.meta \
         /mnt/var/lib/katmate/netvm/{netvm.meta,vmlinuz,initrd.img} \
         "/mnt/var/lib/katmate/kernels/$KERNEL_FILE" \
         /mnt/var/lib/katmate/instances/{app_web,app_personal,app_work,app_vault,app_sandbox}.qcow2 \
         /mnt/usr/lib/katmate/ping-client /mnt/opt/katmate/bin/waypipe \
         /mnt/etc/sudoers.d/katmate-launch /mnt/etc/modprobe.d/katmate-vfio.conf \
         /mnt/etc/sway/config /mnt/etc/sway/outputs.conf /mnt/etc/sway/config.d/10-keyboard.conf \
         /mnt/etc/greetd/config.toml /mnt/etc/greetd/sessions/sway.desktop \
         /mnt/usr/share/plymouth/themes/katmate/katmate.plymouth; do
  [[ -f "$f" ]] || die "missing on the target: ${f#/mnt}"
done
# Enablement as systemd reads it, not as symlinks this script guesses at.
for u in greetd.service katmate-sys-driver@netvm.service; do
  [[ "$(arch-chroot /mnt systemctl is-enabled "$u" 2>/dev/null || true)" == enabled ]] \
    || die "$u is not enabled on the target"
done
[[ "$(arch-chroot /mnt systemctl --global is-enabled waypipe-client.service 2>/dev/null || true)" == enabled ]] \
  || die "waypipe-client.service is not enabled globally on the target"
[[ "$(rel_env_get /mnt/var/lib/katmate/netvm/netvm.meta NETVM_ROOT_UNLOCKED)" == no ]] \
  || die "netvm.meta on the target does not record NETVM_ROOT_UNLOCKED=no"

log "Boot files"
find /mnt/boot -maxdepth 4 -type f | sort

log "DONE"
echo ""
echo "Installation of KatMate $RELEASE_TAG complete."
echo "Remove the installation medium and reboot."
echo ""
echo "To inspect the target before rebooting: KEEP_MOUNTS=yes ./install.sh"
