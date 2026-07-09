#!/usr/bin/env bash
# Katmate OS — netVM sysVM build (ADR-021)
#
# netVM is a DISTINCT COMPONENT CLASS (sysVM), not the foundation and not an
# app-layer. It does NOT share the foundation, carries full systemd (networkd,
# wg, DHCP), boots q35 with a passed-through NIC (vfio), holds its own PRIVILEGED
# control agent (netvm-agent), and updates on its own track (netvm-update),
# never via katmate-update. See ADR-021.
#
# Divergences from foundation.sh (deliberate, per ADR-021 / ADR-018):
#   - STANDALONE LINEAR RW LV, not thin and not in a snapshot chain (netVM is
#     nobody's backing store) -> no -K -ay skip-activation, no RO-freeze.
#   - NOT frozen: runtime-mutable state (/var, leases, wg handshake, resolv.conf,
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
# Secrets (WireGuard keys, per-install values) are NOT baked here. The manifest
# installs only a wg CONFIG TEMPLATE with placeholders; concrete values are
# written at provisioning time (ADR-021 image/state separation).
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
NETVM_OUT="${NETVM_OUT:-$OUT/netvm}"          # host-side kernel+initrd export
GUEST_KERNEL_PKG="${GUEST_KERNEL_PKG:-linux-image-${ARCH}}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
SECURITY_MIRROR="${SECURITY_MIRROR:-http://security.debian.org/debian-security}"

# netvm-agent binary (produced by the agent Cargo workspace, ADR-021). May not
# exist yet — the agent workspace split is a separate step. If absent, the build
# still completes and prints a clear notice; the image simply lacks its control
# agent until the binary is provided.
NETVM_AGENT_BIN="${NETVM_AGENT_BIN:-$OUT/netvm-agent}"

DEV="/dev/$VG/$NETVM_LV"

# --- own cleanup / rollback (linear LV; not lib.sh's thin model) --------------
# On any failure mid-write (e.g. a bad chroot call during initramfs/boot
# writes), the ext4 journal can stay busy if we umount while it is still hot.
# So: sync + settle BEFORE umount, then deactivate explicitly, and if the LV is
# still busy, say so LOUDLY with the exact manual command rather than silently
# leaving a stuck LV behind (which previously masqueraded as a successful
# rollback and forced a host reboot).
NETVM_LV_CREATED=""
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
# Default variant pulls systemd/init: netVM needs networkd, the opposite of
# foundation.sh --variant=minbase.
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
printf 'MODULES=most\n' > \
  "$NETVM_MNT/etc/initramfs-tools/conf.d/modules-most"

log "Installing netVM package manifest"
mapfile -t PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$NETVM_PKGS")
[[ ${#PKGS[@]} -gt 0 ]] || die "Manifest $NETVM_PKGS lists no packages"
log "Install manifest: ${PKGS[*]}"
cp /etc/resolv.conf "$NETVM_MNT/etc/resolv.conf"   # build-time DNS only
chroot_run "$NETVM_MNT" apt-get update
chroot_run "$NETVM_MNT" apt-get install -y --no-install-recommends "${PKGS[@]}"

# --- 5. bake config tree (declarative; closes the netinst drift class) --------
# Everything under conf.d/ is copied verbatim into the image. This is the ONLY
# author of netVM configuration — no installer, no drift. The tree is
# appVM-AGNOSTIC: it bakes the uplink, firewall policy, wg template, sysctl —
# and NO internal /32 route (not even personalVM). All internal routes arrive
# at launch via the agent's NETCFG (ADR-021).
log "Baking netVM config tree from $NETVM_CONFD"
cp -a "$NETVM_CONFD/." "$NETVM_MNT/"

log "Enabling systemd services (networkd, nftables)"
chroot_run "$NETVM_MNT" systemctl enable systemd-networkd
chroot_run "$NETVM_MNT" systemctl enable nftables
# systemd-resolved deliberately NOT enabled — DNS-leak policy is an OPEN
# decision (ADR-021); resolve it in the conf tree, not by silently enabling
# resolved here.
# networking.service (ifupdown) stays present but inert: interfaces is reduced
# to lo+source in the conf tree, so it does nothing on the uplink. Not disabled.

# --- 5b. clean apt state (same hygiene as app-layer.sh) -----------------------
log "Cleaning apt state inside image"
chroot_run "$NETVM_MNT" apt-get clean
rm -f "$NETVM_MNT/etc/resolv.conf"                        # build-time DNS only
rm -rf "$NETVM_MNT"/var/lib/apt/lists/* 2>/dev/null || true

# --- 6. root account: locked (release-safe; dev unlocks out-of-band) ----------
log "Locking root account (dev sets a console password out-of-band)"
chroot_run "$NETVM_MNT" passwd -l root || true

# --- 7. netvm-agent: bake binary + systemd unit -------------------------------
# The privileged control agent (NETCFG/PING/SHUTDOWN) runs under systemd with
# CAP_NET_ADMIN. The binary comes from the agent Cargo workspace (separate
# step). If it is not yet built, warn and continue — the image is otherwise
# complete and bootable; it just lacks host control until the binary lands.
if [[ -f "$NETVM_AGENT_BIN" ]]; then
  log "Baking netvm-agent + systemd unit"
  install -D -m 0755 "$NETVM_AGENT_BIN" "$NETVM_MNT/usr/local/bin/netvm-agent"
  # Unit is baked from the conf tree if present, else written here as the
  # canonical minimal unit. CAP_NET_ADMIN only; no full root.
  if [[ ! -f "$NETVM_MNT/etc/systemd/system/netvm-agent.service" ]]; then
    cat > "$NETVM_MNT/etc/systemd/system/netvm-agent.service" <<'UNIT'
[Unit]
Description=KatMate netVM control agent (NETCFG/PING/SHUTDOWN over vsock)
After=systemd-networkd.service
Wants=systemd-networkd.service

[Service]
ExecStart=/usr/local/bin/netvm-agent
# Minimum privilege for writing /etc/systemd/network/ + networkctl reload + nft.
AmbientCapabilities=CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/etc/systemd/network /run
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  fi
  chroot_run "$NETVM_MNT" systemctl enable netvm-agent
else
  log "NOTICE: netvm-agent binary not found at $NETVM_AGENT_BIN"
  log "        Image built WITHOUT its control agent. Provide the binary"
  log "        (agent workspace, ADR-021) and re-run, or bake it separately."
fi

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

log "Exporting vmlinuz + initrd to $NETVM_OUT"
mkdir -p "$NETVM_OUT"
KVER="$(chroot "$NETVM_MNT" sh -c 'ls -1 /boot/vmlinuz-* 2>/dev/null | sed s#/boot/vmlinuz-##' | head -n1)"
[[ -n "$KVER" ]] || die "no vmlinuz found in image /boot"
cp -v "$NETVM_MNT/boot/vmlinuz-$KVER"    "$NETVM_OUT/vmlinuz"
cp -v "$NETVM_MNT/boot/initrd.img-$KVER" "$NETVM_OUT/initrd.img"
echo "$KVER" > "$NETVM_OUT/kernel.version"

# --- 9. netvm.meta (parallel to foundation.meta; for netvm-update) ------------
# Flat KEY=value, POSIX-sourceable. NO secrets.
log "Writing netvm.meta"
mkdir -p "$NETVM_MNT/var/lib/katmate"
cat > "$NETVM_MNT/var/lib/katmate/netvm.meta" <<META
NETVM_SUITE=$DEBIAN_SUITE
NETVM_ARCH=$ARCH
NETVM_KERNEL_VERSION=$KVER
NETVM_BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

# --- 10. teardown -------------------------------------------------------------
log "Unmounting"
umount_root

log "netVM image built: $DEV (linear, RW, NOT frozen)"
log "  kernel+initrd exported: $NETVM_OUT (KVER=$KVER)"
log "  Provision secrets (wg keys) at deploy time; do not bake into the image."

trap - EXIT
exit 0
