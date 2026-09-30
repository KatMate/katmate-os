#!/usr/bin/env bash
# Katmate OS — netVM sysVM build (ADR-021)
#
# netVM is a DISTINCT COMPONENT CLASS (sysVM), not the foundation and not an
# app-layer. It does NOT share the foundation, carries full systemd (with
# dhcpcd, not networkd, on the uplink), boots q35 with a passed-through NIC
# (vfio), holds its own PRIVILEGED control agent (netvm-agent), and updates on
# its own track (netvm-update), never via katmate-update. See ADR-021.
#
# Divergences from foundation.sh (deliberate, per ADR-021 / ADR-018):
#   - STANDALONE LINEAR RW LV, not thin and not in a snapshot chain (netVM is
#     nobody's backing store) -> no -K -ay skip-activation, no RO-freeze.
#   - NOT frozen: runtime-mutable state (/var, leases, resolv.conf,
#     logs, and host-delivered dynamic /32 routes) lives on the RW LV. The image
#     is disposable: rebuild = overwrite the LV.
#   - full systemd (debootstrap default variant, NOT --variant=minbase).
#   - Debian STOCK kernel (linux-image-amd64) + generated initramfs, both
#     EXPORTED host-side; no in-guest bootloader (direct -kernel/-initrd boot).
#   - no waypipe, no katmate-init. netvm-agent runs as a systemd unit.
#
# Because lib.sh's cleanup()/state model is thin-snapshot specific (SNAP_CREATED
# / FREEZE_DONE / -K -ay), netVM does NOT reuse it. It sources lib.sh only for
# neutral helpers (log/die/require_root/mount_root/umount_root/chroot_run) and
# installs its OWN trap + cleanup for the linear-LV case (ADR-021, option B).
#
# Secrets and per-installation values are NOT baked here, and neither is any
# VPN provider's configuration. Vanilla egress is direct through the uplink
# (ADR-037 R2). The image carries wireguard-tools for a post-install VPN and no
# tunnel config and no template: a provider config is the user's T1, not the
# release's T4 (R20), and the build refuses an image whose baked conf tree names
# `proton` (step 5). Per-installation configuration reaches netVM at run time
# through a read-only config disk (R8): the host builds it at every start, and
# the image carries only its consumer, katmate-cfgdisk.service (step 5, R38).
#
# Run on MINIS (build host). Authored on Acer, GPG-signed, rsync-pushed. bash,
# not fish. root required (debootstrap, lvcreate, mount, chroot).

set -euo pipefail

BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/config.sh
source "$BUILD_DIR/config.sh"
# shellcheck source=build/lib.sh
source "$BUILD_DIR/lib.sh"   # neutral helpers only; NOT lib.sh's cleanup/trap

# --- netVM parameters (promote to config.sh once a second sysVM appears) ------
NETVM_LV="${NETVM_LV:-vm_sys_netvm}"          # standalone linear RW LV
NETVM_LV_SIZE="${NETVM_LV_SIZE:-4G}"          # rootfs + runtime state
NETVM_MNT="${NETVM_MNT:-/mnt/netvm-build}"
# Manifest follows the app-layer convention: a flat <name>.list of packages
# (same format/parser as manifests/web.list). netVM additionally needs a config
# tree, which app-layers do not (they inherit config from the foundation); that
# is the one net-new element, kept beside the .list as netvm.conf.d/.
NETVM_PKGS="${NETVM_PKGS:-$MANIFESTS/netvm.list}"
NETVM_CONFD="${NETVM_CONFD:-$MANIFESTS/netvm.conf.d}"   # config tree baked verbatim
NETVM_OUT="${NETVM_OUT:-$OUT/netvm}"          # BUILD tree export (never read at runtime)
# T2 runtime location (ADR-032 §5): vmlinuz + initrd.img + netvm.meta together.
# Payload and its metadata share a tier and a lifecycle, hence one directory.
# This is what a unit reads; $NETVM_OUT is not.
NETVM_RUNTIME_DIR="${NETVM_RUNTIME_DIR:-$KATMATE_STATE_DIR/netvm}"
GUEST_KERNEL_PKG="${GUEST_KERNEL_PKG:-linux-image-${ARCH}}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
SECURITY_MIRROR="${SECURITY_MIRROR:-http://security.debian.org/debian-security}"

# netvm-agent binary (produced by the agent Cargo workspace, ADR-021). This
# script does NOT build it: it runs as root, and the toolchain is the build
# user's. The preflight refuses a missing binary, and a stale one: any file of
# the agent's sources (NETVM_AGENT_SRCS) newer than the binary (R120). A stale
# binary is baked silently otherwise: open problem #14 cost a boot cycle on
# 2026-07-23, and on 2026-09-30 out/ still held that day's binary until step 4c
# rebuilt it by hand.
NETVM_AGENT_BIN="${NETVM_AGENT_BIN:-$OUT/netvm-agent}"
NETVM_AGENT_SRCS=(
  "$ROOT_DIR/agent/crates/netvm-agent"
  "$ROOT_DIR/agent/crates/katmate-protocol"
  "$ROOT_DIR/agent/Cargo.lock"
)

DEV="/dev/$VG/$NETVM_LV"

# --- own cleanup / rollback (linear LV; not lib.sh's thin model) --------------
# On any failure mid-write (e.g. a bad chroot call during initramfs/boot
# writes), the ext4 journal can stay busy if we umount while it is still hot.
# So: umount FIRST (a sync on a still-open mount does not settle jbd2), then
# sync + settle, then deactivate explicitly, and if the LV is still busy, say
# so LOUDLY with the exact manual command rather than silently leaving a stuck
# LV behind (which previously masqueraded as a successful rollback and forced a
# host reboot).
NETVM_LV_CREATED=""

# lib.sh:umount_root() swallows failure (2>/dev/null || true). Here we need to
# KNOW: a failed umount is exactly the hot-jbd2 case the warning below exists
# for. Same MOUNTED state variable, louder contract.
netvm_umount() {
  [[ -n "${MOUNTED:-}" ]] || return 0
  if ! umount -R "$MOUNTED"; then
    echo "WARNING: umount -R $MOUNTED failed — pseudo-fs or ext4 journal still busy." >&2
    return 1
  fi
  MOUNTED=""
}

netvm_cleanup() {
  local rc=$?
  sync
  umount_root                         # lib.sh helper (umount -R; own MOUNTED)
  udevadm settle 2>/dev/null || true
  if [[ $rc -ne 0 && -n "$NETVM_LV_CREATED" ]]; then
    log "netvm.sh FAILED (rc=$rc) — removing half-built LV $DEV"
    lvchange -an "$DEV" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    if ! lvremove -f "$DEV" 2>/dev/null; then
      echo "" >&2
      echo "WARNING: could not remove $DEV automatically (filesystem still busy)." >&2
      echo "  A hot ext4 journal (jbd2) is likely still holding the device." >&2
      echo "  Try, in order:" >&2
      echo "    sudo sync; sudo udevadm settle" >&2
      echo "    sudo lvchange -an $DEV && sudo lvremove -f $DEV" >&2
      echo "  If it still reports 'in use', a host reboot clears the stuck" >&2
      echo "  jbd2 kthread; then: sudo lvremove -f $DEV" >&2
      echo "" >&2
    fi
  fi
  exit "$rc"
}
trap netvm_cleanup EXIT

# --- preflight ----------------------------------------------------------------
require_root
command -v debootstrap >/dev/null || die "debootstrap not installed"
[[ -f "$NETVM_PKGS"  ]] || die "package manifest not found: $NETVM_PKGS"
[[ -d "$NETVM_CONFD" ]] || die "config tree not found: $NETVM_CONFD"
# The uplink's guest PCI address (build/config.sh). A malformed value would reach
# the step-5a gate as an expected Path= that no file could carry; say so here.
[[ "${NETVM_UPLINK_PCI_ADDR:-}" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] \
  || die "NETVM_UPLINK_PCI_ADDR is '${NETVM_UPLINK_PCI_ADDR:-}', expected a PCI address such as 0000:00:04.0 (build/config.sh)"

# netvm-agent: present, and not older than any of its sources (R120). Here, not
# in step 7, so the refusal comes before the LV exists. -newer compares mtimes,
# which rsync preserves from the Acer, so a source edited after the last build
# reads newer after the sync.
[[ -f "$NETVM_AGENT_BIN" ]] || die "Missing netvm-agent binary: $NETVM_AGENT_BIN
  Build it as the build user (not root) and copy it here (ADR-021, R120):
    (cd agent && cargo build --release -p netvm-agent && cp target/release/netvm-agent $NETVM_AGENT_BIN)"
for src in "${NETVM_AGENT_SRCS[@]}"; do
  [[ -e "$src" ]] || die "netvm-agent source not found: $src (R120 checks the binary against it)"
done
NETVM_AGENT_NEWER="$(find "${NETVM_AGENT_SRCS[@]}" -type f -newer "$NETVM_AGENT_BIN" -print)"
[[ -z "$NETVM_AGENT_NEWER" ]] || die "Stale netvm-agent binary: $NETVM_AGENT_BIN is older than its sources (R120):
$NETVM_AGENT_NEWER
  Rebuild it as the build user and copy it here:
    (cd agent && cargo build --release -p netvm-agent && cp target/release/netvm-agent $NETVM_AGENT_BIN)"
log "netvm-agent: $NETVM_AGENT_BIN; no file of its sources is newer (R120)"

if lvs "$DEV" >/dev/null 2>&1; then
  die "$DEV already exists — refusing to clobber. Remove deliberately first: lvremove -f $DEV"
fi

# --- 1. standalone linear RW LV ----------------------------------------------
# NOTE: lib.sh has lv_thin_create / lv_snapshot_create but no linear helper.
# netVM is intentionally NOT thin (nobody's backing store), so create directly.
# Promote to lib.sh:lv_linear_create once a second sysVM needs it (ADR-021 B).
log "Creating standalone linear RW LV $DEV ($NETVM_LV_SIZE)"
lvcreate -y -L "$NETVM_LV_SIZE" -n "$NETVM_LV" "$VG"
NETVM_LV_CREATED=1

log "mkfs.ext4 on bare LV (no partition table; guest boots root=/dev/vda)"
mkfs.ext4 -q -L netvm "$DEV"

mkdir -p "$NETVM_MNT"
# mount_root mounts /dev/$VG/$lv + pseudo-fs. For a fresh ext4 the pseudo-fs
# dirs do not exist yet, so debootstrap must run FIRST, then mount pseudo-fs.
# We therefore mount ONLY the root here, and mount_root AFTER debootstrap.
mount "$DEV" "$NETVM_MNT"
MOUNTED="$NETVM_MNT"    # register with lib.sh state so umount_root works

# --- 2. debootstrap (systemd variant — NOT minbase) --------------------------
# Default variant pulls systemd/init: netVM runs systemd as PID 1 (its units,
# udev's .link renames, nftables.service), the opposite of foundation.sh
# --variant=minbase.
log "debootstrap $DEBIAN_SUITE (systemd variant) into $NETVM_MNT"
debootstrap \
  --arch="$ARCH" \
  --include=systemd,systemd-sysv,udev,ifupdown \
  "$DEBIAN_SUITE" "$NETVM_MNT" "$DEBIAN_MIRROR"

# pseudo-fs AFTER debootstrap (fresh ext4 had no /proc /sys /dev yet) — the same
# ordering foundation.sh learned. mount_root re-mounts root (idempotent: already
# mounted) then adds proc/sys/dev. To avoid a double root mount, mount pseudo-fs
# directly here rather than calling mount_root (root is already mounted above).
mount -t proc  proc "$NETVM_MNT/proc"
mount -t sysfs sys  "$NETVM_MNT/sys"
mount --rbind  /dev "$NETVM_MNT/dev"
mount --make-rslave "$NETVM_MNT/dev"

# --- 3. apt sources: enable non-free-firmware (rtl8125b-2.fw) -----------------
log "Writing apt sources with non-free-firmware component"
cat > "$NETVM_MNT/etc/apt/sources.list" <<APT
deb $DEBIAN_MIRROR $DEBIAN_SUITE main non-free-firmware
deb $DEBIAN_MIRROR ${DEBIAN_SUITE}-updates main non-free-firmware
deb $SECURITY_MIRROR ${DEBIAN_SUITE}-security main non-free-firmware
APT

# --- 4. install package manifest ---------------------------------------------
# Manifest: one package per line, '#' comments and blanks ignored. Parser is
# bit-for-bit identical to app-layer.sh so the two never diverge on the format.
#
# Set MODULES=most BEFORE installing the kernel: linux-image-amd64's postinst
# generates the initramfs itself, and with this conf already in place it makes a
# correctly-populated initrd at kernel install time — the only initramfs write
# is the kernel's own postinst, inside the apt transaction.
#
# NOTE: MODULES=most, not dep. This image is built in a chroot on a mounted LV
# (root = ext4-on-dm), but BOOTS as a virtio guest (root = /dev/vda on
# virtio-blk). MODULES=dep resolves modules against the BUILD root and omits
# virtio_blk/virtio_pci, leaving the guest unable to find /dev/vda
# ("ALERT! /dev/vda does not exist"). MODULES=most includes the full virtio +
# common-storage set regardless of build context. The extra few MB of initrd are
# irrelevant for a sysVM. (dep failed the first sysVM boot, 2026-07-09.)
log "Pre-seeding initramfs MODULES=most (build ctx != virtio runtime ctx)"
install -D -m 0644 /dev/stdin \
  "$NETVM_MNT/etc/initramfs-tools/conf.d/modules-most" <<< 'MODULES=most'

log "Installing netVM package manifest"
mapfile -t PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$NETVM_PKGS")
[[ ${#PKGS[@]} -gt 0 ]] || die "Manifest $NETVM_PKGS lists no packages"
log "Install manifest: ${PKGS[*]}"
cp /etc/resolv.conf "$NETVM_MNT/etc/resolv.conf"   # build-time DNS only
chroot_run "$NETVM_MNT" apt-get update
chroot_run "$NETVM_MNT" apt-get install -y --no-install-recommends "${PKGS[@]}"

# --- 5. bake config tree (declarative; closes the netinst drift class) --------
# Everything under conf.d/ is copied verbatim into the image. This is the ONLY
# author of netVM's BAKED configuration — no installer, no drift.
# Per-installation configuration is not baked: it arrives at every boot on the
# read-only config disk (ADR-037 R8), and the guest writes it only to /run,
# never over a file this step baked (R38). The tree is
# appVM-AGNOSTIC: it bakes the uplink's name and DHCP client config, firewall
# policy, DNS forwarder config, sysctl —
# and NO internal /32 route (not even personalVM). All internal routes arrive
# at launch via the agent's NETCFG (ADR-021).
#
# OWNERSHIP (open problem #38, ruling R23): everything baked here lands
# root:root. `cp -a` alone preserved the builder's owner, and the build tree on
# the build host is host:host (uid 1000), so the ruleset and every network file
# in the image were owned by uid 1000. `--no-preserve=ownership` keeps -a's
# modes, timestamps and recursion but lets a root cp create each file as root.
# Mode stays the tracked git mode: that is a property of the tree, not of this
# copy. (Rejected: `rsync -a --chown=0:0` — a tool this script does not otherwise
# need; a `chown -R` after the copy — it would have to name every destination
# path anyway, and a recursive chown on /etc or /usr/lib reaches files this
# step did not write.)
log "Baking netVM config tree from $NETVM_CONFD"
cp -a --no-preserve=ownership "$NETVM_CONFD/." "$NETVM_MNT/"

# Read back the outcome, not the flag: every path the conf tree names must be
# 0:0 in the image. The count is printed beside the verdict, so a walk that
# found nothing cannot read as a walk that found everything correct.
NETVM_CONFD_PATHS=0
while IFS= read -r -d '' rel; do
  owner="$(stat -c '%u:%g' -- "$NETVM_MNT/$rel")" \
    || die "step 5 read-back: $rel is in the conf tree but not in the image"
  [[ "$owner" == "0:0" ]] \
    || die "step 5 read-back: /$rel is owned $owner in the image, expected 0:0 (open problem #38)"
  NETVM_CONFD_PATHS=$((NETVM_CONFD_PATHS + 1))
done < <(cd "$NETVM_CONFD" && find . -mindepth 1 -printf '%P\0')
[[ $NETVM_CONFD_PATHS -gt 0 ]] || die "step 5 read-back: the conf tree $NETVM_CONFD yielded no paths"
log "Read-back OK: $NETVM_CONFD_PATHS conf-tree paths in the image, all owned 0:0"

# The baked ruleset must parse (ADR-037 R52): the IMAGE's nft, on the baked
# /etc/nftables.conf, in the build chroot, as root. A ruleset that fails to
# load at boot leaves netVM forwarding with no firewall (open problem #48),
# so a parse failure stops the build here instead. Root is required: run
# unprivileged, `nft -c` fails on every input, valid or not (state.md
# Invariants), so it could not tell a broken file from a good one.
#
# THIS IS NOT GATE F12a. The chroot shares the build host's kernel, so this
# checks the file against the HOST kernel's nf_tables through the image's
# nft binary. F12a is taken inside the booted guest.
#
# /usr/sbin/nft by absolute path, because chroot_run sets no PATH (step 6).
# No mount is added: proc, sys and /dev are mounted after debootstrap above,
# and nft needs a netlink socket, not a filesystem.
[[ -x "$NETVM_MNT/usr/sbin/nft" ]] \
  || die "nft preflight: /usr/sbin/nft is missing or not executable in the image (package nftables)"
if ! NETVM_NFT_CHECK="$(chroot_run "$NETVM_MNT" /usr/sbin/nft -c -f /etc/nftables.conf 2>&1)"; then
  die "nft preflight: the image's nft rejects the baked /etc/nftables.conf (checked against the build host's kernel, ADR-037 R52):
$NETVM_NFT_CHECK"
fi
log "nft preflight OK: the image's nft -c -f /etc/nftables.conf exit 0 (build host's kernel; not gate F12a)"

# Nothing baked in this rebuild references `proton` (ADR-037 R20): the old
# ProtonVPN template and ruleset are gone, and a provider's name in the image
# would be the release asserting the user's T1. Searched over the image's copy
# of every conf-tree file, so an edit made after the copy is seen too.
mapfile -d '' NETVM_CONFD_FILES < <(cd "$NETVM_CONFD" && find . -type f -printf '%P\0')
[[ ${#NETVM_CONFD_FILES[@]} -gt 0 ]] || die "proton check: the conf tree $NETVM_CONFD yielded no files"
if (cd "$NETVM_MNT" && grep -nF -- proton "${NETVM_CONFD_FILES[@]}"); then
  die "baked conf tree names 'proton' (above): nothing in the vanilla image may reference a VPN provider (ADR-037 R20)"
fi
log "proton check OK: ${#NETVM_CONFD_FILES[@]} baked conf-tree files, none names 'proton'"

# dhcpcd, not systemd-networkd, holds the uplink (ADR-037 R6), and networkd is
# DISABLED (R15): after R6 it has no job, and left enabled it is a second
# DHCP-capable daemon in the most exposed VM. Disabled explicitly, not merely
# left unenabled, so the state is a statement the read-back below can check.
# wait-online is named too: enabling networkd enables it (Also=), and left
# enabled it would hold network-online.target for its timeout, waiting on a
# networkd that is not running. systemd-resolved is not installed (ADR-037
# R18: netVM resolves directly upstream through /etc/resolv.conf, written by
# dhcpcd).
#
# katmate-cfgdisk.service is the config disk's consumer (ADR-037 R38): a
# oneshot before dhcpcd that writes /run/katmate-cfg/dhcpcd.conf, which
# dhcpcd reads through the baked drop-in. It is enabled with the others.
#
# katmate-ip-forward.service switches IPv4 forwarding on, and only after
# nftables.service has loaded the ruleset (ADR-037 R111; open problem #48):
# Requires= and After= on it, so a ruleset that fails to load leaves netVM
# not forwarding. sysctl.d no longer sets ip_forward; the check after the
# enablement read-back refuses an image in which it still does.
log "Enabling systemd services (dhcpcd, dnsmasq, nftables, katmate-cfgdisk, katmate-ip-forward); disabling systemd-networkd"
chroot_run "$NETVM_MNT" systemctl enable dhcpcd
chroot_run "$NETVM_MNT" systemctl enable dnsmasq
chroot_run "$NETVM_MNT" systemctl enable nftables
chroot_run "$NETVM_MNT" systemctl enable katmate-cfgdisk
chroot_run "$NETVM_MNT" systemctl enable katmate-ip-forward
NETVM_NETWORKD_UNITS=(systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service)
chroot_run "$NETVM_MNT" systemctl disable "${NETVM_NETWORKD_UNITS[@]}"

# Read back the enablement state, not the commands' exit codes.
netvm_unit_state() { chroot_run "$NETVM_MNT" systemctl is-enabled "$1" 2>/dev/null || true; }
for u in dhcpcd.service dnsmasq.service nftables.service katmate-cfgdisk.service katmate-ip-forward.service; do
  st="$(netvm_unit_state "$u")"
  [[ "$st" == enabled ]] || die "step 5 read-back: $u is '$st' in the image, expected enabled"
done
for u in "${NETVM_NETWORKD_UNITS[@]}"; do
  st="$(netvm_unit_state "$u")"
  [[ "$st" == disabled ]] || die "step 5 read-back: $u is '$st' in the image, expected disabled (ADR-037 R15)"
done
log "Read-back OK: dhcpcd, dnsmasq, nftables, katmate-cfgdisk, katmate-ip-forward enabled; ${#NETVM_NETWORKD_UNITS[@]} networkd units disabled"

# R111's other half: nothing that systemd-sysctl reads may turn forwarding on
# at boot behind the ruleset's back. Every sysctl.d directory in the image,
# the conf tree's own file included. `net.ipv4.conf.*.forwarding` is the
# per-interface form of the same switch.
NETVM_SYSCTL_DIRS=()
for d in etc/sysctl.d run/sysctl.d usr/local/lib/sysctl.d usr/lib/sysctl.d; do
  [[ -d "$NETVM_MNT/$d" ]] && NETVM_SYSCTL_DIRS+=("$NETVM_MNT/$d")
done
[[ ${#NETVM_SYSCTL_DIRS[@]} -gt 0 ]] || die "step 5 read-back: no sysctl.d directory in the image (the conf tree bakes etc/sysctl.d)"
if grep -rnE '^[[:space:]]*-?net[./]ipv4[./](ip_forward|conf[./][^[:space:]=]+[./]forwarding)[[:space:]]*=' -- "${NETVM_SYSCTL_DIRS[@]}" "$NETVM_MNT/etc/sysctl.conf" 2>/dev/null; then
  die "step 5 read-back: a sysctl file in the image sets IPv4 forwarding (above); only katmate-ip-forward.service may, after nftables.service (ADR-037 R111)"
fi
log "Read-back OK: no sysctl file in the image sets IPv4 forwarding (${#NETVM_SYSCTL_DIRS[@]} sysctl.d directories and /etc/sysctl.conf searched)"

# The config disk's consumer, read back as the image holds it (ADR-037 R38).
# Without the drop-in, dhcpcd would read the baked /etc/dhcpcd.conf and ignore a
# static uplink with no diagnostic, so the -f line itself is checked, not just
# the file. Without tar the consumer cannot read the disk, dhcpcd does not
# start, and the image has no uplink.
NETVM_CFGDISK_DROPIN="$NETVM_MNT/etc/systemd/system/dhcpcd.service.d/katmate-cfgdisk.conf"
[[ -f "$NETVM_CFGDISK_DROPIN" ]] \
  || die "step 5 read-back: ${NETVM_CFGDISK_DROPIN#"$NETVM_MNT"} is missing from the image"
grep -qxF 'ExecStart=/usr/sbin/dhcpcd -q -b -f /run/katmate-cfg/dhcpcd.conf' "$NETVM_CFGDISK_DROPIN" \
  || die "step 5 read-back: ${NETVM_CFGDISK_DROPIN#"$NETVM_MNT"} does not point dhcpcd at /run/katmate-cfg/dhcpcd.conf"
[[ -x "$NETVM_MNT/usr/lib/katmate/katmate-cfgdisk-apply" ]] \
  || die "step 5 read-back: /usr/lib/katmate/katmate-cfgdisk-apply is missing or not executable in the image"
[[ -x "$NETVM_MNT/usr/bin/tar" || -x "$NETVM_MNT/bin/tar" ]] \
  || die "step 5 read-back: tar is in neither /usr/bin nor /bin in the image; katmate-cfgdisk-apply reads the config disk with it"
log "Read-back OK: katmate-cfgdisk consumer executable, dhcpcd drop-in present with -f /run/katmate-cfg/dhcpcd.conf, tar in the image"

# dnsmasq serves DNS on the slots and nothing else (ADR-037 R17), and its D-Bus
# interface stays off (operator ruling, 2026-09-27: libdbus-1-3 is accepted
# only as a library with no bus). The tracked config carries none of these;
# this refuses an image in which anything that dnsmasq reads does.
NETVM_DNSMASQ_CONF=("$NETVM_MNT/etc/dnsmasq.conf")
[[ -d "$NETVM_MNT/etc/dnsmasq.d" ]] && NETVM_DNSMASQ_CONF+=("$NETVM_MNT/etc/dnsmasq.d")
if grep -rnE '^[[:space:]]*(enable-dbus|bind-interfaces|bind-dynamic|dhcp-range|enable-ra)([[:space:]=]|$)' -- "${NETVM_DNSMASQ_CONF[@]}"; then
  die "dnsmasq configuration in the image carries a forbidden option (above): netVM's dnsmasq is DNS only, default wildcard mode, no D-Bus (ADR-037 R17)"
fi
grep -qxF 'DNSMASQ_EXCEPT="lo"' "$NETVM_MNT/etc/default/dnsmasq" \
  || die "/etc/default/dnsmasq in the image does not set DNSMASQ_EXCEPT=\"lo\" (ruling R29): dnsmasq would listen on loopback and could register itself as the system resolver"

# No resolvconf implementation in the image (R18). With one present, dhcpcd's
# 20-resolv.conf hook hands DNS to it instead of writing /etc/resolv.conf, and
# dnsmasq's packaged helper switches its upstream to /run/dnsmasq/resolv.conf.
# systemd-resolved, openresolv and resolvconf all provide one.
for p in usr/sbin/resolvconf usr/bin/resolvconf sbin/resolvconf; do
  [[ ! -e "$NETVM_MNT/$p" ]] \
    || die "/$p exists in the image: a resolvconf implementation would take /etc/resolv.conf away from dhcpcd (ADR-037 R18)"
done
log "dnsmasq config OK: slots only, no DHCP/RA/D-Bus, DNSMASQ_EXCEPT=lo; no resolvconf in the image"

# ctnetlink is loaded at boot (R115), because netvm-agent's REMOVE ends with a
# conntrack delete by mark (R107) and a missing subsystem would make it ERR.
# Read back all three things the load depends on: the baked file names the
# module and nothing else, the module is in the image's kernel tree, and
# systemd-modules-load is pulled in at boot. That it is LOADED is part B's
# reading (lsmod in the guest), not a build's.
NETVM_MODLOAD="$NETVM_MNT/etc/modules-load.d/katmate-ctnetlink.conf"
[[ -f "$NETVM_MODLOAD" ]] \
  || die "step 5 read-back: ${NETVM_MODLOAD#"$NETVM_MNT"} is missing from the image (R115)"
NETVM_MODLOAD_BODY="$(grep -vE '^[[:space:]]*([#;]|$)' -- "$NETVM_MODLOAD" || true)"
[[ "$NETVM_MODLOAD_BODY" == nf_conntrack_netlink ]] \
  || die "step 5 read-back: ${NETVM_MODLOAD#"$NETVM_MNT"} must name exactly nf_conntrack_netlink, found: '${NETVM_MODLOAD_BODY}' (R115)"
mapfile -d '' NETVM_CTNL_KO < <(find "$NETVM_MNT/usr/lib/modules" -name 'nf_conntrack_netlink.ko*' -print0 2>/dev/null)
[[ ${#NETVM_CTNL_KO[@]} -ge 1 ]] \
  || die "step 5 read-back: no nf_conntrack_netlink.ko* under /usr/lib/modules in the image; the kernel must carry ctnetlink as a module (CONFIG_NF_CT_NETLINK=m, R115)"
# The wants entry is a symlink; test the entry itself, not its target: from
# outside the chroot an absolute target would resolve on the BUILD host.
NETVM_MODLOAD_WANTS="$NETVM_MNT/usr/lib/systemd/system/sysinit.target.wants/systemd-modules-load.service"
[[ -L "$NETVM_MODLOAD_WANTS" || -f "$NETVM_MODLOAD_WANTS" ]] \
  || die "step 5 read-back: /usr/lib/systemd/system/sysinit.target.wants/systemd-modules-load.service is missing from the image; nothing would read modules-load.d at boot (R115)"
log "Read-back OK: modules-load.d names nf_conntrack_netlink; module present (${NETVM_CTNL_KO[0]#"$NETVM_MNT"}); systemd-modules-load wanted by sysinit.target"
# networking.service (ifupdown) stays present but inert: interfaces is reduced
# to lo+source in the conf tree, so it does nothing on the uplink. Not disabled.

# --- 5a. build gate: the .link files (ADR-035 note 2026-09-20, ADR-037 R12) ----
# Seventeen interface names are load-bearing in this image: km00..km0f, which
# NETCFG and the slot pool address, and uplink0, which dhcpcd's allowinterfaces
# and the ruleset's oifname are written against. udev renames nothing in a
# chroot, so what a build can check is the FILES that will do the renaming;
# whether the names are taken at boot is gate G2's, at runtime.
#
# Exactly 17 katmate .link files anywhere systemd-udevd reads .link files, and
# each one's effective content (comments and blank lines dropped) is exactly
# what is expected. A stray copy in /etc, a missing slot, a MAC or name typo,
# or an uplink Path= that is not NETVM_UPLINK_PCI_ADDR all stop the build.
log "Build gate: katmate .link files (17 expected)"
netvm_link_body() { grep -vE '^[[:space:]]*([#;]|$)' -- "$1" || true; }
NETVM_LINK_DIRS=()
for d in etc/systemd/network run/systemd/network usr/local/lib/systemd/network usr/lib/systemd/network; do
  [[ -d "$NETVM_MNT/$d" ]] && NETVM_LINK_DIRS+=("$NETVM_MNT/$d")
done
NETVM_KM_LINKS=()
if [[ ${#NETVM_LINK_DIRS[@]} -gt 0 ]]; then
  mapfile -d '' NETVM_KM_LINKS < <(find "${NETVM_LINK_DIRS[@]}" -maxdepth 1 -name '*katmate*.link' -print0)
fi
[[ ${#NETVM_KM_LINKS[@]} -eq 17 ]] \
  || die "build gate: ${#NETVM_KM_LINKS[@]} katmate .link files in the image, expected 17: ${NETVM_KM_LINKS[*]:-(none)}"
NETVM_LINK_DIR="$NETVM_MNT/usr/lib/systemd/network"

# The same sixteen slots, as the BAKED ruleset binds them (ADR-037 R48): chain
# slot_guard must carry exactly one `iifname "kmkk" ip saddr 10.100.1.(16+k)
# return` per slot, and no other return. The chain is the lines after
# `chain slot_guard {` up to the first line that begins with `}`; comments are
# dropped and whitespace is collapsed. It is counted first, so an absent or
# doubled chain dies with a name instead of an empty extraction.
NETVM_NFT="$NETVM_MNT/etc/nftables.conf"
[[ -f "$NETVM_NFT" ]] || die "build gate: /etc/nftables.conf is missing from the image"
NETVM_GUARD_CHAINS="$(grep -cE '^[[:space:]]*chain[[:space:]]+slot_guard[[:space:]]*\{' -- "$NETVM_NFT" || true)"
[[ "$NETVM_GUARD_CHAINS" == 1 ]] \
  || die "build gate: /etc/nftables.conf carries $NETVM_GUARD_CHAINS 'chain slot_guard {' lines, expected 1 (ADR-037 R48)"
NETVM_GUARD="$(awk '/^[[:space:]]*chain[[:space:]]+slot_guard[[:space:]]*\{/ {g=1; next}
                    g && /^[[:space:]]*\}/ {exit}
                    g' "$NETVM_NFT" \
               | sed -e 's/#.*//' -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//')"
for i in $(seq 0 15); do
  kk="$(printf '%02x' "$i")"
  f="$NETVM_LINK_DIR/70-katmate-slot-$kk.link"
  [[ -f "$f" ]] || die "build gate: slot $kk: $f missing"
  [[ "$(netvm_link_body "$f")" == $'[Match]\nMACAddress=52:54:01:00:00:'"$kk"$'\n[Link]\nName=km'"$kk" ]] \
    || die "build gate: slot $kk: $f does not carry exactly MACAddress=52:54:01:00:00:$kk and Name=km$kk"
  pair="iifname \"km$kk\" ip saddr 10.100.1.$((16 + i)) return"
  n="$(grep -cxF -- "$pair" <<< "$NETVM_GUARD" || true)"
  [[ "$n" == 1 ]] \
    || die "build gate: slot $kk: slot_guard in /etc/nftables.conf carries '$pair' $n times, expected once (ADR-037 R48)"
done
# Every `return` in the chain, quoted strings removed first so a comment or an
# interface name cannot supply or hide one. Sixteen, and each is a pair above.
# (sed, not ${var//}: a glob "*" would run from the first quote to the last.)
# shellcheck disable=SC2001
NETVM_GUARD_RETURNS="$(sed -e 's/"[^"]*"//g' <<< "$NETVM_GUARD" | { grep -ow return || true; } | wc -l)"
[[ "$NETVM_GUARD_RETURNS" -eq 16 ]] \
  || die "build gate: slot_guard in /etc/nftables.conf carries $NETVM_GUARD_RETURNS returns, expected exactly the 16 slot pairs (ADR-037 R48)"
log "Build gate OK: slot_guard carries 16 slot pairs, km00..km0f <-> 10.100.1.16..31, and no other return"

# The same sixteen slots as the BAKED ruleset marks them (ADR-035 §6; R107,
# R116; read-back ruled by R110, on R48's model above). NETCFG REMOVE flushes
# slot k's conntrack entries by mark k+1, so a wrong or missing pair here would
# flush another slot's flows or none, with nothing reporting it. Chain
# slot_mark must be a prerouting base chain and carry exactly one
# `iifname "kmkk" ct state new ct mark set (k+1)` per slot, and no other mark.
NETVM_MARK_CHAINS="$(grep -cE '^[[:space:]]*chain[[:space:]]+slot_mark[[:space:]]*\{' -- "$NETVM_NFT" || true)"
[[ "$NETVM_MARK_CHAINS" == 1 ]] \
  || die "build gate: /etc/nftables.conf carries $NETVM_MARK_CHAINS 'chain slot_mark {' lines, expected 1 (R116)"
NETVM_MARK="$(awk '/^[[:space:]]*chain[[:space:]]+slot_mark[[:space:]]*\{/ {g=1; next}
                   g && /^[[:space:]]*\}/ {exit}
                   g' "$NETVM_NFT" \
              | sed -e 's/#.*//' -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//')"
n="$(grep -cxF -- 'type filter hook prerouting priority filter;' <<< "$NETVM_MARK" || true)"
[[ "$n" == 1 ]] \
  || die "build gate: slot_mark in /etc/nftables.conf is not a 'type filter hook prerouting priority filter;' chain (found $n such lines, expected 1; R116)"
for i in $(seq 0 15); do
  kk="$(printf '%02x' "$i")"
  pair="iifname \"km$kk\" ct state new ct mark set $((i + 1))"
  n="$(grep -cxF -- "$pair" <<< "$NETVM_MARK" || true)"
  [[ "$n" == 1 ]] \
    || die "build gate: slot $kk: slot_mark in /etc/nftables.conf carries '$pair' $n times, expected once (R107, R110)"
done
# Every `mark set` in the chain, quoted strings removed first (as for the
# returns above). Sixteen, and each is a pair above.
# shellcheck disable=SC2001
NETVM_MARK_SETS="$(sed -e 's/"[^"]*"//g' <<< "$NETVM_MARK" | { grep -o 'mark set' || true; } | wc -l)"
[[ "$NETVM_MARK_SETS" -eq 16 ]] \
  || die "build gate: slot_mark in /etc/nftables.conf carries $NETVM_MARK_SETS 'mark set' statements, expected exactly the 16 slot pairs (R107, R110)"
log "Build gate OK: slot_mark is a prerouting chain carrying 16 slot pairs, km00..km0f -> ct mark 1..16, and no other mark"

# The ARP half of finding 12 (open problem #34; R100, read-back R110): the
# BAKED file's `table arp filter` must hold one input chain slot_arp with one
# `iifname "kmkk" arp saddr ip 10.100.1.(16+k) accept` per slot, no other
# accept, and exactly one `iifname "km*" counter drop` after them. The table
# block is the lines after `table arp filter {` up to the first line that
# begins with `}`; the chain inside it closes indented, so that line is the
# table's own close.
NETVM_ARP_TABLES="$(grep -cE '^[[:space:]]*table[[:space:]]+arp[[:space:]]' -- "$NETVM_NFT" || true)"
[[ "$NETVM_ARP_TABLES" == 1 ]] \
  || die "build gate: /etc/nftables.conf carries $NETVM_ARP_TABLES 'table arp' lines, expected 1 (R100)"
grep -qE '^table[[:space:]]+arp[[:space:]]+filter[[:space:]]*\{' -- "$NETVM_NFT" \
  || die "build gate: /etc/nftables.conf's arp table is not 'table arp filter {' at the start of a line (R100)"
NETVM_ARP="$(awk '/^table[[:space:]]+arp[[:space:]]+filter[[:space:]]*\{/ {g=1; next}
                  g && /^\}/ {exit}
                  g' "$NETVM_NFT" \
             | sed -e 's/#.*//' -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//')"
for want in 'chain slot_arp {' 'type filter hook input priority filter;' 'policy accept;'; do
  n="$(grep -cxF -- "$want" <<< "$NETVM_ARP" || true)"
  [[ "$n" == 1 ]] \
    || die "build gate: table arp filter carries '$want' $n times, expected once (R100)"
done
for i in $(seq 0 15); do
  kk="$(printf '%02x' "$i")"
  pair="iifname \"km$kk\" arp saddr ip 10.100.1.$((16 + i)) accept"
  n="$(grep -cxF -- "$pair" <<< "$NETVM_ARP" || true)"
  [[ "$n" == 1 ]] \
    || die "build gate: slot $kk: table arp filter carries '$pair' $n times, expected once (R100, R110)"
done
# (No '#' in the rule's comment string: the extraction above strips '#' to end
# of line as a file comment.)
NETVM_ARP_DROP='iifname "km*" counter drop comment "ARP on a slot claiming another address (R100)"'
n="$(grep -cxF -- "$NETVM_ARP_DROP" <<< "$NETVM_ARP" || true)"
[[ "$n" == 1 ]] \
  || die "build gate: table arp filter carries the km* drop $n times, expected once (R100, R110)"
# The drop comes after every pair: the last accept precedes it.
NETVM_ARP_LAST_ACCEPT="$(grep -nw accept <<< "$NETVM_ARP" | tail -n1 | cut -d: -f1)"
NETVM_ARP_DROP_LINE="$(grep -nxF -- "$NETVM_ARP_DROP" <<< "$NETVM_ARP" | cut -d: -f1)"
(( NETVM_ARP_LAST_ACCEPT < NETVM_ARP_DROP_LINE )) \
  || die "build gate: table arp filter's km* drop precedes a slot pair; every pair must come first (R100)"
# Every accept and every drop in the table's rules, quoted strings removed
# first; the policy line, checked once above, is not a rule.
NETVM_ARP_RULES="$(grep -vxF 'policy accept;' <<< "$NETVM_ARP" | sed -e 's/"[^"]*"//g')"
NETVM_ARP_ACCEPTS="$({ grep -ow accept <<< "$NETVM_ARP_RULES" || true; } | wc -l)"
NETVM_ARP_DROPS="$({ grep -ow drop <<< "$NETVM_ARP_RULES" || true; } | wc -l)"
[[ "$NETVM_ARP_ACCEPTS" -eq 16 && "$NETVM_ARP_DROPS" -eq 1 ]] \
  || die "build gate: table arp filter carries $NETVM_ARP_ACCEPTS accepts and $NETVM_ARP_DROPS drops, expected exactly the 16 slot pairs and the one km* drop (R100, R110)"
log "Build gate OK: table arp filter carries 16 slot pairs, km00..km0f <-> arp saddr 10.100.1.16..31, then one counted km* drop"
f="$NETVM_LINK_DIR/60-katmate-uplink.link"
[[ -f "$f" ]] || die "build gate: uplink: $f missing"
[[ "$(netvm_link_body "$f")" == $'[Match]\nPath=pci-'"$NETVM_UPLINK_PCI_ADDR"$'\n[Link]\nName=uplink0' ]] \
  || die "build gate: uplink: $f does not carry exactly Path=pci-$NETVM_UPLINK_PCI_ADDR and Name=uplink0"
log "Build gate OK: 17 katmate .link files — 16 slots, and the uplink on pci-$NETVM_UPLINK_PCI_ADDR"

# --- 5b. clean apt state (same hygiene as app-layer.sh) -----------------------
log "Cleaning apt state inside image"
chroot_run "$NETVM_MNT" apt-get clean
rm -f "$NETVM_MNT/etc/resolv.conf"                        # build-time DNS only
# ...and in its place an EMPTY root:root 0644 file (ruling R29). dhcpcd.service
# runs ProtectSystem=strict with ReadWritePaths=/etc/resolv.conf: /etc is
# read-only to it, so its hook can rewrite this file in place but cannot create
# it. Empty, not absent; and never a nameserver line baked at build time.
install -m 0644 -o 0 -g 0 /dev/null "$NETVM_MNT/etc/resolv.conf"
[[ "$(stat -c '%u:%g %a %s' "$NETVM_MNT/etc/resolv.conf")" == "0:0 644 0" ]] \
  || die "resolv.conf read-back: expected an empty root:root 0644 file, found: $(stat -c '%u:%g %a %s' "$NETVM_MNT/etc/resolv.conf")"
rm -rf "$NETVM_MNT"/var/lib/apt/lists/* 2>/dev/null || true

# --- 6. root account: LOCKED by default; the dev unlock is opt-in -------------
# The image ships with root locked. That is the release state, it is the
# default, and it costs the build nothing to reach: no variable is consulted to
# get there. An unlock has to be asked for.
#
# A dev build unlocks root for console observation by passing a password HASH
# in KATMATE_DEV_ROOT_HASH. A hash and never a plaintext: this script runs as
# root, and a plaintext handed to it would reach the process table, the
# invoking shell's history and every `ps` on the build host. Produce one with
#
#     openssl passwd -6            # prompts, prints $<id>$<salt>$<body>
#
# and pass it in the environment for that one build. NOTHING about the value
# lives in this repository — no default, no fallback, no example that happens
# to be a working hash.
#
# WHY THIS REPLACED A LITERAL: until this commit this step carried a tracked,
# signed and pushed $6$katmate$... string, applied unconditionally. Two things
# were wrong with it at once. It unlocked root in the most network-exposed VM
# in the system on EVERY build, release builds included, because there was no
# way to ask for a locked one. And it matched no password anyone held (open
# problem #12), so the unlock bought nothing it cost. The second fact is what
# let it survive four months of review: a credential that does not work looks
# harmless. It is not. A credential in git is the defect whether or not it
# works, and the shared-secret failure would have arrived the day someone
# made it work.
#
# The value is VALIDATED before it is baked. An unusable hash is precisely the
# defect being removed, arriving by another route, and it fails silently — the
# account looks unlocked and no password opens it. So a malformed value stops
# the build instead.
#
# usermod, not chpasswd: `usermod -p` takes the hash directly, which is the
# whole reason for carrying a hash rather than a plaintext.
#
# `|| true` on the lock below is retained, and the READ-BACK at 6b is what
# makes it safe: the exit status of passwd -l is not the evidence that root is
# locked — /etc/shadow is. (Whether passwd -l returns non-zero on an ALREADY
# locked account is not measured here: a fresh debootstrap root is not yet
# locked, so this script never takes that path. With 6b in place it does not
# need to be.)
#
# It is invoked by ABSOLUTE PATH, and that is required rather than tidy:
# chroot_run (build/lib.sh) sets no PATH of its own — it runs
# `chroot <mnt> /usr/bin/env DEBIAN_FRONTEND=noninteractive "$@"` — so the
# chroot inherits the build host's PATH, which does not carry /usr/sbin, where
# the Debian image keeps usermod. Measured 2026-07-23. A bare `usermod` here
# fails with "command not found" and the account silently stays locked.
log "Locking root account (release-safe default)"
chroot_run "$NETVM_MNT" passwd -l root || true

# Recorded in the host-side netvm.meta at step 11, so the image says what it is
# rather than being remembered.
NETVM_ROOT_UNLOCKED=no

if [[ -n "${KATMATE_DEV_ROOT_HASH:-}" ]]; then
  # crypt(3) shape: $<id>$[params$]<salt>$<body>. Narrow on the parts that
  # corrupt /etc/shadow or silently produce an unopenable account — an empty
  # field, whitespace, or the ':' that is shadow's own field separator — and
  # deliberately not narrow on the scheme, so a yescrypt hash from mkpasswd(1)
  # is accepted beside the sha512crypt one openssl prints.
  [[ "$KATMATE_DEV_ROOT_HASH" =~ ^\$(6|5|y|7|gy|2a|2b|2y)\$[^:[:space:]]+\$[^:[:space:]]+$ ]] \
    || die "KATMATE_DEV_ROOT_HASH is not a well-formed crypt(3) hash: expected \$<id>\$<salt>\$<body> as produced by \`openssl passwd -6\`. Refusing to bake it — an unusable hash leaves root looking unlocked with no password that opens it. (Pass a HASH, never a plaintext password.)"
  log "DEV: unlocking root from KATMATE_DEV_ROOT_HASH — this image is NOT release-clean"
  chroot_run "$NETVM_MNT" /usr/sbin/usermod -p "$KATMATE_DEV_ROOT_HASH" root
  NETVM_ROOT_UNLOCKED=yes
else
  log "root stays LOCKED (KATMATE_DEV_ROOT_HASH unset)"
fi

# --- 6b. read back what step 6 published --------------------------------------
# The branch above ends with ONE security action on the release path,
# `passwd -l root || true`, whose `|| true` says its failure does not count. A
# failed lock would therefore produce a successful build, a log line reading
# "release-safe default", and NETVM_ROOT_UNLOCKED=no in the meta, with nothing
# in the image disagreeing — the same silent-wrong-state class the validator
# above exists to prevent, on the branch that is not validated.
#
# So the OUTCOME is verified rather than the command trusted. This is
# katmate-generate-env's idiom (ADR-030 §8): it reads back what it published
# before it exits, so that no exit path leaves a claim the artefact does not
# support. Here the artefact is /etc/shadow and the claim is the meta key.
#
# Only the '!' lock marker or the crypt id is ever printed. A hash body never
# reaches the log, and a failure message carries no field content at all.
[[ -r "$NETVM_MNT/etc/shadow" ]] \
  || die "$NETVM_MNT/etc/shadow is missing or unreadable — step 6's outcome cannot be confirmed"
NETVM_SHADOW_PW="$(awk -F: '$1=="root"{print $2; found=1} END{exit !found}' \
                   "$NETVM_MNT/etc/shadow")" \
  || die "no root line in $NETVM_MNT/etc/shadow — step 6's outcome cannot be confirmed"

case "$NETVM_ROOT_UNLOCKED" in
  no)
    # passwd -l prepends '!' to whatever was there. Absent marker = not locked,
    # whatever passwd reported.
    [[ "$NETVM_SHADOW_PW" == '!'* ]] \
      || die "step 6 locked root and /etc/shadow disagrees: the root password field does not begin with the '!' lock marker. Refusing to build an image whose netvm.meta would claim NETVM_ROOT_UNLOCKED=no."
    log "Read-back OK: root LOCKED ('!' marker present in /etc/shadow)"
    ;;
  yes)
    [[ "$NETVM_SHADOW_PW" == "$KATMATE_DEV_ROOT_HASH" ]] \
      || die "step 6 applied KATMATE_DEV_ROOT_HASH and /etc/shadow does not carry it: the root password field differs from the value supplied. Refusing to build an image whose netvm.meta would claim NETVM_ROOT_UNLOCKED=yes."
    log "Read-back OK: root UNLOCKED from the supplied hash (crypt id \$$(printf '%s' "$NETVM_SHADOW_PW" | cut -d'$' -f2)\$)"
    ;;
  *)
    die "internal: NETVM_ROOT_UNLOCKED is '$NETVM_ROOT_UNLOCKED', expected yes or no"
    ;;
esac

# --- 7. netvm-agent: bake binary, enable the unit ------------------------------
# The privileged control agent (NETCFG/PING/SHUTDOWN) runs under systemd with
# CAP_NET_ADMIN. The binary comes from the agent Cargo workspace. The preflight
# has already refused a missing or stale one (R120); an image without its
# control agent is no longer a build outcome.
log "Baking netvm-agent + systemd unit"
install -D -m 0755 "$NETVM_AGENT_BIN" "$NETVM_MNT/usr/local/bin/netvm-agent"
# The unit has one author: manifests/netvm.conf.d/etc/systemd/system/
# netvm-agent.service, baked in step 5 (open problem #27, ruling R24). This
# step used to carry a second copy as a heredoc, written only when the conf
# tree supplied none. Missing here means the conf tree is wrong, not that a
# fallback is due.
[[ -f "$NETVM_MNT/etc/systemd/system/netvm-agent.service" ]] \
  || die "netvm-agent.service missing from the image: step 5 should have baked it from $NETVM_CONFD"
chroot_run "$NETVM_MNT" systemctl enable netvm-agent

# --- 8. export kernel + initrd host-side (no in-guest bootloader) -------------
# linux-image-amd64's postinst already generated the initramfs in /boot with the
# full virtio + common-storage module set (MODULES=most was pre-seeded before the
# install). We therefore only
# COPY vmlinuz + initrd out to the host-side artifact dir — NO regeneration here
# (that avoided the fragile /boot re-write that kept leaving a stuck jbd2). The
# launcher (net-vfio.con) passes these via -kernel/-initrd; nothing in the guest
# boots them (no GRUB, no /boot partition).

log "Exporting vmlinuz + initrd to $NETVM_OUT"
mkdir -p "$NETVM_OUT"
KVER="$(chroot "$NETVM_MNT" sh -c 'ls -1 /boot/vmlinuz-* 2>/dev/null | sed s#/boot/vmlinuz-##' | head -n1)"
[[ -n "$KVER" ]] || die "no vmlinuz found in image /boot"
[[ -f "$NETVM_MNT/boot/initrd.img-$KVER" ]] || die "no initrd.img-$KVER in image /boot (kernel postinst did not generate it)"
cp -v "$NETVM_MNT/boot/vmlinuz-$KVER"    "$NETVM_OUT/vmlinuz"
cp -v "$NETVM_MNT/boot/initrd.img-$KVER" "$NETVM_OUT/initrd.img"
echo "$KVER" > "$NETVM_OUT/kernel.version"

# --- 9. netvm.meta, IN-GUEST copy (secondary; for netvm-update) ---------------
# Flat KEY=value, POSIX-sourceable. NO secrets.
#
# WHICH IS WHICH (read this before adding a consumer):
#   * THIS copy lives inside the guest filesystem. It is reachable only by
#     mounting the image, which the launch path must never do. Kept for
#     netvm-update (ADR-021's separate update track), which operates ON the
#     image and therefore already has it mounted.
#   * The AUTHORITATIVE copy for anything host-side — every unit, every T4
#     preflight, the projection generator — is written in step 11 to
#     $NETVM_RUNTIME_DIR/netvm.meta. It carries strictly more keys.
# Until step 11 existed there was only this one, in the one place no launcher
# could read it (ADR-032 context, finding 5).
NETVM_BUILT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # one timestamp, both copies
log "Writing in-guest netvm.meta (secondary copy — see comment)"
mkdir -p "$NETVM_MNT/var/lib/katmate"
cat > "$NETVM_MNT/var/lib/katmate/netvm.meta" <<META
NETVM_SUITE=$DEBIAN_SUITE
NETVM_ARCH=$ARCH
NETVM_KERNEL_VERSION=$KVER
NETVM_BUILT=$NETVM_BUILT
META

# --- 10. teardown -------------------------------------------------------------
log "Unmounting"
netvm_umount || log "WARNING: image built, but umount left the LV busy — see above"

# Disarm the rollback HERE, not at the end of the script. Everything below is
# host-side and the image is already complete: a failure from this point must
# die loudly (set -e) and leave a valid netVM LV behind, NOT trigger
# netvm_cleanup's `lvremove -f $DEV`. This is foundation.sh's ordering (its
# step 10 comment gives the same reasoning) and it is the reason step 11 can
# exist at all. Moving this line UP is the whole safety property; do not sink
# it back to the bottom of the file.
trap - EXIT

# --- 11. install host-side payload + metadata (ADR-032 §5) --------------------
# T2 lives at $NETVM_RUNTIME_DIR: vmlinuz, initrd.img and netvm.meta together,
# because payload and its metadata share an author (this script), a lifecycle
# (replaced wholesale on rebuild) and an upgrade owner (the pipeline, never the
# user and never the release).
#
# $NETVM_OUT keeps its copy and stays a BUILD tree. Nothing at runtime reads it.
#
# On the kernel version appearing twice: $NETVM_OUT/kernel.version and the meta
# key NETVM_KERNEL_VERSION have BOTH existed since this script was written, ten
# lines apart. The split of roles, stated rather than left to be rediscovered:
# kernel.version is a build-tree convenience beside the build-tree payload;
# NETVM_KERNEL_VERSION in the meta below is what a unit reads. One is not a new
# duplicate of the other.
log "Installing host-side payload + metadata -> $NETVM_RUNTIME_DIR"
install -d -m0755 "$NETVM_RUNTIME_DIR"

# Copy-then-rename, same filesystem: a reader never sees a truncated kernel.
for f in vmlinuz initrd.img; do
  cp -- "$NETVM_OUT/$f" "$NETVM_RUNTIME_DIR/.$f.new"
  chmod 0644 "$NETVM_RUNTIME_DIR/.$f.new"
  mv -f -- "$NETVM_RUNTIME_DIR/.$f.new" "$NETVM_RUNTIME_DIR/$f"
done

# Flat KEY=value, POSIX-sourceable, no parser needed — the foundation.meta
# format (ADR-030 T2: "no second format is introduced"). NO secrets.
#
# Beyond the four descriptive keys of the in-guest copy, a unit needs to reach
# QEMU without guessing. Two of these describe DIFFERENT sides of one disk and
# are deliberately both present:
#   NETVM_LV          host side  — the backing block device to attach
#   NETVM_ROOT_DEVICE guest side — what the kernel is told in -append root=
# NETVM_ROOTFSTYPE exists because ADR-030 makes `rootfstype` in -append legal
# only if <image>.meta records it. It is ext4 by mkfs.ext4 in step 1, and the
# root device has no partition table (debootstrap writes straight to the LV),
# hence /dev/vda and never /dev/vda1.
#
# NETVM_ROOT_UNLOCKED records step 6's outcome, yes|no, in the vocabulary the
# ADR-034 provenance sidecar already uses for a two-state fact. A dev image and
# a release image are otherwise indistinguishable without mounting the LV and
# reading /etc/shadow, which the launch path must never do; with this key the
# difference is one grep against a file a unit already reads. It is a
# DESCRIPTION and never an instruction: nothing consults it to decide anything
# yet, and a reader that ignores it is unaffected.
#
# UPLINK_PCI_ADDR (ADR-037 R13) is the guest PCI address the image's
# 60-katmate-uplink.link matches, from build/config.sh NETVM_UPLINK_PCI_ADDR,
# the value the step-5a gate checked. The unit pins the same address as
# addr=0x4; the preflight comparing the two is open problem #44, and until it
# exists nothing reads this key.
#
# Added at KATMATE_META_VERSION=1, unchanged. km_meta_open() in
# host/usr/lib/katmate/katmate-lib.sh refuses any version but 1, and readers
# take keys individually with km_meta_get/km_meta_require, so an added key is
# invisible to a reader that does not ask for it while a BUMP would break every
# shipped T4 executable. ADR-034 set the precedent from the other direction:
# KERNEL_PROVENANCE joined foundation.meta on 2026-09-01 with the version line
# beside it left at 1 (build/foundation.sh:246).
NETVM_META="$NETVM_RUNTIME_DIR/netvm.meta"
META_TMP="$(mktemp "$NETVM_RUNTIME_DIR/.netvm.meta.XXXXXX")"
cat >"$META_TMP" <<META
KATMATE_META_VERSION=1
NETVM_SUITE=$DEBIAN_SUITE
NETVM_ARCH=$ARCH
NETVM_KERNEL_VERSION=$KVER
NETVM_BUILT=$NETVM_BUILT
NETVM_LV=$VG/$NETVM_LV
NETVM_ROOT_DEVICE=/dev/vda
NETVM_ROOTFSTYPE=ext4
NETVM_KERNEL=$NETVM_RUNTIME_DIR/vmlinuz
NETVM_INITRD=$NETVM_RUNTIME_DIR/initrd.img
NETVM_ROOT_UNLOCKED=$NETVM_ROOT_UNLOCKED
UPLINK_PCI_ADDR=$NETVM_UPLINK_PCI_ADDR
META
chmod 0644 "$META_TMP"
mv -f -- "$META_TMP" "$NETVM_META"   # atomic: mktemp created it on the same fs

log "netVM image built: $DEV (linear, RW, NOT frozen)"
log "  runtime payload + meta: $NETVM_RUNTIME_DIR (KVER=$KVER)  <- units read this"
log "  build-tree export:      $NETVM_OUT"
log "  Per-installation config (static address, VPN) is T1 and never baked (ADR-037 R7, R8, R20)."

exit 0
