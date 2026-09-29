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

# --- the image's resolver link (ADR-038 §7) -----------------------------------
# An AppVM's resolver is /run/resolv.conf, written by katmate-init on the tmpfs
# it mounts; the image carries /etc/resolv.conf as a link to it. The link is
# RELATIVE, ../run/resolv.conf, as a defence: the build runs `cp` on the host,
# and through an absolute /run/resolv.conf link that `cp` resolves on the host
# and overwrites the HOST's /run/resolv.conf when that file exists, and
# otherwise fails the build (GNU coreutils refuses to write through a dangling
# link; measured with 9.11). Relative, it resolves inside $mnt. The builds copy
# explicitly into "$mnt/run/resolv.conf" in any case (never through the link),
# and the copy is removed here: left in the image, it would sit beneath init's
# /run tmpfs for good.

# Remove the build-time copy and make /etc/resolv.conf the relative link,
# replacing whatever is there (a regular file on a fresh debootstrap).
resolv_link_install() {
  local mnt="$1"
  rm -f "$mnt/run/resolv.conf"
  ln -sfn ../run/resolv.conf "$mnt/etc/resolv.conf"
}

# Read-back: die unless /etc/resolv.conf is exactly the relative link and no
# /run/resolv.conf (file or link) exists in the image. Run before freeze, and by
# app-layer.sh on the foundation it snapshots, so a layer built before this
# change is refused rather than extended.
resolv_link_check() {
  local mnt="$1" got
  got="$(readlink "$mnt/etc/resolv.conf" || true)"
  [[ "$got" == "../run/resolv.conf" ]] \
    || die "$mnt/etc/resolv.conf is not the relative link ../run/resolv.conf (ADR-038 §7): $(ls -ld "$mnt/etc/resolv.conf" 2>&1)"
  [[ ! -e "$mnt/run/resolv.conf" && ! -L "$mnt/run/resolv.conf" ]] \
    || die "$mnt/run/resolv.conf exists in the image (ADR-038 §7: the build-time copy must be removed): $(ls -ld "$mnt/run/resolv.conf" 2>&1)"
}

# Run a command inside the chroot with a sane non-interactive apt env.
chroot_run() {
  local mnt="$1"; shift
  chroot "$mnt" /usr/bin/env DEBIAN_FRONTEND=noninteractive "$@"
}

# --- kernel provenance (ADR-034) ---------------------------------------------
# Establish what provenance record accompanies the kernel this build is about to
# use, and refuse if that record describes a DIFFERENT kernel. ADR-034's
# acceptance note (2026-09-01) § G puts this in the preflight and not at the end:
# "a mismatch fails BEFORE the expensive build rather than after the image is
# frozen and its metadata already written."
#
# THIS IS THE ONLY FUNCTION IN THIS FILE THAT RETURNS A VALUE ON STDOUT.
# It prints `absent` or `recorded`, which foundation.sh captures into
# KERNEL_PROVENANCE for foundation.meta (§ B: the field carries recorded|absent
# and NEVER a hash — a hash there would be a second copy of a value that already
# lives in the sidecar). Every diagnostic therefore goes to stderr, so a caller
# writing KERNEL_PROVENANCE="$(kernel_provenance_check ...)" captures the value
# and nothing else.
#
# The caller MUST keep `set -e`. die() runs inside the command-substitution
# subshell, so its exit(1) ends that subshell rather than the script; the
# assignment then carries status 1 and `set -e` stops the build. Wrapping the
# call in `|| true`, or dropping `set -e`, silently turns every die below into
# an empty KERNEL_PROVENANCE and a build that continues.
#
# The sidecar path is DERIVED here and never passed in: <image>.provenance, the
# same derivation tools/capture-kernel-provenance makes. Passing it as a
# parameter would let the two ends disagree about which record describes which
# kernel, and that binding is what the file exists for.
#
# The sidecar is PARSED, never sourced. It is deliberately not sourceable —
# BANNER carries spaces and unescaped parentheses, so `. file` fails on it
# (tools/capture-kernel-provenance:46-53 states this and why). ^KEY= with sed,
# exactly as build/app-layer.sh:101 meta_get() already reads foundation.meta.
#
# Absent is not refused (ADR-034): a kernel with no sidecar still builds and the
# meta records KERNEL_PROVENANCE=absent, stating honestly that provenance was not
# recorded rather than implying it was. But a MALFORMED record is not an absent
# one and is never flattened into one — a sidecar that exists and cannot be read,
# or that carries no KERNEL_SHA256, is a die.
#
# A sidecar recording AUTOCONF_MATCH=no or IMAGE_MATCH=no WARNS and does not
# refuse, and KERNEL_PROVENANCE still reads `recorded` — because it was. The
# field records whether a capture happened; whether the pairing held is the
# sidecar's own business and lives in exactly one place. Refusing here would
# reject a kernel ADR-034 explicitly allows to exist, and would repeat the error
# its own -dirty finding names: "a refusal keyed on the banner would have blocked
# the better-documented of the two kernels and passed the worse."
kernel_provenance_check() {
  local image="$1"                       # the vmlinuz this build will use
  local sidecar="$image.provenance"      # derived, never a parameter
  local recorded_sha actual_sha field value

  if [[ ! -e "$sidecar" ]]; then
    echo "absent"
    return 0
  fi

  [[ -f "$sidecar" && -r "$sidecar" ]] || die "Provenance sidecar exists but cannot be read: $sidecar
A record that cannot be read is not the same as no record. Refusing rather than
writing KERNEL_PROVENANCE=absent, which would claim this kernel was never captured."

  recorded_sha="$(sed -n 's/^KERNEL_SHA256=//p' "$sidecar" | head -n1)"
  [[ -n "$recorded_sha" ]] || die "Provenance sidecar carries no KERNEL_SHA256: $sidecar
A malformed record is not an absent one and is not flattened into one (ADR-034)."

  actual_sha="$(sha256sum -- "$image" | awk '{print $1}')"
  [[ "$recorded_sha" == "$actual_sha" ]] || die "Provenance sidecar describes a different kernel than the one being built in.
  sidecar:  $sidecar
  records:  $recorded_sha
  actual:   $actual_sha
  image:    $image
This is the case this check exists for. Re-capture in the kernel build tree with
tools/capture-kernel-provenance, or remove the stale sidecar."

  # Captured, but the capture may record that a pairing could not be established.
  # Warn, name the field, never refuse. KERNEL_PROVENANCE stays `recorded`.
  for field in AUTOCONF_MATCH IMAGE_MATCH; do
    value="$(sed -n "s/^$field=//p" "$sidecar" | head -n1)"
    if [[ "$value" == "no" ]]; then
      echo "WARNING (ADR-034): $sidecar records $field=no." >&2
      echo "  The kernel IS captured and KERNEL_PROVENANCE stays 'recorded'; what" >&2
      echo "  could not be established is that one pairing. Not a refusal." >&2
    fi
  done

  echo "recorded"
}
