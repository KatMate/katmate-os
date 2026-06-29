# Katmate OS — build pipeline helpers (ADR-011, LVM-thin per ADR-010 rev 2026-06)
# Sourced by foundation.sh and app-layer.sh. Not executed directly.
#
# Guests use direct kernel boot (ADR-005): a BARE ext4 filesystem on the whole
# device — no partition table, no ESP. The app-layer is an LVM thin SNAPSHOT of
# the frozen foundation; we mount the LV block device directly (/dev/$VG/$lv),
# there is no nbd and no qcow2 in the layering path (qcow2 survives only as the
# deploy-time per-instance RW delta — not built here).

log() { echo -e "\n==> $*"; }
die() { echo -e "\nERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Must run as root (lvm/mount/chroot). Use: sudo make <target>"
}

# --- state for cleanup() -----------------------------------------------------
MOUNTED=""          # mountpoint of the app-layer root, if mounted
ACTIVE_LV=""        # vg/lv we activated and must deactivate on cleanup
SNAP_CREATED=""     # vg/lv of a snapshot we created (for failure rollback)
FREEZE_DONE=""      # set once the snapshot is RO-frozen (then we do NOT remove it)

# Create a thin snapshot of the frozen foundation. Snapshot originates WRITABLE
# (Vwi) — required so the manifest can be installed before the RO-freeze.
# Proven command (no --size, no -T: origin is already a thin LV):
#     lvcreate -s --name <snap> <vg>/<origin>
lv_snapshot_create() {
  local snap="$1" origin="$2"      # bare LV names
  lvcreate -s --name "$snap" "$VG/$origin"
  SNAP_CREATED="$VG/$snap"
}

# Create a fresh thin LV in the pool (the foundation base). Originates WRITABLE
# so debootstrap + the manifest install can run before the RO-freeze. Unlike a
# thin snapshot, this needs the pool (-T $VG/$POOL) and a virtual size (-V).
#     lvcreate -T $VG/$POOL -V <size> --name <lv>
lv_thin_create() {
  local lv="$1" size="$2"          # bare LV name, e.g. 8G
  lvcreate -T "$VG/$POOL" -V "$size" --name "$lv"
  SNAP_CREATED="$VG/$lv"           # reuse the failure-rollback slot
}

# RO-frozen thin LVs (and fresh thin snapshots) carry the skip-activation 'k'
# flag; the device node does NOT appear without an explicit -K -ay. Mandatory
# before mount, exactly as the app_web.con launcher does in pre-flight.
lv_activate() {
  local lv="$1"                    # bare LV name
  lvchange -K -ay "$VG/$lv"
  ACTIVE_LV="$VG/$lv"
  udevadm settle 2>/dev/null || true
}

# Mount whole-device bare ext4 + pseudo-filesystems for chroot.
mount_root() {
  local lv="$1" mnt="$2"           # bare LV name, mountpoint
  mount "/dev/$VG/$lv" "$mnt"
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

lv_deactivate() {
  [[ -n "$ACTIVE_LV" ]] || return 0
  lvchange -an "$ACTIVE_LV" 2>/dev/null || true
  ACTIVE_LV=""
}

# RO-freeze the snapshot. Proven: lvchange -p r (= --permission r).
lv_freeze() {
  local lv="$1"
  lvchange --permission r "$VG/$lv"
  FREEZE_DONE=1
}

# trap target — safe to call multiple times, reverse dependency order.
# If we created a snapshot but did NOT reach the freeze, the build failed
# mid-way: remove the half-built snapshot so a re-run starts clean.
cleanup() {
  umount_root
  lv_deactivate
  if [[ -n "$SNAP_CREATED" && -z "$FREEZE_DONE" ]]; then
    log "Build did not complete — removing half-built snapshot $SNAP_CREATED"
    lvchange -an "$SNAP_CREATED" 2>/dev/null || true
    lvremove -f "$SNAP_CREATED" 2>/dev/null || true
  fi
  SNAP_CREATED=""
}

# Run a command inside the chroot with a sane non-interactive apt env.
chroot_run() {
  local mnt="$1"; shift
  chroot "$mnt" /usr/bin/env DEBIAN_FRONTEND=noninteractive "$@"
}
