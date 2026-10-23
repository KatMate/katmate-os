#!/usr/bin/env bash
# make-release.sh — assemble the unsigned half of a KatMate release (ADR-020)
#
# Usage (on the build host, as root, from the synced tree):
#   sudo tools/make-release.sh --tag <tag> --archive <dir>/katmate-os-<tag>.tar.gz \
#        --iso <dir>/katmate-install-<tag>-x86_64.iso --out <empty dir> --built-after <UTC>
#
#   --tag          the release tag (e.g. v0.2.0-beta)
#   --archive      the Acer's archive of the tag, copied here. Made with
#                    git -c tar.umask=0022 archive --format=tar.gz \
#                      --prefix=katmate-os-<tag>/ -o katmate-os-<tag>.tar.gz <tag>
#   --iso          the install medium build/iso.sh built from that archive, with
#                  its .sha256 beside it
#   --out          a directory that does not exist yet, or is empty
#   --built-after  ISO-8601 UTC time (2026-10-05T08:00:00Z). Every image must
#                  have been built after it: "built fresh for this release"
#                  (operator ruling R20) as a check, not as a promise
#
# What a release is (operator rulings R1-R4, R20, U1; 2026-10-05): prebuilt,
# zstd-compressed guest images (foundation, the app layers web/office/vault,
# netVM), their T2 metadata, the MicroVM kernel and its provenance sidecar,
# netVM's kernel and initrd, the host binaries (host waypipe, ping-client,
# katmate-alloc, katmate-vm), a `git archive` of the release tag, and the
# install medium (ADR-042). One SHA256SUMS lists every file and is signed
# detached by the release key; the ISO is covered by that one signature, with
# no signature of its own. The installer builds nothing.
#
# This script writes every release file and the complete SHA256SUMS. It stops
# before signing: git and the signing key live on the Acer only (CLAUDE.md,
# *The two machines*). The commands for the Acer half are printed at the end:
# check the Acer's own archive against SHA256SUMS, sign, verify.
#
# Step 0 binds the medium to the archive before anything is exported: the ISO
# embeds the archive, so the release must ship the very archive its ISO
# carries. Both are read from the ISO itself (its airootfs), not from a
# sidecar.
#
# What it reads, and what it never reads:
#   - reads: --archive and --iso, the image LVs named below,
#     /var/lib/katmate/*.meta, the shared kernel directory,
#     /var/lib/katmate/netvm/, /opt/katmate/bin/waypipe,
#     /usr/lib/katmate/ping-client, /usr/lib/katmate/katmate-alloc,
#     /usr/lib/katmate/katmate-vm.
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
# templates the installer will instantiate: those in --archive.
#
# UNVERIFIED: copying --archive and --iso into --out and the complete
# SHA256SUMS (steps 5 and 6) first execute in the v0.2.0-beta release run.

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
HOST_ALLOC="/usr/lib/katmate/katmate-alloc"
HOST_VM="/usr/lib/katmate/katmate-vm"
VALIDATOR="$ROOT_DIR/tools/validate-properties.fish"
# The release's shipped set of layers (prebuilt until ADR-043 gate B1), not a
# rule about which layers may exist; installer/install.sh carries the same set.
# app_personal and app_sandbox use web.
APP_TYPES=(web office vault)
# A second copy of build/iso.sh's `(( DAYS_LEFT >= 60 ))` (ADR-042 Decision 5):
# iso.sh holds it as a literal, so the two are kept equal by hand.
ISO_MIN_DAYS=60
# docs/DEV-ENV.md, *Dev access to MINIS*; only printed, for the Acer's scp.
BUILD_HOST_SSH="host@10.3.1.3"

usage() {
  echo "usage: $0 --tag <tag> --archive <katmate-os-<tag>.tar.gz> --iso <katmate-install-<tag>-x86_64.iso> --out <empty dir> --built-after <YYYY-MM-DDTHH:MM:SSZ>" >&2
  exit 2
}

TAG="" OUTDIR="" BUILT_AFTER="" ARCHIVE_SRC="" ISO_SRC=""
while (( $# )); do
  case "$1" in
    --tag)         TAG="${2-}"; shift 2 || usage ;;
    --archive)     ARCHIVE_SRC="${2-}"; shift 2 || usage ;;
    --iso)         ISO_SRC="${2-}"; shift 2 || usage ;;
    --out)         OUTDIR="${2-}"; shift 2 || usage ;;
    --built-after) BUILT_AFTER="${2-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done
[[ -n "$TAG" && -n "$ARCHIVE_SRC" && -n "$ISO_SRC" && -n "$OUTDIR" && -n "$BUILT_AFTER" ]] || usage
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "--tag '$TAG': letters, digits, '.', '_' and '-' only (it becomes a file name)"
[[ "$BUILT_AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || die "--built-after '$BUILT_AFTER' is not YYYY-MM-DDTHH:MM:SSZ (UTC, the format every meta's stamp uses)"

require_root
for c in lvs lvchange blockdev dd zstd sha256sum mount umount findmnt losetup unsquashfs tar find cmp file fish systemctl stat; do
  command -v "$c" >/dev/null || die "missing command: $c"
done

if [[ -e "$OUTDIR" ]]; then
  [[ -d "$OUTDIR" && -z "$(ls -A "$OUTDIR")" ]] || die "--out $OUTDIR exists and is not an empty directory"
else
  mkdir -p "$OUTDIR"
fi
OUTDIR="$(cd "$OUTDIR" && pwd)"
# The printed Acer half carries this path into fish and scp unescaped.
[[ "$OUTDIR" =~ ^[A-Za-z0-9/._+-]+$ ]] || die "--out $OUTDIR: letters, digits and . _ + - / only (the printed Acer commands use it as is)"
ARCHIVE="katmate-os-$TAG.tar.gz"
ISO="katmate-install-$TAG-x86_64.iso"   # mkarchiso: iso_name-iso_version-arch (iso/profiledef.sh)

# --- cleanup: unmount and deactivate only what this script activated ---------
MNT="$(mktemp -d)"
ISO_MNT="$(mktemp -d)"
ISO_LOOP=""
X=""
ACTIVATED=()
iso_release() {
  if findmnt "$ISO_MNT" >/dev/null 2>&1; then umount "$ISO_MNT" || echo "cleanup: cannot unmount $ISO_MNT" >&2; fi
  if [[ -n "$ISO_LOOP" ]]; then losetup -d "$ISO_LOOP" || echo "cleanup: cannot detach $ISO_LOOP" >&2; fi
  ISO_LOOP=""
}
cleanup() {
  iso_release
  findmnt "$MNT" >/dev/null 2>&1 && umount "$MNT" 2>/dev/null
  rmdir "$MNT" "$ISO_MNT" 2>/dev/null || true
  [[ -z "$X" ]] || rm -rf -- "$X"
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

# --- 0. archive, install medium, T1 templates: the cheap checks first -------
# Nothing here writes into --out; the archive and the ISO are copied in step 5.
log "Step 0: the archive, the install medium and the T1 templates"
[[ "$(basename -- "$ARCHIVE_SRC")" == "$ARCHIVE" ]] || die "--archive $ARCHIVE_SRC is not named $ARCHIVE"
[[ "$(basename -- "$ISO_SRC")" == "$ISO" ]] || die "--iso $ISO_SRC is not named $ISO"
[[ -f "$ARCHIVE_SRC" ]] || die "No such archive: $ARCHIVE_SRC"
[[ -f "$ISO_SRC" ]] || die "No such ISO: $ISO_SRC"
log "  names: OK ($ARCHIVE, $ISO)"

X="$(mktemp -d)"
tar -xzf "$ARCHIVE_SRC" -C "$X" || die "Cannot unpack $ARCHIVE"
top="$(ls -A "$X")"
[[ "$top" == "katmate-os-$TAG" && -d "$X/$top" ]] \
  || die "$ARCHIVE does not unpack to katmate-os-$TAG/ alone (top level: ${top//$'\n'/ })"
# Git's default tar.umask is 0002, which archives directories 775 and files
# 664; extracted as root, as on the live ISO, the tree keeps those modes, and
# the installer's host-parts step refuses group-writable paths (install.sh,
# the 8#022 check). Found 2026-10-09 by the first alpha2 install on the Cubi.
writable="$(find "$X" -mindepth 1 ! -type l -perm /022 -printf '%P\n')"
[[ -z "$writable" ]] || { printf '%s\n' "$writable" | head -n 20 >&2
  die "$ARCHIVE: $(wc -l <<<"$writable") paths are group- or world-writable (first 20 above): it was archived without -c tar.umask=0022. Make it again."; }
ARCHIVE_SUM="$(sha256sum -- "$ARCHIVE_SRC" | awk '{print $1}')" || die "Cannot hash $ARCHIVE_SRC"
log "  archive: OK (unpacks to katmate-os-$TAG/, nothing group- or world-writable; sha256 $ARCHIVE_SUM)"

# fish is not installed on a KatMate host, so tools/validate-properties.fish
# (R10) runs here, over the templates of the archive being released.
T1_TMP="$X/t1"
mkdir "$T1_TMP"
n=0
for f in "$X/katmate-os-$TAG/installer/t1"/*.toml.in; do
  [[ -e "$f" ]] || continue
  cp -- "$f" "$T1_TMP/$(basename "$f" .in)"; n=$((n + 1))
done
(( n == 6 )) || die "$ARCHIVE holds $n installer/t1/*.toml.in templates, expected 6 (netvm and the five alpha AppVMs)"
fish "$VALIDATOR" --strict "$T1_TMP" || die "tools/validate-properties.fish --strict refused the templates of $ARCHIVE (above)"
log "  T1: OK ($n templates from $ARCHIVE validated with --strict, cross-file rules included)"

ISO_LOOP="$(losetup --find --show --read-only "$ISO_SRC")" || die "Cannot attach $ISO_SRC to a loop device"
mount -o ro "$ISO_LOOP" "$ISO_MNT" || die "Cannot mount $ISO_SRC"
SFS="$ISO_MNT/arch/x86_64/airootfs.sfs"
[[ -f "$SFS" ]] || die "$ISO has no arch/x86_64/airootfs.sfs: not a build/iso.sh medium"
ISO_ENV="$(unsquashfs -cat "$SFS" etc/katmate-iso/iso.env)" || die "$ISO: no etc/katmate-iso/iso.env in its airootfs"
iso_env_get() { sed -n "s/^$1=//p" <<<"$ISO_ENV" | head -n1; }
ISO_TAG="$(iso_env_get ISO_RELEASE_TAG)"
[[ "$ISO_TAG" == "$TAG" ]] || die "$ISO: its iso.env records ISO_RELEASE_TAG=$ISO_TAG, not --tag $TAG"
log "  tag: OK (iso.env ISO_RELEASE_TAG=$ISO_TAG)"

VALID_UNTIL="$(iso_env_get ISO_VALID_UNTIL)"
[[ "$VALID_UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || die "$ISO: its iso.env records no ISO_VALID_UNTIL date (got '$VALID_UNTIL'): built before build/iso.sh wrote one. Rebuild it."
# Midnight UTC of the expiry date: never later than iso.sh's own reckoning.
DAYS_LEFT=$(( ($(date -u -d "$VALID_UNTIL" +%s) - $(date -u +%s)) / 86400 ))
(( DAYS_LEFT >= ISO_MIN_DAYS )) \
  || die "$ISO is valid until $VALID_UNTIL, $DAYS_LEFT days from now: under $ISO_MIN_DAYS (ADR-042 Decision 5). Rebuild the medium with a newer archlinux-keyring."
log "  validity: OK (ISO_VALID_UNTIL=$VALID_UNTIL, $DAYS_LEFT days left, at least $ISO_MIN_DAYS required)"

unsquashfs -cat "$SFS" "usr/share/katmate-iso/$ARCHIVE" | cmp -s - "$ARCHIVE_SRC" \
  || die "$ISO: its usr/share/katmate-iso/$ARCHIVE is missing or not byte-identical to --archive $ARCHIVE_SRC: the medium was not built from this archive"
log "  embedded archive: OK (usr/share/katmate-iso/$ARCHIVE is byte-identical to --archive)"
iso_release

[[ -r "$ISO_SRC.sha256" ]] || die "No $ISO_SRC.sha256 beside the ISO (build/iso.sh writes one)"
sha_line="$(cat -- "$ISO_SRC.sha256")"
[[ "$sha_line" =~ ^([0-9a-f]{64})\ \ (.+)$ ]] || die "$ISO_SRC.sha256 is not a sha256sum line: $sha_line"
ISO_SUM_WANT="${BASH_REMATCH[1]}"
[[ "${BASH_REMATCH[2]}" == "$ISO" ]] || die "$ISO_SRC.sha256 names '${BASH_REMATCH[2]}', not $ISO"
ISO_SUM="$(sha256sum -- "$ISO_SRC" | awk '{print $1}')" || die "Cannot hash $ISO_SRC"
[[ "$ISO_SUM" == "$ISO_SUM_WANT" ]] || die "$ISO: sha256 $ISO_SUM does not match its .sha256 ($ISO_SUM_WANT)"
log "  .sha256: OK ($ISO_SUM)"

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
  [[ "$(meta_req "$m" KIND)" == debian-manifest ]] || die "$m records KIND=$(meta_get "$m" KIND), not debian-manifest (ADR-043 §8)"
  meta_req "$m" RUN >/dev/null   # without RUN, katmate-launch refuses every app (ADR-043 §5)
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
  # The stamp has whole-second resolution and the build's own last writes (cleanup) can land inside that second; only the next second on counts as after the build.
  newer="$(find "$MNT" -xdev -newermt "@$((epoch + 1))" -print)"
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

# --- 4. export the images ----------------------------------------------------
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

# --- 5. T2 metadata, kernels, host binaries, archive, ISO --------------------
log "T2 metadata, kernels, host binaries, the archive and the ISO"
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

for b in "$HOST_WAYPIPE" "$HOST_PING_CLIENT" "$HOST_ALLOC" "$HOST_VM"; do
  [[ -x "$b" ]] || die "missing host binary $b"
  file -b "$b" | grep -q '^ELF ' || die "$b is not an ELF binary: $(file -b "$b")"
done
# The version lock (ADR-019), the comparison katmate-check-waypipe makes at
# every AppVM start, made here once so a release cannot carry a mismatch.
wp_have="$("$HOST_WAYPIPE" --version 2>&1 | head -n1 | awk '{print $2}')"
[[ "$wp_have" == "${WP_TAG#v}" ]] || die "host waypipe reports '$wp_have', foundation.meta WAYPIPE_TAG=$WP_TAG"
install -m 0755 "$HOST_WAYPIPE" "$OUTDIR/waypipe"
install -m 0755 "$HOST_PING_CLIENT" "$OUTDIR/ping-client"
install -m 0755 "$HOST_ALLOC" "$OUTDIR/katmate-alloc"
install -m 0755 "$HOST_VM" "$OUTDIR/katmate-vm"
install -m 0644 "$ARCHIVE_SRC" "$OUTDIR/$ARCHIVE"
install -m 0644 "$ISO_SRC" "$OUTDIR/$ISO"

cat > "$OUTDIR/release.env" <<EOF
KATMATE_RELEASE_VERSION=1
RELEASE_TAG=$TAG
ARCHIVE=$ARCHIVE
KERNEL_FILE=$(basename "$KERNEL")
KERNEL_PROVENANCE=$KPROV
WAYPIPE_TAG=$WP_TAG
ASSEMBLED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# --- 6. size limit and SHA256SUMS --------------------------------------------
log "Asset sizes (GitHub limit: < 2 GiB each, R3)"
too_big=0
for f in "$OUTDIR"/*; do
  s="$(stat -c %s "$f")"
  printf '  %12d  %s\n' "$s" "$(basename "$f")"
  (( s < MAX_ASSET_BYTES )) || { echo "  ^ over the limit" >&2; too_big=1; }
done
(( ! too_big )) || die "at least one asset is 2 GiB or larger (above): GitHub refuses it"

(cd "$OUTDIR" && find . -maxdepth 1 -type f ! -name 'SHA256SUMS*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum) > "$OUTDIR/SHA256SUMS.new"
mv "$OUTDIR/SHA256SUMS.new" "$OUTDIR/SHA256SUMS"
# The copies in --out are the bytes step 0 checked.
grep -qxF "$ARCHIVE_SUM  $ARCHIVE" "$OUTDIR/SHA256SUMS" || die "SHA256SUMS: $ARCHIVE is not the archive step 0 checked ($ARCHIVE_SUM)"
grep -qxF "$ISO_SUM  $ISO" "$OUTDIR/SHA256SUMS" || die "SHA256SUMS: $ISO is not the ISO step 0 checked ($ISO_SUM)"
log "SHA256SUMS: $(wc -l < "$OUTDIR/SHA256SUMS") files, the archive and the ISO included"

# Fish, the operator's shell: no placeholders, no subshells, and one && chain
# so that nothing is signed after a failed check.
cat <<EOF

==> Done on this host. SHA256SUMS lists every file in $OUTDIR; it is NOT
    signed. On the Acer, in fish, with ~/release-$TAG/$ARCHIVE the archive
    this run was given:

    cd ~/katmate-os && git tag -v $TAG \\
      && scp $BUILD_HOST_SSH:$OUTDIR/SHA256SUMS ~/release-$TAG/SHA256SUMS \\
      && cd ~/release-$TAG && sha256sum -c --ignore-missing SHA256SUMS \\
      && gpg --local-user 3F49AE514562ACD3FF9D6049F8841B7B3D3AB436 --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS \\
      && gpg --verify SHA256SUMS.asc SHA256SUMS

    Upload as the assets of GitHub release $TAG: every file in $OUTDIR, plus
    ~/release-$TAG/SHA256SUMS.asc. The SHA256SUMS in $OUTDIR is the file that
    signature covers.
EOF
