#!/usr/bin/env bash
# Katmate OS — generic app-layer builder (ADR-014, ADR-011, LVM-thin per ADR-010)
# Usage: app-layer.sh <type>     (reads manifests/<type>.toml, ADR-043 §6)
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
# The manifest reader is katmate-lib.sh's, sourced from the tree (cu2 ruling D3).
# shellcheck disable=SC2034
KM_PROG="app-layer"
# shellcheck source=host/usr/lib/katmate/katmate-lib.sh
source "$ROOT_DIR/host/usr/lib/katmate/katmate-lib.sh"

require_root

TYPE="${1:?usage: app-layer.sh <type>  (manifest: manifests/<type>.toml)}"

# The repo's manifests/ is the T3 source. No T1 tier here: the host never
# builds a user layer (ADR-043 §1).
km_manifest_read "$TYPE" "$MANIFESTS" ""
PKGS=("${KM_MF_PACKAGES[@]}")

# The one canonical RUN list. The guest's /etc/katmate/run-whitelist (one name
# per line) and the meta's RUN= (space-separated) are both written from it, in
# the manifest's order (cu2 ruling D5).
RUN_LIST=("${KM_MF_RUN[@]}")
RUN_WHITELIST_BYTES="$(printf '%s\n' "${RUN_LIST[@]}")"$'\n'
RUN_META="${RUN_LIST[*]}"

APP_LV="${APP_LV_PREFIX}${TYPE}"          # e.g. vm_app_web
MNT="$(mktemp -d)"
trap 'cleanup; rmdir "$MNT" 2>/dev/null || true' EXIT

# foundation must exist and be frozen RO (built by: sudo make foundation)
lvs "$VG/$FOUNDATION_LV" >/dev/null 2>&1 \
  || die "Missing foundation LV: $VG/$FOUNDATION_LV (run: sudo make foundation)"

# foundation.meta is the provenance source for the app-layer meta written at the
# end of this script. Checked HERE, in the preflight, because failing after the
# snapshot exists would waste a full debootstrap-scale apt run — and because a
# meta that records provenance as "unknown" is worse than no meta: it is the
# silent-wrong-object shape this project keeps finding.
[[ -r "$FOUNDATION_META" ]] \
  || die "Missing or unreadable $FOUNDATION_META — the foundation LV exists but
       its metadata does not, so this app-layer's provenance cannot be recorded.
       Rebuild the foundation (sudo make foundation), or re-run foundation.sh's
       final meta block by hand."

# refuse to clobber an existing app-layer — rebuild is an explicit drop first
if lvs "$VG/$APP_LV" >/dev/null 2>&1; then
  die "App-layer $VG/$APP_LV already exists. Remove it first: sudo lvremove -f $VG/$APP_LV"
fi

log "Snapshot $FOUNDATION_LV -> $APP_LV (thin, writable until freeze)"
lv_snapshot_create "$APP_LV" "$FOUNDATION_LV"

log "Activate $APP_LV (-K -ay: clears skip-activation flag) + mount"
lv_activate "$APP_LV"
mount_root "$APP_LV" "$MNT"

# Build-time DNS only (ADR-038 §7). The foundation must already carry the
# relative /etc/resolv.conf -> ../run/resolv.conf link; one built before that
# change is refused here, loudly, rather than extended. The copy goes
# explicitly into the image's /run — never through the link — and the chroot's
# apt reaches it through the link. Cleanup removes it and reads the link back.
resolv_link_check "$MNT"
cp /etc/resolv.conf "$MNT/run/resolv.conf"

log "Install manifest: ${PKGS[*]}"
chroot_run "$MNT" apt-get update
chroot_run "$MNT" apt-get install -y "${PKGS[@]}"

log "Cleanup inside image"
chroot_run "$MNT" apt-get clean
resolv_link_install "$MNT"
resolv_link_check "$MNT"
rm -rf "$MNT"/var/lib/apt/lists/* 2>/dev/null || true

# vm-agent reads this once at start and refuses every RUN without it (ADR-043 §5).
log "Write /etc/katmate/run-whitelist: $RUN_META"
[[ ! -L "$MNT/etc/katmate" && ! -L "$MNT/etc/katmate/run-whitelist" ]] \
  || die "the image carries a symlink at /etc/katmate or /etc/katmate/run-whitelist"
WL_TMP="$(mktemp)"
printf '%s' "$RUN_WHITELIST_BYTES" >"$WL_TMP"
install -D -m 0644 -o root -g root "$WL_TMP" "$MNT/etc/katmate/run-whitelist"
rm -f -- "$WL_TMP"
cmp -s <(printf '%s' "$RUN_WHITELIST_BYTES") "$MNT/etc/katmate/run-whitelist" \
  || die "read-back: /etc/katmate/run-whitelist in the image differs from the manifest's run list"
[[ "$(stat -c '%u:%g %a' "$MNT/etc/katmate/run-whitelist")" == "0:0 644" ]] \
  || die "read-back: /etc/katmate/run-whitelist in the image is not root:root 0644"

log "Unmount + deactivate, then RO-freeze"
umount_root
lv_deactivate
lv_freeze "$APP_LV"

# freeze succeeded — disarm the half-built-snapshot removal in cleanup
SNAP_CREATED=""
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

# ---- write app-<type>.meta (ADR-030 T2, ADR-032 §5) -------------------------
# Host-side metadata for this image, on the foundation.meta pattern and with
# foundation.sh's ordering, for the same two reasons stated there:
#  * AFTER the RO-freeze, so the meta never describes a half-built layer;
#  * AFTER the rollback trap is disarmed, so a meta-write failure dies loudly
#    (set -e) instead of destroying a valid frozen LV.
#
# What this closes: foundation.meta already records FOUNDATION_LV, so the base
# LV's NAME was never missing. What was missing is per-app-layer PROVENANCE —
# nothing tied a given app layer to the foundation GENERATION it was snapshotted
# from. A name is a constant; BASE_BUILT is the discriminator.
#
# Deliberately NOT recorded here: the waypipe tag. ADR-019 makes foundation.meta
# the single source for the version-lock gate, and copying the tag into every
# app-layer meta would be a second record of the fact the gate reads. Provenance
# needs to identify the generation, not restate its contents.
#
# KIND and RUN are the manifest's, never the layer's (ADR-043 §2, §5). The
# layer's foundation is BASE_BUILT; there is no separate FOUNDATION key (cu2
# ruling D1).
#
# KERNEL_VERSION is the kernel this image REQUIRES, not where it lies
# (ADR-032 §5). Today every image records the same one.
log "Write $KATMATE_STATE_DIR/app-$TYPE.meta"

# foundation.meta is flat KEY=value; read it without sourcing (it is root-owned
# under /var/lib, but a build script should not execute a data file to read it).
meta_get() { sed -n "s/^$1=//p" "$FOUNDATION_META" | head -n1; }
BASE_BUILT="$(meta_get BUILD_DATE)"
BASE_LV_RECORDED="$(meta_get FOUNDATION_LV)"
[[ -n "$BASE_BUILT" ]] \
  || die "$FOUNDATION_META records no BUILD_DATE — cannot establish provenance"

# The foundation we just snapshotted must be the one the meta describes, or the
# provenance we are about to write is a plausible lie. Cheap check, and exactly
# the class of silent mismatch ADR-030 §5 describes for a stale BDF.
[[ "$BASE_LV_RECORDED" == "$VG/$FOUNDATION_LV" ]] \
  || die "$FOUNDATION_META records FOUNDATION_LV=$BASE_LV_RECORDED but this
       build snapshotted $VG/$FOUNDATION_LV — refusing to record provenance
       that does not match the LV actually used."

APP_META="$KATMATE_STATE_DIR/app-$TYPE.meta"
install -d -m0755 "$KATMATE_STATE_DIR"
APP_META_TMP="$(mktemp "$KATMATE_STATE_DIR/.app-$TYPE.meta.XXXXXX")"
cat >"$APP_META_TMP" <<EOF
KATMATE_META_VERSION=1
APP_TYPE=$TYPE
APP_LV=$VG/$APP_LV
APP_BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
APP_ROOTFSTYPE=ext4
BASE_LV=$VG/$FOUNDATION_LV
BASE_BUILT=$BASE_BUILT
KERNEL_VERSION=$KERNEL_VERSION
KIND=$KM_MF_KIND
RUN=$RUN_META
EOF
chmod 0644 "$APP_META_TMP"
mv -f -- "$APP_META_TMP" "$APP_META"   # atomic: mktemp created it on the same fs

log "$APP_LV ready: RO-frozen thin snapshot of $FOUNDATION_LV"
log "  metadata: $APP_META (base generation $BASE_BUILT)"
log "Reminder: 'lvchange -K -ay $VG/$APP_LV' is required before each instance boot."
