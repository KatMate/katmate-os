#!/usr/bin/env bash
# make-release.sh — assemble the unsigned half of a KatMate release (ADR-020)
#
# Usage (on the build host, as root, from the synced tree):
#   sudo tools/make-release.sh --tag <tag> --out <empty dir> --built-after <UTC>
#
#   --tag          the release tag the Acer will archive (e.g. v0.2.0-alpha1);
#                  names the tree archive in release.env, nothing else
#   --out          a directory that does not exist yet, or is empty
#   --built-after  ISO-8601 UTC time (2026-10-05T08:00:00Z). Every image must
#                  have been built after it: "built fresh for this release"
#                  (operator ruling R20) as a check, not as a promise
#
# What a release is (operator rulings R1-R4, R20, U1; 2026-10-05): prebuilt,
# zstd-compressed guest images (foundation, the app layers web/office/vault,
# netVM), their T2 metadata, the MicroVM kernel and its provenance sidecar,
# netVM's kernel and initrd, the host binaries (host waypipe, ping-client),
# and a `git archive` of the release tag. One SHA256SUMS lists every file and
# is signed detached by the release key. The installer builds nothing.
#
# This script writes everything but the tree archive, and a PARTIAL
# SHA256SUMS. It stops before signing: git and the signing key live on the
# Acer only (CLAUDE.md, *The two machines*). The commands for the Acer half
# are printed at the end.
#
# What it reads, and what it never reads:
#   - reads: the image LVs named below, /var/lib/katmate/*.meta, the shared
#     kernel directory, /var/lib/katmate/netvm/, /opt/katmate/bin/waypipe,
#     /usr/lib/katmate/ping-client, installer/t1/ in this tree.
#   - NEVER reads the operator's per-instance state: no home LV
#     (vm_<instance>_home), no qcow2 delta under /var/lib/katmate/instances/
#     (R20). The LV list is a literal below, never a glob over vg0.
#
# Hygiene (R20): an image is exported only if it was built after
# --built-after, is not open (no running VM holds it), and nothing in it is
# newer than its build stamp. netVM must also never have been booted since its
# build: build/netvm.sh step 9b writes /var/lib/katmate/build-unbooted as its
# last write, and any file newer than that marker, any journal file, any
# dhcpcd state or any SSH host key refuses the export.
#
# Validation of the T1 templates (R10): fish is not installed on a KatMate
# host, so tools/validate-properties.fish runs HERE, at release time, over the
# templates the installer will instantiate.
#
# UNVERIFIED: written in a cloud session without LVM, zstd or an image; only
# `bash -n` and shellcheck were run. It first executes on MINIS.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/config.sh
source "$HERE/../build/config.sh"
# shellcheck source=build/lib.sh
source "$HERE/../build/lib.sh"   # log, die, require_root, kernel_provenance_check

# GitHub's per-asset limit (R3: each file < 2 GiB).
MAX_ASSET_BYTES=$(( 2 * 1024 * 1024 * 1024 ))
NETVM_LV="vm_sys_netvm"            # build/netvm.sh's default NETVM_LV
NETVM_RUNTIME_DIR="$KATMATE_STATE_DIR/netvm"
HOST_WAYPIPE="/opt/katmate/bin/waypipe"
HOST_PING_CLIENT="/usr/lib/katmate/ping-client"
T1_TEMPLATES="$ROOT_DIR/installer/t1"
VALIDATOR="$ROOT_DIR/tools/validate-properties.fish"
APP_TYPES=(web office vault)       # the three layers; app_personal uses web

usage() {
  echo "usage: $0 --tag <tag> --out <empty dir> --built-after <YYYY-MM-DDTHH:MM:SSZ>" >&2
  exit 2
}

TAG="" OUTDIR="" BUILT_AFTER=""
while (( $# )); do
  case "$1" in
    --tag)         TAG="${2-}"; shift 2 || usage ;;
    --out)         OUTDIR="${2-}"; shift 2 || usage ;;
    --built-after) BUILT_AFTER="${2-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done
[[ -n "$TAG" && -n "$OUTDIR" && -n "$BUILT_AFTER" ]] || usage
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "--tag '$TAG': letters, digits, '.', '_' and '-' only (it becomes a file name)"
[[ "$BUILT_AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || die "--built-after '$BUILT_AFTER' is not YYYY-MM-DDTHH:MM:SSZ (UTC, the format every meta's stamp uses)"

require_root
for c in lvs lvchange blockdev dd zstd sha256sum mount umount findmnt find cmp file fish systemctl stat; do
  command -v "$c" >/dev/null || die "missing command: $c"
done

if [[ -e "$OUTDIR" ]]; then
  [[ -d "$OUTDIR" && -z "$(ls -A "$OUTDIR")" ]] || die "--out $OUTDIR exists and is not an empty directory"
else
  mkdir -p "$OUTDIR"
fi
OUTDIR="$(cd "$OUTDIR" && pwd)"
ARCHIVE="katmate-os-$TAG.tar.gz"

# --- cleanup: unmount and deactivate only what this script activated ---------
MNT="$(mktemp -d)"
ACTIVATED=()
cleanup() {
  findmnt "$MNT" >/dev/null 2>&1 && umount "$MNT" 2>/dev/null
  rmdir "$MNT" 2>/dev/null || true
  local lv
  for lv in "${ACTIVATED[@]}"; do lvchange -an "$VG/$lv" 2>/dev/null || true; done
}
trap cleanup EXIT

meta_get() { sed -n "s/^$2=//p" "$1" | head -n1; }
meta_req() {
  local v; v="$(meta_get "$1" "$2")"
  [[ -n "$v" ]] || die "$1 records no $2"
  printf '%s' "$v"
}
# Stamps are all YYYY-MM-DDTHH:MM:SSZ, which sorts lexically in time order.
fresh() {
  local what="$1" stamp="$2"
  [[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || die "$what: build stamp '$stamp' is not YYYY-MM-DDTHH:MM:SSZ"
  [[ "$stamp" > "$BUILT_AFTER" ]] \
    || die "$what was built at $stamp, not after --built-after $BUILT_AFTER: only images built fresh for this release are exported (R20)"
}

# --- 1. metadata: what each image is, and that it is this release's ---------
log "Metadata (T2) and freshness against --built-after $BUILT_AFTER"
[[ -r "$FOUNDATION_META" ]] || die "missing $FOUNDATION_META"
F_BUILT="$(meta_req "$FOUNDATION_META" BUILD_DATE)"
F_LV="$(meta_req "$FOUNDATION_META" FOUNDATION_LV)"
KVER="$(meta_req "$FOUNDATION_META" KERNEL_VERSION)"
WP_TAG="$(meta_req "$FOUNDATION_META" WAYPIPE_TAG)"
[[ "$F_LV" == "$VG/$FOUNDATION_LV" ]] || die "$FOUNDATION_META records FOUNDATION_LV=$F_LV, expected $VG/$FOUNDATION_LV"
fresh foundation "$F_BUILT"

declare -A STAMP=([foundation]="$F_BUILT")
declare -A LVOF=([foundation]="$FOUNDATION_LV")
for t in "${APP_TYPES[@]}"; do
  m="$KATMATE_STATE_DIR/app-$t.meta"
  [[ -r "$m" ]] || die "missing $m"
  [[ "$(meta_req "$m" APP_LV)" == "$VG/$APP_LV_PREFIX$t" ]] || die "$m records APP_LV=$(meta_get "$m" APP_LV), expected $VG/$APP_LV_PREFIX$t"
  [[ "$(meta_req "$m" BASE_BUILT)" == "$F_BUILT" ]] \
    || die "$m was built on foundation $(meta_get "$m" BASE_BUILT), not on the current one ($F_BUILT): rebuild the layer"
  [[ "$(meta_req "$m" KERNEL_VERSION)" == "$KVER" ]] || die "$m requires kernel $(meta_get "$m" KERNEL_VERSION), the foundation records $KVER"
  STAMP[app-$t]="$(meta_req "$m" APP_BUILT)"
  LVOF[app-$t]="$APP_LV_PREFIX$t"
  fresh "app-$t" "${STAMP[app-$t]}"
done

NETVM_META="$NETVM_RUNTIME_DIR/netvm.meta"
[[ -r "$NETVM_META" ]] || die "missing $NETVM_META"
[[ "$(meta_req "$NETVM_META" NETVM_LV)" == "$VG/$NETVM_LV" ]] || die "$NETVM_META records NETVM_LV=$(meta_get "$NETVM_META" NETVM_LV), expected $VG/$NETVM_LV"
# A dev image is never a release image (R18; SECURITY-MODEL release blockers).
[[ "$(meta_req "$NETVM_META" NETVM_ROOT_UNLOCKED)" == no ]] \
  || die "$NETVM_META records NETVM_ROOT_UNLOCKED=$(meta_get "$NETVM_META" NETVM_ROOT_UNLOCKED): a netVM with an unlocked root is never released. Rebuild without KATMATE_DEV_ROOT_HASH."
STAMP[netvm]="$(meta_req "$NETVM_META" NETVM_BUILT)"
LVOF[netvm]="$NETVM_LV"
fresh netvm "${STAMP[netvm]}"

IMAGES=(foundation app-web app-office app-vault netvm)

# --- 2. nothing holds an image ----------------------------------------------
# An open LV is in use: netVM running, or an AppVM whose delta backs onto a
# layer. Exporting it would read a device something else may be writing, and
# mounting it below would be worse.
log "In-use check"
systemctl is-active --quiet "katmate-sys-driver@netvm" \
  && die "katmate-sys-driver@netvm is active: stop netVM before a release (and do not boot it again: an image booted since its build is refused below)"
for img in "${IMAGES[@]}"; do
  lv="${LVOF[$img]}"
  attr="$(lvs --noheadings -o lv_attr "$VG/$lv" 2>/dev/null | tr -d ' ')" || die "$VG/$lv does not exist"
  [[ -n "$attr" ]] || die "$VG/$lv does not exist"
  [[ "${attr:5:1}" != o ]] || die "$VG/$lv is open (lv_attr $attr): a VM holds it. Stop every VM first."
done

activate() {
  local lv="$1" kind="$2"
  if [[ ! -b "/dev/$VG/$lv" ]]; then
    if [[ "$kind" == thin ]]; then lvchange -K -ay "$VG/$lv"; else lvchange -ay "$VG/$lv"; fi
    ACTIVATED+=("$lv")
    udevadm settle 2>/dev/null || true
  fi
  [[ -b "/dev/$VG/$lv" ]] || die "/dev/$VG/$lv did not appear after activation"
}

# Read-only, and noload: the journal is not replayed, so nothing is written to
# an image this script only reads.
mount_ro() { mount -o ro,noload "/dev/$VG/$1" "$MNT"; }

# --- 3. hygiene: nothing newer than the build stamp (R20) --------------------
log "Hygiene: no file newer than each image's build stamp"
for img in foundation app-web app-office app-vault; do
  lv="${LVOF[$img]}"
  activate "$lv" thin
  mount_ro "$lv"
  epoch="$(date -u -d "${STAMP[$img]}" +%s)"
  newer="$(find "$MNT" -xdev -newermt "@$epoch" -print)"
  total="$(find "$MNT" -xdev | wc -l)"
  umount "$MNT"
  if [[ -n "$newer" ]]; then
    printf '%s\n' "$newer" | sed "s#^$MNT##" | head -n 50 >&2
    die "$img ($VG/$lv): $(printf '%s\n' "$newer" | wc -l) of $total paths are newer than its build stamp ${STAMP[$img]} (first 50 above). Only an image built fresh and never modified is released (R20)."
  fi
  log "  $img: 0 of $total paths newer than ${STAMP[$img]}"
done

log "Hygiene: netVM never booted since its build"
activate "$NETVM_LV" linear
mount_ro "$NETVM_LV"
MARKER="$MNT/var/lib/katmate/build-unbooted"
netvm_refuse() { umount "$MNT"; die "netvm ($VG/$NETVM_LV): $*"; }
[[ -f "$MARKER" ]] || netvm_refuse "no /var/lib/katmate/build-unbooted: this image was built before build/netvm.sh wrote the marker. Rebuild it."
[[ "$(cat "$MARKER")" == "NETVM_BUILT=${STAMP[netvm]}" ]] \
  || netvm_refuse "the marker reads '$(cat "$MARKER")', netvm.meta records NETVM_BUILT=${STAMP[netvm]}: the image and its metadata are from different builds"
newer="$(find "$MNT" -xdev -newer "$MARKER" -print)"
[[ -z "$newer" ]] || { printf '%s\n' "$newer" | sed "s#^$MNT##" | head -n 50 >&2
  netvm_refuse "$(printf '%s\n' "$newer" | wc -l) paths are newer than the unbooted marker (first 50 above): it has been booted since its build"; }
journal="$(find "$MNT/var/log/journal" -type f -print 2>/dev/null || true)"
[[ -z "$journal" ]] || netvm_refuse "journal files present: $(printf '%s ' "$journal" | sed "s#$MNT##g")"
dhcp="$(find "$MNT/var/lib/dhcpcd" -type f -print 2>/dev/null || true)"
[[ -z "$dhcp" ]] || netvm_refuse "dhcpcd state present (a lease, DUID or secret): $(printf '%s ' "$dhcp" | sed "s#$MNT##g")"
hostkeys="$(find "$MNT/etc/ssh" -name 'ssh_host_*' -print 2>/dev/null || true)"
[[ -z "$hostkeys" ]] || netvm_refuse "SSH host keys present: $(printf '%s ' "$hostkeys" | sed "s#$MNT##g")"
umount "$MNT"
log "  netvm: marker matches NETVM_BUILT=${STAMP[netvm]}; nothing newer; no journal, no dhcpcd state, no host key"

# --- 4. T1 templates validate (R10) ------------------------------------------
log "Validate the T1 templates the installer instantiates"
T1_TMP="$(mktemp -d)"
n=0
for f in "$T1_TEMPLATES"/*.toml.in; do
  cp -- "$f" "$T1_TMP/$(basename "$f" .in)"; n=$((n + 1))
done
(( n == 5 )) || die "$T1_TEMPLATES holds $n *.toml.in templates, expected 5 (netvm and the four alpha AppVMs)"
fish "$VALIDATOR" --strict "$T1_TMP" || die "tools/validate-properties.fish --strict refused the templates in $T1_TEMPLATES (above)"
rm -rf "$T1_TMP"
log "  $n templates validated with --strict, cross-file rules included"

# --- 5. export the images ----------------------------------------------------
# images.list, one line per image:
#   <file> <lv> <thin|linear> <bytes> <ro|rw> <allocated bytes>
log "Export images (zstd), each read back against its LV"
: > "$OUTDIR/images.list"
for img in "${IMAGES[@]}"; do
  lv="${LVOF[$img]}"
  kind=thin; mode=ro
  [[ "$img" == netvm ]] && { kind=linear; mode=rw; }
  dev="/dev/$VG/$lv"
  bytes="$(blockdev --getsize64 "$dev")"
  out="$OUTDIR/$img.img.zst"
  log "  $img: $dev ($bytes bytes) -> $(basename "$out")"
  dd if="$dev" bs=4M status=none | zstd -q -T0 -12 -o "$out"
  # The read-back, not zstd's exit code, is the evidence that the file is
  # the LV: decompress and compare every byte, and the size beside it.
  cmp -n "$bytes" <(zstd -q -dc "$out") "$dev" || die "$img: $(basename "$out") does not decompress to $dev"
  [[ "$(zstd -q -dc "$out" | wc -c)" == "$bytes" ]] || die "$img: decompressed size differs from $bytes"
  # Allocated bytes: what the image occupies in a thin pool after a sparse
  # import, so the installer can size its pool check on use rather than on
  # the virtual size. For a thin LV, lv_size x data_percent (blocks mapped,
  # including those a snapshot shares with its origin: a standalone import
  # needs them all). A linear LV is all allocated.
  alloc="$bytes"
  if [[ "$kind" == thin ]]; then
    pct="$(lvs --noheadings -o data_percent "$VG/$lv" | tr -d ' ')"
    [[ "$pct" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "$VG/$lv: unreadable data_percent '$pct'"
    alloc="$(awk -v b="$bytes" -v p="$pct" 'BEGIN { a = b * (p + 0.01) / 100; printf "%d", (a > b ? b : a) }')"
  fi
  printf '%s %s %s %s %s %s\n' "$img.img.zst" "$lv" "$kind" "$bytes" "$mode" "$alloc" >> "$OUTDIR/images.list"
done

# --- 6. T2 metadata, kernels, host binaries ----------------------------------
log "T2 metadata, kernels and host binaries"
install -m 0644 "$FOUNDATION_META" "$OUTDIR/foundation.meta"
for t in "${APP_TYPES[@]}"; do install -m 0644 "$KATMATE_STATE_DIR/app-$t.meta" "$OUTDIR/app-$t.meta"; done
install -m 0644 "$NETVM_META" "$OUTDIR/netvm.meta"
install -m 0644 "$(meta_req "$NETVM_META" NETVM_KERNEL)" "$OUTDIR/netvm-vmlinuz"
install -m 0644 "$(meta_req "$NETVM_META" NETVM_INITRD)" "$OUTDIR/netvm-initrd.img"

KERNEL="$KATMATE_KERNELS_DIR/vmlinuz-katmate-microvm-$ARCH-$KVER"
[[ -f "$KERNEL" ]] || die "missing the shared MicroVM kernel $KERNEL (foundation.meta KERNEL_VERSION=$KVER)"
KPROV="$(kernel_provenance_check "$KERNEL")"   # dies on a sidecar for another kernel
install -m 0644 "$KERNEL" "$OUTDIR/$(basename "$KERNEL")"
[[ "$KPROV" == recorded ]] && install -m 0644 "$KERNEL.provenance" "$OUTDIR/$(basename "$KERNEL").provenance"
log "  MicroVM kernel $(basename "$KERNEL"), provenance $KPROV"

for b in "$HOST_WAYPIPE" "$HOST_PING_CLIENT"; do
  [[ -x "$b" ]] || die "missing host binary $b"
  file -b "$b" | grep -q '^ELF ' || die "$b is not an ELF binary: $(file -b "$b")"
done
# The version lock (ADR-019), the comparison katmate-check-waypipe makes at
# every AppVM start, made here once so a release cannot carry a mismatch.
wp_have="$("$HOST_WAYPIPE" --version 2>&1 | head -n1 | awk '{print $2}')"
[[ "$wp_have" == "${WP_TAG#v}" ]] || die "host waypipe reports '$wp_have', foundation.meta WAYPIPE_TAG=$WP_TAG"
install -m 0755 "$HOST_WAYPIPE" "$OUTDIR/waypipe"
install -m 0755 "$HOST_PING_CLIENT" "$OUTDIR/ping-client"

cat > "$OUTDIR/release.env" <<EOF
KATMATE_RELEASE_VERSION=1
RELEASE_TAG=$TAG
ARCHIVE=$ARCHIVE
KERNEL_FILE=$(basename "$KERNEL")
KERNEL_PROVENANCE=$KPROV
WAYPIPE_TAG=$WP_TAG
ASSEMBLED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# --- 7. size limit and the partial SHA256SUMS --------------------------------
log "Asset sizes (GitHub limit: < 2 GiB each, R3)"
too_big=0
for f in "$OUTDIR"/*; do
  s="$(stat -c %s "$f")"
  printf '  %12d  %s\n' "$s" "$(basename "$f")"
  (( s < MAX_ASSET_BYTES )) || { echo "  ^ over the limit" >&2; too_big=1; }
done
(( ! too_big )) || die "at least one asset is 2 GiB or larger (above): GitHub refuses it"

(cd "$OUTDIR" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum) > "$OUTDIR/SHA256SUMS.partial"
mv "$OUTDIR/SHA256SUMS.partial" "$OUTDIR/SHA256SUMS"
log "SHA256SUMS: $(wc -l < "$OUTDIR/SHA256SUMS") files (partial: the tree archive is added on the Acer)"

cat <<EOF

==> Done on this host. The release is NOT complete and NOT signed.
    Copy $OUTDIR/SHA256SUMS to the Acer, then on the Acer:

    cd ~/katmate-os
    git fetch origin && git tag -v $TAG
    mkdir -p ~/release-$TAG && cp <the copied SHA256SUMS> ~/release-$TAG/SHA256SUMS
    git archive --format=tar.gz --prefix=katmate-os-$TAG/ -o ~/release-$TAG/$ARCHIVE $TAG
    (cd ~/release-$TAG && sha256sum $ARCHIVE >> SHA256SUMS && LC_ALL=C sort -k2 -o SHA256SUMS SHA256SUMS)
    gpg --local-user 3F49AE514562ACD3FF9D6049F8841B7B3D3AB436 --armor --detach-sign \\
        --output ~/release-$TAG/SHA256SUMS.asc ~/release-$TAG/SHA256SUMS
    gpg --verify ~/release-$TAG/SHA256SUMS.asc ~/release-$TAG/SHA256SUMS

    Upload as the assets of GitHub release $TAG: every file in $OUTDIR except
    SHA256SUMS, plus ~/release-$TAG/{$ARCHIVE,SHA256SUMS,SHA256SUMS.asc}.
    The SHA256SUMS uploaded must be the Acer's, the one the signature covers.
EOF
