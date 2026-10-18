#!/usr/bin/env bash
# Katmate OS — app layer built inside a builder VM (spike cu1; dev scaffolding)
# Usage: KMB_WORK=<dir> app-layer-vm.sh <type> <suffix> [<manifest>]
#        (manifest defaults to manifests/<type>.toml; LV vm_app_<type><suffix>)
#
# The host snapshots the foundation, hands the snapshot to a short-lived
# builder VM that reaches the network through netVM like any AppVM, and
# freezes it afterwards. The host never mounts the snapshot. The builder runs
# build/layer-builder/guest.sh as PID 1 and reports over the serial console
# only; what it reports is guest output and goes to the run directory, never
# into the meta, which is written from the manifest and foundation.meta alone.
# The builder runs as a transient unit (operator ruling D9), and nothing here
# is a shipped profile.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib.sh"
# shellcheck disable=SC2034
KM_PROG="app-layer-vm"
# shellcheck source=host/usr/lib/katmate/katmate-lib.sh
source "$ROOT_DIR/host/usr/lib/katmate/katmate-lib.sh"

require_root

TYPE="${1:?usage: KMB_WORK=<dir> app-layer-vm.sh <type> <suffix> [<manifest>]}"
SUFFIX="${2:?usage: KMB_WORK=<dir> app-layer-vm.sh <type> <suffix> [<manifest>]}"
MANIFEST="${3:-$MANIFESTS/$TYPE.toml}"
WORK="${KMB_WORK:?set KMB_WORK to the dev work directory}"
[[ "$TYPE" =~ ^[a-z][a-z0-9]*$ ]] || die "type '$TYPE' must match ^[a-z][a-z0-9]*$"
[[ "$SUFFIX" =~ ^_[a-z0-9]+$ ]] || die "suffix '$SUFFIX' must match ^_[a-z0-9]+$"
APP_LV="${APP_LV_PREFIX}${TYPE}${SUFFIX}"

# The builder's link: slot 06 of netVM `netvm` (operator ruling 3, cu1 H1).
NETVM=netvm
NETVM_CID=3
SLOT=06
LINK_ID=206
SLOT_MAC=52:54:01:00:00:06
PEER=10.100.1.22
GW=10.100.1.1
DNS=10.100.1.1
BUILDER_NAME=cu1_builder
MEM=2G
VCPUS=2
TIMEOUT_S=3600

SLOT_DIR="/run/katmate/link/$NETVM/$SLOT"
OWNER="$SLOT_DIR/owner"
PING_CLIENT=/usr/lib/katmate/ping-client
KERNEL="$KATMATE_KERNELS_DIR/vmlinuz-katmate-microvm-amd64-$KERNEL_VERSION"
GUEST_SRC="$HERE/layer-builder/guest.sh"

RUN="$WORK/runs/$TYPE$SUFFIX-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0755 "$WORK" "$WORK/runs" "$WORK/meta" "$RUN"
exec > >(tee -a "$RUN/host.log") 2>&1

htime() { printf '%s %s\n' "$1" "$(date +%s%3N)" >>"$RUN/host-times.txt"; log "time $1"; }

UNIT=""
LINK_ADDED=""
OWNER_WRITTEN=""

owner_text() { printf 'KATMATE_OWNER_VERSION=1\nINSTANCE=%s\nLINK_ID=%s\n' "$BUILDER_NAME" "$LINK_ID"; }

withdraw_link() {
  if [[ -n "$LINK_ADDED" ]]; then
    if "$PING_CLIENT" netcfg-remove "$NETVM_CID" "$LINK_ID"; then
      log "NETCFG REMOVE $LINK_ID: OK"
    else
      log "NETCFG REMOVE $LINK_ID FAILED"
    fi
    LINK_ADDED=""
  fi
  if [[ -n "$OWNER_WRITTEN" ]]; then
    if [[ ! -L "$OWNER" && "$(cat -- "$OWNER" 2>/dev/null)" == "$(owner_text)" ]]; then
      rm -f -- "$OWNER"
      log "owner removed: $OWNER"
    else
      log "owner $OWNER is not the builder's; not removed"
    fi
    OWNER_WRITTEN=""
  fi
}

on_exit() {
  local rc=$?
  set +e
  if [[ -n "$UNIT" ]]; then
    case "$(systemctl is-active "$UNIT" 2>/dev/null)" in
    active|activating|deactivating)
      log "stopping $UNIT"
      systemctl stop "$UNIT" ;;
    esac
    rm -f -- "$SLOT_DIR/appvm"
  fi
  withdraw_link
  cleanup
  log "exit $rc; run directory $RUN"
}

# --- preflight: nothing is created until all of it holds ---------------------
lvs "$VG/$FOUNDATION_LV" >/dev/null 2>&1 || die "Missing foundation LV: $VG/$FOUNDATION_LV"
[[ -r "$FOUNDATION_META" ]] || die "Missing or unreadable $FOUNDATION_META"
meta_get() { sed -n "s/^$1=//p" "$FOUNDATION_META" | head -n1; }
BASE_BUILT="$(meta_get BUILD_DATE)"
[[ -n "$BASE_BUILT" ]] || die "$FOUNDATION_META records no BUILD_DATE"
[[ "$(meta_get FOUNDATION_LV)" == "$VG/$FOUNDATION_LV" ]] \
  || die "$FOUNDATION_META records FOUNDATION_LV=$(meta_get FOUNDATION_LV), not $VG/$FOUNDATION_LV"
if lvs "$VG/$APP_LV" >/dev/null 2>&1; then
  die "$VG/$APP_LV already exists"
fi
[[ -r "$KERNEL" ]] || die "kernel not readable: $KERNEL"
[[ -r "$GUEST_SRC" ]] || die "builder program not readable: $GUEST_SRC"
[[ -x "$PING_CLIENT" ]] || die "$PING_CLIENT not executable"
[[ "$(systemctl is-active "katmate-sys-driver@$NETVM.service" 2>/dev/null || true)" == active ]] \
  || die "netVM '$NETVM' is not active"
[[ -d "$SLOT_DIR" && -S "$SLOT_DIR/netvm" ]] || die "$SLOT_DIR/netvm is absent"
[[ ! -e "$OWNER" && ! -L "$OWNER" ]] || die "$OWNER exists: slot $SLOT is taken ('$(cat -- "$OWNER" 2>&1 | tr '\n' ' ')')"
[[ ! -e "$SLOT_DIR/appvm" ]] || die "$SLOT_DIR/appvm exists: a peer may be bound to slot $SLOT"
if [[ -n "$(systemctl list-units --no-legend --state=active,activating 'km-cu1-builder-*' 2>/dev/null)" ]]; then
  die "another km-cu1-builder unit is running"
fi

# --- manifest: validated here, before any snapshot (operator ruling 3) --------
km_manifest_parse "$MANIFEST"
PKGS=("${KM_MF_PACKAGES[@]}")
log "manifest $MANIFEST: ${#PKGS[@]} packages: ${PKGS[*]}"

# --- payloads ---------------------------------------------------------------
# vdc: lib.sh + the builder program, padded with newlines to whole sectors so
# QEMU exposes every byte and bash never meets a NUL.
CODE_IMG="$RUN/code.img"
cat "$HERE/lib.sh" "$GUEST_SRC" >"$CODE_IMG"
[[ "$(tr -cd '\000' <"$CODE_IMG" | wc -c)" == 0 ]] || die "$CODE_IMG contains a NUL byte"
size="$(stat -c %s "$CODE_IMG")"
head -c $(( (512 - size % 512) % 512 )) /dev/zero | tr '\0' '\n' >>"$CODE_IMG"

# vdd: ustar on katmate-build-cfgdisk's pattern (ADR-037 R33, R35): canonical
# members, pinned headers, read back against what this run meant to write.
DATA_IMG="$RUN/data.img"
declare -A CANON=([VERSION]=$'1\n' [manifest]="$(printf '%s\n' "${PKGS[@]}")"$'\n')
MEMBERS=(VERSION manifest)
STAGE="$(mktemp -d "$RUN/.stage.XXXXXX")"
for m in "${MEMBERS[@]}"; do printf '%s' "${CANON[$m]}" >"$STAGE/$m"; done
tar --format=ustar --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=0644 \
    -C "$STAGE" -cf "$DATA_IMG" "${MEMBERS[@]}"
rm -rf -- "$STAGE"
mapfile -t listed < <(tar -tf "$DATA_IMG")
[[ "${listed[*]}" == "${MEMBERS[*]}" ]] || die "$DATA_IMG lists '${listed[*]}', expected '${MEMBERS[*]}'"
for m in "${MEMBERS[@]}"; do
  cmp -s <(tar -xOf "$DATA_IMG" "$m") <(printf '%s' "${CANON[$m]}") \
    || die "$DATA_IMG: member '$m' differs from the canonical bytes"
done
chmod 0444 "$CODE_IMG" "$DATA_IMG"
# The meta records what was built: the canonical list as written to the data
# disk, not the authored file (operator ruling, cu1 H2).
MANIFEST_SHA256="$(printf '%s' "${CANON[manifest]}" | sha256sum | cut -d' ' -f1)"
log "canonical manifest sha256 $MANIFEST_SHA256"
log "code disk $(sha256sum <"$CODE_IMG" | cut -c1-64) $(stat -c %s "$CODE_IMG") B"
log "data disk $(sha256sum <"$DATA_IMG" | cut -c1-64) $(stat -c %s "$DATA_IMG") B"

h="$(printf '%s' "$BUILDER_NAME" | sha256sum | cut -c1-6)"
BUILDER_MAC="52:54:00:${h:0:2}:${h:2:2}:${h:4:2}"

trap on_exit EXIT

# --- snapshot ---------------------------------------------------------------
htime snapshot-start
lv_snapshot_create "$APP_LV" "$FOUNDATION_LV"
lv_activate "$APP_LV"
htime snapshot-end
[[ -b "/dev/$VG/$APP_LV" ]] || die "/dev/$VG/$APP_LV is not a block device after activation"

# --- link -------------------------------------------------------------------
tmp="$(mktemp "$RUN/.owner.XXXXXX")"
owner_text >"$tmp"
install -o root -g root -m 0644 "$tmp" "$OWNER"
rm -f -- "$tmp"
OWNER_WRITTEN=1
log "owner written: $OWNER"
"$PING_CLIENT" netcfg-add "$NETVM_CID" "$LINK_ID" "$SLOT_MAC" "$PEER" 100 \
  || die "NETCFG ADD $LINK_ID failed"
LINK_ADDED=1
log "NETCFG ADD $LINK_ID $SLOT_MAC $PEER metric 100 to CID $NETVM_CID: OK"

# --- the builder ------------------------------------------------------------
APPEND="root=/dev/vda ro rootfstype=ext4 console=ttyS0 reboot=t panic=-1 ipv6.disable=1"
APPEND+=" km.ip=$PEER km.gw=$GW km.dns=$DNS km.name=$BUILDER_NAME"
# No "--": microvm appends its virtio_mmio.device= parameters after -append,
# and after "--" the kernel would hand them to init (cu1 H2 halt). A bare word
# without "=" or "." reaches init as an argument anyway.
APPEND+=" init=/usr/bin/bash /dev/vdc"

UNIT="km-cu1-builder-$TYPE$SUFFIX-$(date +%s)"
htime builder-start
systemd-run --unit="$UNIT" \
  --description="KatMate cu1 layer builder for $VG/$APP_LV (dev scaffolding, transient)" \
  -p StandardInput=null -p StandardOutput=journal -p StandardError=journal \
  -p KillMode=control-group -p TimeoutStopSec=30s \
  /usr/bin/qemu-system-x86_64 \
    -enable-kvm -nodefaults -no-user-config -no-reboot \
    -machine microvm,accel=kvm,acpi=off,pit=off,pic=off,rtc=off,memory-backend=mem \
    -cpu host -smp "$VCPUS" -display none -monitor none \
    -chardev stdio,id=console0,signal=off -serial chardev:console0 \
    -object memory-backend-memfd,id=mem,size="$MEM",share=on \
    -kernel "$KERNEL" \
    -append "$APPEND" \
    -object iothread,id=iothread0 \
    -drive file="/dev/$VG/$FOUNDATION_LV",if=none,id=disk0,format=raw,readonly=on,cache=none,aio=threads \
    -device virtio-blk-device,drive=disk0,iothread=iothread0 \
    -drive file="/dev/$VG/$APP_LV",if=none,id=disk1,format=raw,cache=none,aio=threads \
    -device virtio-blk-device,drive=disk1,iothread=iothread0 \
    -drive file="$CODE_IMG",if=none,id=disk2,format=raw,readonly=on \
    -device virtio-blk-device,drive=disk2,iothread=iothread0 \
    -drive file="$DATA_IMG",if=none,id=disk3,format=raw,readonly=on \
    -device virtio-blk-device,drive=disk3,iothread=iothread0 \
    -device virtio-rng-device \
    -netdev "dgram,id=link0,local.type=unix,local.path=$SLOT_DIR/appvm,remote.type=unix,remote.path=$SLOT_DIR/netvm" \
    -device virtio-net-device,netdev=link0,mac="$BUILDER_MAC" \
    -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
log "started $UNIT"

deadline=$(( $(date +%s) + TIMEOUT_S ))
TIMED_OUT=""
while :; do
  case "$(systemctl is-active "$UNIT" 2>/dev/null || true)" in
  active|activating|deactivating) ;;
  *) break ;;
  esac
  if (( $(date +%s) >= deadline )); then
    TIMED_OUT=1
    log "timeout after ${TIMEOUT_S} s: stopping $UNIT"
    systemctl stop "$UNIT" || true
    break
  fi
  sleep 2
done
htime builder-exit
rm -f -- "$SLOT_DIR/appvm"

journalctl --sync 2>/dev/null || true
journalctl -u "$UNIT" -o cat --no-pager | tr -d '\r' >"$RUN/console.log"
journalctl -u "$UNIT" -o short-unix --no-pager | tr -d '\r' \
  | grep -aE 'KMB-|devtmpfs: mounted|as init process|Kernel panic|Deactivated|Main process exited|Failed with result' \
  >"$RUN/markers.txt" || true
sed -n 's/^KMB-PKG //p' "$RUN/console.log" >"$RUN/pkgs.txt"

withdraw_link

# Operator ruling 1 (cu1 H1): devtmpfs must be seen mounted before bash runs
# as init; without that the build is not accepted, whatever it reports.
dev_line="$(grep -anm1 'devtmpfs: mounted' "$RUN/console.log" | cut -d: -f1 || true)"
init_line="$(grep -anm1 'Run /usr/bin/bash as init process' "$RUN/console.log" | cut -d: -f1 || true)"
log "console: 'devtmpfs: mounted' at line ${dev_line:-<absent>}, 'Run /usr/bin/bash as init process' at line ${init_line:-<absent>}"
[[ -n "$dev_line" && -n "$init_line" ]] && (( dev_line < init_line )) \
  || die "HALT (ruling 1): devtmpfs was not seen mounted before bash ran as init"

ok="$(grep -c '^KMB-RESULT OK$' "$RUN/console.log" || true)"
fail="$(grep -c '^KMB-RESULT FAIL' "$RUN/console.log" || true)"
log "builder result lines: OK=$ok FAIL=$fail$([[ -n "$TIMED_OUT" ]] && echo ' (timed out)')"
[[ -z "$TIMED_OUT" && "$ok" == 1 && "$fail" == 0 ]] \
  || die "build failed: $(grep -a '^KMB-RESULT' "$RUN/console.log" | tr '\n' ' ')"

DATA_PCT="$(lvs --noheadings -o data_percent "$VG/$APP_LV" | tr -d ' ')"
printf 'data_percent %s\n' "$DATA_PCT" >>"$RUN/host-times.txt"
log "$VG/$APP_LV Data% $DATA_PCT"

# --- freeze, then the meta (after the freeze and the disarm, as app-layer.sh) -
htime freeze-start
lv_deactivate
lv_freeze "$APP_LV"
htime freeze-end
# shellcheck disable=SC2034  # read by lib.sh's cleanup()
SNAP_CREATED=""
trap - EXIT

APP_META="$WORK/meta/app-$TYPE$SUFFIX.meta"
APP_META_TMP="$(mktemp "$WORK/meta/.app-$TYPE$SUFFIX.meta.XXXXXX")"
cat >"$APP_META_TMP" <<EOF
KATMATE_META_VERSION=1
APP_TYPE=$TYPE
APP_LV=$VG/$APP_LV
APP_BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
APP_ROOTFSTYPE=ext4
BASE_LV=$VG/$FOUNDATION_LV
BASE_BUILT=$BASE_BUILT
KERNEL_VERSION=$KERNEL_VERSION
MANIFEST_SHA256=$MANIFEST_SHA256
BUILT_BY=builder-vm
EOF
chmod 0644 "$APP_META_TMP"
mv -f -- "$APP_META_TMP" "$APP_META"

log "$APP_LV ready: RO-frozen, built in the builder VM; meta $APP_META; run $RUN"
