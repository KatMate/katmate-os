#!/usr/bin/env bash
# Katmate OS — generic app-layer builder (ADR-014, ADR-011, LVM-thin per ADR-010)
# Usage: app-layer.sh <type>     (reads manifests/<type>.list)
#
# Produces an RO-frozen thin SNAPSHOT  vm_app_<type>  of vm_tpl_foundation:
#   lvcreate -s  ->  lvchange -K -ay  ->  mount  ->  chroot apt install
#   ->  umount  ->  lvchange --permission r  (freeze)
# No nbd, no qemu-img, no flatten — the thin-snapshot relationship stores the
# foundation once and keeps the chain three-level (foundation <- app <- instance).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib.sh"

require_root

TYPE="${1:?usage: app-layer.sh <type>  (manifest: manifests/<type>.list)}"
MANIFEST="$MANIFESTS/$TYPE.list"
APP_LV="${APP_LV_PREFIX}${TYPE}"          # e.g. vm_app_web
MNT="$(mktemp -d)"
trap 'cleanup; rmdir "$MNT" 2>/dev/null || true' EXIT

[[ -f "$MANIFEST" ]] || die "Missing manifest: $MANIFEST"

# foundation must exist and be frozen RO (built by: sudo make foundation)
lvs "$VG/$FOUNDATION_LV" >/dev/null 2>&1 \
  || die "Missing foundation LV: $VG/$FOUNDATION_LV (run: sudo make foundation)"

# refuse to clobber an existing app-layer — rebuild is an explicit drop first
if lvs "$VG/$APP_LV" >/dev/null 2>&1; then
  die "App-layer $VG/$APP_LV already exists. Remove it first: sudo lvremove -f $VG/$APP_LV"
fi

# package list = non-empty, non-comment lines
mapfile -t PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")
[[ ${#PKGS[@]} -gt 0 ]] || die "Manifest $MANIFEST lists no packages"

log "Snapshot $FOUNDATION_LV -> $APP_LV (thin, writable until freeze)"
lv_snapshot_create "$APP_LV" "$FOUNDATION_LV"

log "Activate $APP_LV (-K -ay: clears skip-activation flag) + mount"
lv_activate "$APP_LV"
mount_root "$APP_LV" "$MNT"

cp /etc/resolv.conf "$MNT/etc/resolv.conf"   # build-time DNS only

log "Install manifest: ${PKGS[*]}"
chroot_run "$MNT" apt-get update
chroot_run "$MNT" apt-get install -y "${PKGS[@]}"

log "Cleanup inside image"
chroot_run "$MNT" apt-get clean
rm -f "$MNT/etc/resolv.conf"
rm -rf "$MNT"/var/lib/apt/lists/* 2>/dev/null || true

log "Unmount + deactivate, then RO-freeze"
umount_root
lv_deactivate
lv_freeze "$APP_LV"

# freeze succeeded — disarm the half-built-snapshot removal in cleanup
SNAP_CREATED=""
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

log "$APP_LV ready: RO-frozen thin snapshot of $FOUNDATION_LV"
log "Reminder: 'lvchange -K -ay $VG/$APP_LV' is required before each instance boot."
