#!/usr/bin/env bash
# Katmate OS — generic app-layer builder (ADR-014, ADR-011)
# Usage: app-layer.sh <type>     (reads manifests/<type>.list)
#
# Produces out/app-<type>.qcow2 : a READ-ONLY qcow2 overlay whose backing file
# is out/foundation.qcow2. NO flatten — the backing link keeps the chain
# three-level (foundation <- app-<type> <- instance) and stores foundation once.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib.sh"

require_root

TYPE="${1:?usage: app-layer.sh <type>  (manifest: manifests/<type>.list)}"
MANIFEST="$MANIFESTS/$TYPE.list"
FOUNDATION="$OUT/foundation.qcow2"
IMG="$OUT/app-$TYPE.qcow2"
MNT="$(mktemp -d)"
trap 'cleanup; rmdir "$MNT" 2>/dev/null || true' EXIT

[[ -f "$FOUNDATION" ]] || die "Missing foundation: $FOUNDATION (run: sudo make foundation)"
[[ -f "$MANIFEST" ]]   || die "Missing manifest: $MANIFEST"

# package list = non-empty, non-comment lines
mapfile -t PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")
[[ ${#PKGS[@]} -gt 0 ]] || die "Manifest $MANIFEST lists no packages"

log "Create app-$TYPE overlay (backing -> foundation, NO flatten)"
rm -f "$IMG"
qemu-img create -f qcow2 -F qcow2 -b "$(realpath "$FOUNDATION")" "$IMG"

log "Attach + mount (whole-device view through backing chain)"
nbd_connect "$IMG"
mount_root "$MNT"

cp /etc/resolv.conf "$MNT/etc/resolv.conf"   # build-time DNS only

log "Install manifest: ${PKGS[*]}"
chroot_run "$MNT" apt-get update
chroot_run "$MNT" apt-get install -y "${PKGS[@]}"

log "Cleanup"
chroot_run "$MNT" apt-get clean
rm -f "$MNT/etc/resolv.conf"
rm -rf "$MNT"/var/lib/apt/lists/* 2>/dev/null || true

umount_root
nbd_disconnect
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

chmod 444 "$IMG"
log "app-$TYPE.qcow2 ready: $IMG  (RO overlay on foundation)"
