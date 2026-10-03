#!/usr/bin/env bash
# Katmate OS — foundation builder (ADR-007 shared base, ADR-008 waypipe pin,
# ADR-011 build/update, ADR-005 direct-kernel, LVM-thin per ADR-010 rev 2026-06)
#
# Builds the single shared RO-frozen thin base  vg0/vm_tpl_foundation  from
# scratch, then freezes it. App-layers (app-layer.sh) are thin SNAPSHOTS of
# this LV. This is build-order step 2.
#
#   lvcreate -T (thin) -> lvchange -K -ay -> mkfs.ext4 (bare, whole-device)
#   -> debootstrap trixie -> apt base -> custom kernel .deb
#   -> waypipe 0.11 from source (ADR-008), build deps PURGED before freeze
#   -> bake vm-agent + katmate-init (PID 1) -> bake user 1000
#   -> extract vmlinuz for host -kernel boot -> umount -> RO-freeze
#
# Two things that bit before, both encoded here:
#  * BARE ext4 on the whole device — debootstrap writes directly to the LV, so
#    the launcher uses root=/dev/vda (NOT vda1). No partition table, no ESP.
#  * katmate-init replaces /sbin/init (per init/katmate-init.c header:
#    "bake to /sbin/init; no init= cmdline needed"); it is PID 1 and the only
#    root process. systemd, systemd-sysv, dbus and dbus-daemon ARE installed —
#    dependency debt of the GUI runtime (step 3), accepted for the alpha — and
#    nothing starts them. dpkg's claim on /usr/sbin/init is diverted in step 6.
#
# Migrated from the pre-revision qcow2/nbd mechanism (old foundation.sh) to the
# LVM-thin mechanism, matching app-layer.sh (commit cff4880). The waypipe
# source-build + purge is carried over from the old script (ADR-008).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib.sh"

require_root

MNT="$(mktemp -d)"
trap 'cleanup; rmdir "$MNT" 2>/dev/null || true' EXIT

# Virtual size of the thin LV (thin-provisioned: only written extents consume
# pool space — a ceiling, not a reservation). Override: FOUNDATION_SIZE=... make foundation
FOUNDATION_SIZE="${FOUNDATION_SIZE:-8G}"

# ---- preflight: pool present, foundation absent, artifacts present ----------

lvs "$VG/$POOL" >/dev/null 2>&1 \
  || die "Missing thin pool $VG/$POOL (installer creates it; not built here)"

if lvs "$VG/$FOUNDATION_LV" >/dev/null 2>&1; then
  die "Foundation $VG/$FOUNDATION_LV already exists. Rebuild = drop first:
       sudo lvchange -an $VG/$FOUNDATION_LV && sudo lvremove -f $VG/$FOUNDATION_LV"
fi

[[ -f "$KERNEL_VMLINUZ" ]] || die "Missing kernel: $KERNEL_VMLINUZ
  Build the MicroVM kernel (Debian LTS sources + katmate-microvm config, ADR-005)
  and place the vmlinuz at that path, or: cp \$KERNEL_SRC_DIR/vmlinuz-... \$KERNEL_VMLINUZ
  (Makefile copies it from $KERNEL_SRC_DIR/. No .deb: the host boots it via -kernel.)"

# Provenance of THAT kernel, established before anything destructive happens
# (ADR-034 acceptance note § G). Returns absent|recorded on stdout; dies on a
# sidecar that describes a different kernel, or that exists and is malformed.
# `set -e` above is what makes the die reach this script — see lib.sh.
KERNEL_PROVENANCE="$(kernel_provenance_check "$KERNEL_VMLINUZ")"
log "Kernel provenance: $KERNEL_PROVENANCE ($KERNEL_VMLINUZ)"
[[ -f "$VM_AGENT_BIN" ]] || die "Missing vm-agent binary: $VM_AGENT_BIN
  Build the Rust vm-agent and copy it here (ADR-039):
    (cd agent && cargo build --release && cp target/release/vm-agent $VM_AGENT_BIN)"
[[ -f "$INIT_SRC" ]] || die "Missing init source: $INIT_SRC"

command -v debootstrap >/dev/null || die "debootstrap not installed on host"

# ---- 0. compile katmate-init (static ANSI C, no deps) -----------------------
# Pure static C, no NSS calls (uid 1000 hardcoded), so building it on the host
# is safe and reproducible. It becomes PID 1 — refuse a non-static binary.
log "Compile katmate-init (static) -> $INIT_BIN"
mkdir -p "$OUT"
"${CC:-gcc}" -static -O2 -Wall -Wextra -std=gnu11 -o "$INIT_BIN" "$INIT_SRC"
file "$INIT_BIN" | grep -q 'statically linked' \
  || die "katmate-init is not statically linked — refusing (it becomes PID 1)"

# ---- 1. create + activate + format the thin foundation LV -------------------

log "Create thin LV $FOUNDATION_LV (virtual $FOUNDATION_SIZE) in pool $POOL"
lv_thin_create "$FOUNDATION_LV" "$FOUNDATION_SIZE"

log "Activate $FOUNDATION_LV (-K -ay) + mkfs.ext4 (bare, whole-device)"
lv_activate "$FOUNDATION_LV"
mkfs.ext4 -q -L katmate-found "/dev/$VG/$FOUNDATION_LV"
# Mount ONLY the bare ext4 here. The pseudo-filesystems (/proc /sys /dev) are
# mounted AFTER debootstrap — on a fresh fs those mount points do not exist yet
# (debootstrap creates them). mount_root() in lib.sh does both at once, which is
# correct for app-layer.sh (it mounts an already-debootstrapped snapshot) but
# wrong for a from-scratch foundation, so we stage the mounts manually here.
mount "/dev/$VG/$FOUNDATION_LV" "$MNT"
MOUNTED="$MNT"               # arm cleanup's umount_root

# ---- 2. debootstrap trixie --------------------------------------------------
# ADR-011 build note: SNAPSHOT pin is DEFERRED — plain trixie against current
# packages; the RO-frozen LV is itself the effective pin. (No snapshot mirror,
# so no Acquire::Check-Valid-Until override is needed.)
log "debootstrap $DEBIAN_SUITE ($ARCH)"
debootstrap --arch="$ARCH" --variant=minbase "$DEBIAN_SUITE" "$MNT"

# Now the rootfs has /proc /sys /dev — mount the pseudo-filesystems for chroot.
log "Mount pseudo-filesystems for chroot"
mount -t proc  proc "$MNT/proc"
mount -t sysfs sys  "$MNT/sys"
mount --rbind  /dev "$MNT/dev"
mount --make-rslave "$MNT/dev"

cat >"$MNT/etc/apt/sources.list" <<EOF
deb http://deb.debian.org/debian $DEBIAN_SUITE main
deb http://security.debian.org/debian-security ${DEBIAN_SUITE}-security main
EOF
cat >"$MNT/etc/apt/apt.conf.d/10katmate" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

# Build-time DNS only. A fresh debootstrap has no resolver link yet, so this is
# a plain file; step 9 replaces it with the relative ../run/resolv.conf link
# (ADR-038 §7, lib.sh resolv_link_install) and reads the link back.
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

# ---- 3. base userspace ------------------------------------------------------
# The minimal GUI runtime every GUI domain shares, and no applications (ADR-014,
# revision note 2026-09-26): TLS roots, fonts (guest renders into buffers
# locally), GTK3, GBM, the Wayland client, and the waypipe RUNTIME libs (the
# source build links against these; build deps are added+purged in step 5).
# Every application — foot, pcmanfm, firefox-esr, keepassxc — is in manifests/.
# libgtk-3-0t64 is trixie's name; the old libgtk-3-0 resolves only as a virtual.
#
# katmate-init is PID 1, yet systemd, systemd-sysv, dbus and dbus-daemon end up
# installed, as dependency debt accepted for the alpha; nothing starts them:
#   GTK3 -> dconf-service -> dbus-user-session -> libpam-systemd -> systemd-sysv
# Removing them is state.md's Next-steps item "systemd purge from foundation".
log "Base userspace (shared GUI runtime; systemd installed as debt, never PID 1)"
chroot_run "$MNT" apt-get update
chroot_run "$MNT" apt-get install -y \
  ca-certificates \
  fontconfig fonts-dejavu-core \
  libgbm1 libwayland-client0 liblz4-1 libzstd1 \
  libgtk-3-0t64

# ---- 4. custom MicroVM kernel — NOT installed into the image ----------------
# The host boots the kernel via -kernel $KERNEL (see app_web.con): monolithic,
# no initrd, no /lib/modules. So there is nothing to install in the guest — no
# .deb, no dpkg, no update-initramfs. The vmlinuz lives outside the image, in
# out/ (placed by the Makefile from $KERNEL_SRC_DIR), and the launcher points
# at it. This step is intentionally a no-op kept for build-order clarity.
log "Custom MicroVM kernel: host-side -kernel boot, nothing to install in image"

# ---- 5. waypipe from source, version-locked (ADR-008) -----------------------
# Build deps installed -> used -> PURGED (must not ship in the foundation).
# Runtime libs (step 3) remain. The 5 gotchas live in ADR-008; the flags below
# encode them (bindgen present; lz4/zstd forced enabled; libgbm-dev satisfies
# wrap-gbm/build.rs though the feature stays off; cargo fetch before meson).
log "waypipe $WAYPIPE_VERSION (source build, then purge build deps)"
WP_BUILD_DEPS="meson ninja-build pkg-config git cargo rustc bindgen \
               libwayland-dev liblz4-dev libzstd-dev libgbm-dev"
chroot_run "$MNT" apt-get install -y $WP_BUILD_DEPS
chroot_run "$MNT" bash -eu -c "
  cd /tmp
  git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git
  cd waypipe
  git checkout $WAYPIPE_VERSION
  cargo fetch                       # build wrapper passes --frozen (gotcha 4)
  meson setup build -Dwith_lz4=enabled -Dwith_zstd=enabled \\
                    -Dwith_gbm=disabled -Dwith_dmabuf=disabled -Dwith_video=disabled
  ninja -C build
  ninja -C build install            # -> /usr/local/bin/waypipe
  /usr/local/bin/waypipe --version  # expect: lz4: true, zstd: true (gotcha 2/5)
"
chroot_run "$MNT" apt-get purge -y $WP_BUILD_DEPS
chroot_run "$MNT" apt-get autoremove --purge -y
rm -rf "$MNT/tmp/waypipe" "$MNT/root/.cargo" "$MNT/root/.cache" 2>/dev/null || true

# ---- 5b. iproute2, after the purge (R147) -----------------------------------
# Not GUI runtime: it puts `ip` in every AppVM, so an in-guest network reading
# needs no /sys and /proc substitute. Installed HERE, after step 5's purge and
# autoremove, and not in step 3: iproute2 Suggests python3, and an installed
# package's Suggests keep the waypipe build residue (python3.13, binutils)
# alive through autoremove — measured in ai5 B3, 72 removed against 91.
log "iproute2 (after the build-dependency purge)"
chroot_run "$MNT" apt-get install -y iproute2

# ---- 5c. read-back: no build residue in the layer ---------------------------
# Step 5's rule — build deps must not ship — made enforceable. Reads the
# layer's dpkg status (nothing installs after this point; step 9 only cleans
# the apt cache) and dies naming any installed (ii) compiler-toolchain or
# Python package. Dying here, before the freeze, lets cleanup remove the
# half-built LV.
# The one exception to gcc*: gcc-<N>-base is libgcc-s1's runtime base, present
# in every known-good layer (ai5: ai3's 209-package foundation and all three
# app layers), and not a compiler.
build_residue_check() {
  local status="$1"
  awk '
    /^Package: /{ p = $2 }
    /^Status: /{ s = $0 }
    /^$/{ emit() } END{ emit() }
    function emit() {
      if (s == "Status: install ok installed" &&
          p ~ /^(python3.*|libpython3.*|binutils.*|libbinutils|gcc.*|cpp.*|meson|ninja-build)$/ &&
          p !~ /^gcc-[0-9]+-base$/)
        print p
      p = s = ""
    }' "$status"
}
DPKG_STATUS="$MNT/var/lib/dpkg/status"
[[ -s "$DPKG_STATUS" ]] || die "read-back: $DPKG_STATUS is missing or empty"
RESIDUE="$(build_residue_check "$DPKG_STATUS")"
[[ -z "$RESIDUE" ]] || die "build residue installed in the foundation (step 5 must purge it):
$RESIDUE"
log "Read-back: no build residue installed among $(grep -c '^Package: ' "$DPKG_STATUS") dpkg records (python3*, libpython3*, binutils*, libbinutils, gcc* but gcc-N-base, cpp*, meson, ninja-build)"

# ---- 6. bake vm-agent + katmate-init ----------------------------------------
# Paths from the live code: vm-agent at /usr/local/bin/vm-agent (`VM_AGENT_PATH`
# in katmate-init.c). katmate-init replaces /sbin/init — kernel default search
# path, so no init= cmdline is needed (its header, "Bake to /sbin/init").
# vm-agent is launched by init dropped to uid 1000; there is NO systemd unit
# (the old vm-agent.service left with the move to katmate-init; the systemd
# package itself remains, step 3).
log "Bake vm-agent -> /usr/local/bin/vm-agent"
install -Dm0755 "$VM_AGENT_BIN" "$MNT/usr/local/bin/vm-agent"

# /sbin/init is /usr/sbin/init through the merged /usr, and dpkg records that
# path as systemd-sysv's. Divert it BEFORE katmate-init lands there, so dpkg no
# longer owns the file katmate-init becomes: otherwise a later purge, reinstall
# or upgrade of systemd-sysv acts on katmate-init. --rename moves systemd's
# binary aside to /usr/sbin/init.systemd, where systemd-sysv's unpacks now go.
log "Divert /usr/sbin/init (systemd-sysv) -> /usr/sbin/init.systemd"
chroot_run "$MNT" dpkg-divert --local --rename \
  --divert /usr/sbin/init.systemd --add /usr/sbin/init
# Read the diversion back from dpkg's own record: a divert that did not land
# would leave katmate-init at a path dpkg still attributes to systemd-sysv.
[[ "$(chroot_run "$MNT" dpkg-divert --truename /usr/sbin/init)" == /usr/sbin/init.systemd ]] \
  || die "divert of /usr/sbin/init did not land"

log "Bake katmate-init -> /sbin/init (PID 1)"
rm -f "$MNT/sbin/init"
install -Dm0755 "$INIT_BIN" "$MNT/sbin/init"

# ---- 7. bake user 1000 ------------------------------------------------------
# katmate-init hardcodes uid 1000 (no NSS lookup), but the account must exist
# for file ownership / XDG_RUNTIME_DIR. /home itself is the per-instance rw LV
# mounted by init at boot; here we only need the passwd/group/shadow entry.
#
# Written DIRECTLY to the account files — no useradd/groupadd (the passwd pkg is
# not in the minbase image, and direct write needs no tooling, keeping the TCB
# minimal). No password set (locked '*'); login is not used — init drops to the
# uid directly. /home/user is NOT created here (it is the per-instance rw LV
# that init mounts at boot).
log "Bake user 'user' (uid/gid 1000) — direct passwd/group/shadow write"
if ! grep -q '^user:' "$MNT/etc/passwd"; then
  echo 'user:x:1000:1000:Katmate user:/home/user:/bin/bash' >> "$MNT/etc/passwd"
fi
if ! grep -q '^user:' "$MNT/etc/group"; then
  echo 'user:x:1000:' >> "$MNT/etc/group"
fi
if ! grep -q '^user:' "$MNT/etc/shadow"; then
  # locked account (no usable password); !* = no login via password
  echo 'user:!*:20000:0:99999:7:::' >> "$MNT/etc/shadow"
fi

# ---- 8. (kernel vmlinuz already lives in out/ — no extraction needed) -------
# Old qcow2/nbd pipeline extracted vmlinuz from the image's /boot. With the
# host-side -kernel boot the vmlinuz is an INPUT (out/), not an output, so
# there is nothing to extract here.

# ---- 9. finalize: cleanup, unmount, RO-freeze -------------------------------
log "Cleanup (apt cache, lists; /etc/resolv.conf -> ../run/resolv.conf, read back)"
chroot_run "$MNT" apt-get clean
resolv_link_install "$MNT"
resolv_link_check "$MNT"
rm -rf "$MNT"/tmp/* "$MNT"/var/lib/apt/lists/* 2>/dev/null || true

log "Unmount + deactivate, then RO-freeze"
umount_root
lv_deactivate
lv_freeze "$FOUNDATION_LV"

# freeze succeeded — disarm the half-built-LV removal in cleanup
SNAP_CREATED=""
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

# ---- 10. write foundation.meta (ADR-019) ------------------------------------
# Host-side source of truth for the active foundation version — readable
# without booting or mounting anything. Ordering is deliberate:
#  * AFTER a successful RO-freeze: the meta must never describe a half-built
#    foundation.
#  * AFTER the rollback trap is disarmed: a meta-write failure must not
#    destroy a valid frozen LV. It dies loudly instead (set -e); the launch
#    preflight refuses to start any instance without a meta, so the gap is
#    detectable, and a manual re-run of this block is safe.
# Format: flat KEY=value, POSIX-sourceable — the preflight reads it with no
# parser. KATMATE_META_VERSION guards future schema changes.
# WAYPIPE_PATCH_LEVEL counts the patch queue (0 until the scaffold exists).
# NOTE: when the patch-apply step lands in step 5, it MUST apply from the same
# $WAYPIPE_PATCHES_DIR this count reads — one dir, one truth.
log "Write $FOUNDATION_META"
WAYPIPE_PATCH_LEVEL=0
if [[ -d "$WAYPIPE_PATCHES_DIR" ]]; then
  WAYPIPE_PATCH_LEVEL=$(find "$WAYPIPE_PATCHES_DIR" -maxdepth 1 -name '*.patch' | wc -l)
fi
install -d -m0755 "$(dirname "$FOUNDATION_META")"
META_TMP="$(mktemp "$(dirname "$FOUNDATION_META")/.foundation.meta.XXXXXX")"
cat >"$META_TMP" <<EOF
KATMATE_META_VERSION=1
WAYPIPE_TAG=$WAYPIPE_VERSION
WAYPIPE_PATCH_LEVEL=$WAYPIPE_PATCH_LEVEL
KERNEL_VERSION=$KERNEL_VERSION
KERNEL_PROVENANCE=$KERNEL_PROVENANCE
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FOUNDATION_LV=$VG/$FOUNDATION_LV
EOF
chmod 0644 "$META_TMP"
mv "$META_TMP" "$FOUNDATION_META"   # atomic: same fs (mktemp in the target dir)

# ---- 11. install the shared MicroVM kernel (ADR-032 §5) ---------------------
# The AppVM kernel is T2 with one value for all images: every image records the
# same KERNEL_VERSION today, and <image>.meta records WHICH kernel an image
# requires, not where it lies. A unit's -kernel therefore resolves to
# $KATMATE_KERNELS_DIR/$(basename) and never into out/ — a unit reading from a
# build tree would be a release running from build artifacts.
#
# Ordering matches step 10 and netvm.sh step 11, for the same two reasons:
#  * AFTER the RO-freeze, so the kernel is never published beside a half-built
#    foundation;
#  * AFTER the rollback trap is disarmed, so a failure here dies loudly (set -e)
#    and leaves a valid frozen LV standing rather than destroying it.
#
# Copy-then-rename on the same filesystem: a launcher never sees a truncated
# kernel. The basename is preserved because it already carries arch and version
# (vmlinuz-katmate-microvm-<arch>-<version>), which is what KERNEL_VERSION in a
# meta resolves against.
# The temporary name carries a leading dot, as netvm.sh step 11 does: a partial
# file named vmlinuz-*.new would be matched by any glob looking for a kernel.
log "Install shared MicroVM kernel -> $KATMATE_KERNELS_DIR"
install -d -m0755 "$KATMATE_KERNELS_DIR"
KERNEL_BASE="$(basename "$KERNEL_VMLINUZ")"
KERNEL_TMP="$KATMATE_KERNELS_DIR/.$KERNEL_BASE.new"
cp -- "$KERNEL_VMLINUZ" "$KERNEL_TMP"
chmod 0644 "$KERNEL_TMP"
mv -f -- "$KERNEL_TMP" "$KATMATE_KERNELS_DIR/$KERNEL_BASE"

# The provenance sidecar travels with the kernel it describes (ADR-034): payload
# and metadata share an author, a lifecycle and an upgrade owner, so they share a
# directory (ADR-032 §5, netvm.meta's precedent). Copied only if it exists —
# absent is not refused, and a build machine with an uncaptured kernel still
# builds. Same dotted temporary as the kernel above, for the same reason: a
# partial file named vmlinuz-*.provenance would be matched by any glob looking
# for one.
if [[ -f "$KERNEL_VMLINUZ.provenance" ]]; then
  log "Install kernel provenance sidecar -> $KATMATE_KERNELS_DIR"
  SIDECAR_TMP="$KATMATE_KERNELS_DIR/.$KERNEL_BASE.provenance.new"
  cp -- "$KERNEL_VMLINUZ.provenance" "$SIDECAR_TMP"
  chmod 0644 "$SIDECAR_TMP"
  mv -f -- "$SIDECAR_TMP" "$KATMATE_KERNELS_DIR/$KERNEL_BASE.provenance"
else
  log "No provenance sidecar beside $KERNEL_BASE — nothing to install (KERNEL_PROVENANCE=$KERNEL_PROVENANCE)"
fi

log "$FOUNDATION_LV ready: RO-frozen thin foundation."
log "Next: sudo make app-web / sudo make app-vault (thin snapshots of this LV)."
log "Reminder: 'lvchange -K -ay $VG/$FOUNDATION_LV' is required before each boot."
log "Kernel boots host-side via -kernel ($KERNEL_VMLINUZ); not in the image."
