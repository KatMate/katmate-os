# Katmate OS — builder VM program (spike cu1; dev scaffolding)
#
# PID 1 of the layer builder: the kernel runs `init=/usr/bin/bash /dev/vdc`,
# and vdc is build/lib.sh followed by this file, newline-padded, attached
# read-only by build/app-layer-vm.sh. Not executed on the host.
#
# Disks: vda the foundation (root, ro), vdb the target thin snapshot (rw),
# vdc this program, vdd a ustar with VERSION and manifest (the
# katmate-build-cfgdisk pattern, ADR-037 R33/R35). No vsock: every result
# leaves as a KMB-* line on the serial console. The network is configured here
# from km.* because katmate-init does not run in this VM (operator ruling D1(a)).
# The script ends by rebooting, which under `-no-reboot` ends QEMU; panic=-1
# covers an unplanned exit.

set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C
umask 022

PHASE=start
RESULT=""
T=/run/kmb/target
PKG_RE='^[a-z0-9][a-z0-9+.-]*$'
QUAD_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

phase() { PHASE="$1"; printf 'KMB-PHASE %s %s\n' "$1" "$(date +%s.%N)"; }

finish() {
  local rc=$?
  set +e
  [[ "$RESULT" == OK ]] || printf 'KMB-RESULT FAIL %s %s\n' "$PHASE" "$rc"
  umount -R "$T" 2>/dev/null
  sync
  echo b >/proc/sysrq-trigger
}
trap finish EXIT

phase pid1
printf 'KMB-PID1 pid=%s argv0=%s\n' "$$" "$0"

mount -t proc proc /proc
mount -t sysfs sys /sys
printf 'KMB-ARGV %s\n' "$(tr '\0' ' ' </proc/1/cmdline)"
printf 'KMB-DEVTMPFS %s\n' "$(grep -E '^[^ ]+ /dev devtmpfs ' /proc/mounts || echo ABSENT)"
mount -t tmpfs -o mode=0755,nosuid,nodev run /run
mount -t tmpfs -o mode=1777,nosuid,nodev tmp /tmp
mkdir -p /dev/pts
mount -t devpts -o gid=5,mode=620 devpts /dev/pts
ln -sfn /proc/self/fd /dev/fd
ln -sfn /proc/self/fd/0 /dev/stdin
ln -sfn /proc/self/fd/1 /dev/stdout
ln -sfn /proc/self/fd/2 /dev/stderr
printf 'KMB-CLOCK %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- disks: the target must be the only writable one, and not the root -------
phase disks
for d in vda vdb vdc vdd; do
  printf 'KMB-DISK %s dev=%s sectors=%s ro=%s\n' "$d" \
    "$(</sys/block/$d/dev)" "$(</sys/block/$d/size)" "$(</sys/block/$d/ro)"
done
[[ "$(</sys/block/vdb/ro)" == 0 ]] || die "vdb is read-only; it must be the target"
for d in vda vdc vdd; do
  [[ "$(</sys/block/$d/ro)" == 1 ]] || die "$d is writable; only vdb may be"
done
root_dev="$(stat -c '%Hd:%Ld' /)"
[[ "$root_dev" == "$(</sys/block/vda/dev)" ]] \
  || die "/ is on $root_dev, not on vda ($(</sys/block/vda/dev))"

# --- network, from km.* (ADR-038's shape, applied with ip) ---------------------
phase net
read -ra TOKS </proc/cmdline
kmval() {
  local t
  for t in "${TOKS[@]}"; do
    [[ "$t" == "km.$1="* ]] && { printf '%s' "${t#*=}"; return 0; }
  done
  return 1
}
IP="$(kmval ip)"; GW="$(kmval gw)"; DNS="$(kmval dns)"
NAME="$(kmval name || true)"
for v in "$IP" "$GW" "$DNS"; do
  [[ "$v" =~ $QUAD_RE ]] || die "km.* value '$v' is not a dotted quad"
done
[[ -z "$NAME" ]] || printf '%s' "$NAME" >/proc/sys/kernel/hostname

nics=()
for d in /sys/class/net/*; do
  [[ -e "$d/device" ]] && nics+=("${d##*/}")
done
(( ${#nics[@]} == 1 )) || die "expected one device-backed link, found ${#nics[@]}: ${nics[*]}"
NIC="${nics[0]}"
ip link set lo up
ip link set "$NIC" up
ip addr add "$IP/32" dev "$NIC"
ip route add default via "$GW" dev "$NIC" onlink
printf 'nameserver %s\n' "$DNS" >/run/resolv.conf
printf 'KMB-NET-UP %s %s/32 via %s dns %s\n' "$NIC" "$IP" "$GW" "$DNS"

netc() {
  printf 'KMB-NET %s rx=%s tx=%s\n' "$1" \
    "$(</sys/class/net/$NIC/statistics/rx_bytes)" "$(</sys/class/net/$NIC/statistics/tx_bytes)"
}

# --- manifest, from the data disk; revalidated here --------------------------
phase manifest
members="$(tar -tf /dev/vdd | tr '\n' ' ')"
[[ "$members" == "VERSION manifest " ]] || die "data disk lists '$members', expected 'VERSION manifest'"
[[ "$(tar -xOf /dev/vdd VERSION)" == 1 ]] || die "data disk VERSION is not 1"
mapfile -t PKGS <<<"$(tar -xOf /dev/vdd manifest)"
(( ${#PKGS[@]} > 0 )) && [[ -n "${PKGS[0]}" ]] || die "manifest is empty"
for p in "${PKGS[@]}"; do
  [[ "$p" =~ $PKG_RE ]] || die "manifest entry '$p' is not a package name"
done
printf 'KMB-MANIFEST count=%s sha256=%s\n' "${#PKGS[@]}" \
  "$(tar -xOf /dev/vdd manifest | sha256sum | cut -d' ' -f1)"

# --- build: app-layer.sh's steps, against vdb --------------------------------
phase mount
mkdir -p "$T"
mount -t ext4 /dev/vdb "$T"
mount -t proc proc "$T/proc"
mount -t sysfs sys "$T/sys"
mount --rbind /dev "$T/dev"
mount --make-rslave "$T/dev"
resolv_link_check "$T"
cp /run/resolv.conf "$T/run/resolv.conf"

netc before-update
phase apt-update
chroot_run "$T" apt-get update
netc after-update
phase apt-install
chroot_run "$T" apt-get install -y "${PKGS[@]}"
netc after-install

phase clean
chroot_run "$T" apt-get clean
resolv_link_install "$T"
resolv_link_check "$T"
printf 'KMB-RESOLV ok\n'
rm -rf "$T"/var/lib/apt/lists/* 2>/dev/null || true

phase pkglist
chroot "$T" dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' | sed 's/^/KMB-PKG /'
printf 'KMB-PKGCOUNT %s\n' "$(chroot "$T" dpkg-query -W -f='.\n' | wc -l)"

phase umount
umount -R "$T"
sync
phase finished
RESULT=OK
printf 'KMB-RESULT OK\n'
exit 0
