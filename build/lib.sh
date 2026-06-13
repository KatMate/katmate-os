# Katmate OS — build pipeline helpers (ADR-011)
# Sourced by foundation.sh and app-layer.sh. Not executed directly.
#
# Guests use direct kernel boot (ADR-005), so images carry a BARE ext4
# filesystem on the whole device — no partition table, no ESP. nbd therefore
# exposes the filesystem directly at $NBD (e.g. /dev/nbd0), not $NBD'p1'.

log() { echo -e "\n==> $*"; }
die() { echo -e "\nERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Must run as root (nbd/mount/chroot). Use: sudo make <target>"
}

# state for cleanup()
NBD_CONNECTED=""
MOUNTED=""

nbd_connect() {
  local img="$1"
  modprobe nbd max_part=8
  qemu-nbd --connect="$NBD" "$img"
  NBD_CONNECTED="$NBD"
  udevadm settle 2>/dev/null || true
  sleep 1
}

nbd_disconnect() {
  [[ -n "$NBD_CONNECTED" ]] || return 0
  qemu-nbd --disconnect "$NBD_CONNECTED" >/dev/null 2>&1 || true
  NBD_CONNECTED=""
}

# Mount whole-device bare ext4 + pseudo-filesystems for chroot.
mount_root() {
  local mnt="$1"
  mount "$NBD" "$mnt"
  MOUNTED="$mnt"
  mount -t proc  proc "$mnt/proc"
  mount -t sysfs sys  "$mnt/sys"
  mount --rbind  /dev "$mnt/dev"
  mount --make-rslave "$mnt/dev"
}

umount_root() {
  [[ -n "$MOUNTED" ]] || return 0
  umount -R "$MOUNTED" 2>/dev/null || true
  MOUNTED=""
}

# trap target — safe to call multiple times, runs in reverse dependency order.
cleanup() {
  umount_root
  nbd_disconnect
}

# Run a command inside the chroot with a sane non-interactive apt env.
chroot_run() {
  local mnt="$1"; shift
  chroot "$mnt" /usr/bin/env DEBIAN_FRONTEND=noninteractive "$@"
}
