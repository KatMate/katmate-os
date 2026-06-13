#!/usr/bin/env bash
# Katmate OS — foundation image builder (ADR-007, ADR-011)
# Produces out/foundation.qcow2 : OS + custom MicroVM kernel + waypipe + vm-agent.
# Shared, read-only, version-locked. App layers back onto this (ADR-014).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib.sh"

require_root

IMG="$OUT/foundation.qcow2"
MNT="$(mktemp -d)"
trap 'cleanup; rmdir "$MNT" 2>/dev/null || true' EXIT

mkdir -p "$OUT"

# --- preflight: external artifacts (hooks) -----------------------------------
[[ -f "$KERNEL_DEB" ]]   || die "Missing kernel package: $KERNEL_DEB
  Build the MicroVM kernel (Debian LTS sources + katmate-microvm config, ADR-005)
  and place the linux-image .deb at that path. (kernel sub-pipeline = separate TODO)"
[[ -f "$VM_AGENT_BIN" ]] || die "Missing vm-agent binary: $VM_AGENT_BIN
  Build ../vm-agent (C) and copy the binary here, e.g.:
    gcc -O2 -Wall -o $OUT/vm-agent ../vm-agent/vm-agent.c"

# --- 1. create + format (bare ext4, whole device — direct kernel boot) -------
log "Create qcow2 ($FOUNDATION_SIZE)"
rm -f "$IMG"
qemu-img create -f qcow2 "$IMG" "$FOUNDATION_SIZE"

log "Attach + format (bare ext4, no partition table)"
nbd_connect "$IMG"
mkfs.ext4 -q -L katmate-root "$NBD"
mount_root "$MNT"

# --- 2. debootstrap (snapshot-pinned) ----------------------------------------
log "debootstrap $DEBIAN_SUITE @ $SNAPSHOT"
debootstrap --arch="$ARCH" --variant=minbase "$DEBIAN_SUITE" "$MNT" "$MIRROR"

log "Pin apt to snapshot"
cat >"$MNT/etc/apt/sources.list" <<EOF
deb $MIRROR $DEBIAN_SUITE main
deb $SECURITY_MIRROR ${DEBIAN_SUITE}-security main
EOF
# snapshot Release files are past Valid-Until by design → must disable the check
cat >"$MNT/etc/apt/apt.conf.d/10katmate" <<'EOF'
Acquire::Check-Valid-Until "false";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

cp /etc/resolv.conf "$MNT/etc/resolv.conf"   # build-time DNS only; removed before finalize

# --- 3. base userspace (minimal; tune per measurement) -----------------------
# Rationale: init + dbus (GUI apps) + waypipe runtime libs + fonts (the guest
# app renders into buffers locally) + net config (via NetVM, ADR-009) + TLS.
log "Base userspace"
chroot_run "$MNT" apt-get update
chroot_run "$MNT" apt-get install -y \
  systemd systemd-sysv udev \
  dbus-user-session \
  iproute2 nftables \
  ca-certificates \
  fontconfig fonts-dejavu-core \
  libgbm1 libwayland-client0 liblz4-1 libzstd1

# --- 4. custom MicroVM kernel ------------------------------------------------
log "Custom MicroVM kernel"
cp "$KERNEL_DEB" "$MNT/tmp/kernel.deb"
chroot_run "$MNT" dpkg -i /tmp/kernel.deb
rm -f "$MNT/tmp/kernel.deb"

# --- 5. waypipe from source, version-locked (ADR-008) ------------------------
# Build deps are installed, used, then PURGED — they must not ship in the
# foundation (minimal TCB). Runtime libs (installed in step 3) remain.
log "waypipe $WAYPIPE_VERSION (source build, then purge build deps)"
WP_BUILD_DEPS="meson ninja-build pkg-config git cargo bindgen \
               libwayland-dev liblz4-dev libzstd-dev libgbm-dev"
chroot_run "$MNT" apt-get install -y $WP_BUILD_DEPS
chroot_run "$MNT" bash -eu -c "
  cd /tmp
  git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git
  cd waypipe
  git checkout $WAYPIPE_VERSION
  cargo fetch --manifest-path Cargo.toml   # build wrapper passes --frozen
  meson setup build
  ninja -C build
  ninja -C build install
"
chroot_run "$MNT" apt-get purge -y $WP_BUILD_DEPS
chroot_run "$MNT" apt-get autoremove --purge -y
rm -rf "$MNT/tmp/waypipe" "$MNT/root/.cargo" 2>/dev/null || true

# --- 6. vm-agent (host-trusted AF_VSOCK command channel) ---------------------
log "vm-agent"
install -Dm755 "$VM_AGENT_BIN" "$MNT/usr/local/sbin/vm-agent"
cat >"$MNT/etc/systemd/system/vm-agent.service" <<'UNIT'
[Unit]
Description=Katmate vm-agent (AF_VSOCK command channel)
After=multi-user.target

[Service]
ExecStart=/usr/local/sbin/vm-agent
Restart=on-failure
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
UNIT
chroot_run "$MNT" systemctl enable vm-agent.service

# --- 7. finalize -------------------------------------------------------------
log "Cleanup"
chroot_run "$MNT" apt-get clean
rm -f "$MNT/etc/resolv.conf"
rm -rf "$MNT"/tmp/* "$MNT"/var/lib/apt/lists/* 2>/dev/null || true

log "Extract vmlinuz for host-side direct kernel boot"
cp "$MNT"/boot/vmlinuz-* "$OUT/vmlinuz-katmate-microvm" 2>/dev/null \
  || die "No vmlinuz in image /boot — check kernel package"
# NOTE: with virtio-blk + ext4 built into the kernel (=y) and root=/dev/vda,
# no initramfs is needed. If the kernel uses modules, extract initrd here too.

umount_root
nbd_disconnect
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

chmod 444 "$IMG"
log "foundation.qcow2 ready: $IMG"
