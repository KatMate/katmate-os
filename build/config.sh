# Katmate OS — build pipeline shared config (ADR-011, LVM-thin per ADR-010 rev 2026-06)
# Sourced by foundation.sh and app-layer.sh. Not executed directly.

# --- version pins (reproducibility: ADR-011 — DEFERRED, see note) ------------
# These are retained for when katmate-update makes determinism meaningful.
# NOT yet applied to the build: foundation/app layers use plain `debootstrap
# trixie` / `apt-get` against current packages (the RO-frozen LV is the
# effective pin). Do not wire SNAPSHOT into apt sources until the rebuild
# pipeline exists.
DEBIAN_SUITE="trixie"                 # Debian stable (ADR-002)
SNAPSHOT="20260601T000000Z"           # snapshot.debian.org pin — DEFERRED, unused
WAYPIPE_VERSION="v0.11.0"             # version-locked to host (ADR-008)
ARCH="amd64"

# --- LVM layout (live names on MINIS/UM870, ADR-010) -------------------------
VG="vg0"
POOL="vm_pool"
FOUNDATION_LV="vm_tpl_foundation"     # thin, RO-frozen — the single shared base
APP_LV_PREFIX="vm_app_"               # app-<type> -> vm_app_<type> (e.g. vm_app_web)

# --- netVM uplink: guest PCI address (ADR-037 R4, R10, R12, R13) -------------
# The ONE build-side source of the uplink's guest PCI address. build/netvm.sh
# checks 60-katmate-uplink.link's Path= against it and records it in netvm.meta
# as UPLINK_PCI_ADDR. The same constant is also written, as addr=0x4, into
# katmate-sys-driver@.service; nothing compares the unit with this value yet
# (open problem #44). Change all three together, or the uplink stays unrenamed.
NETVM_UPLINK_PCI_ADDR="0000:00:04.0"

# --- paths -------------------------------------------------------------------
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$BUILD_DIR/.." && pwd)"
OUT="$ROOT_DIR/out"
MANIFESTS="$ROOT_DIR/manifests"

# --- external artifacts (foundation step only — produced by sub-pipelines) ---
# vm-agent is now Rust (ADR-039) and is baked into the FOUNDATION, not the
# app-layer. App-layer builds need neither the kernel nor vm-agent.

KERNEL_VERSION="6.12.87"                                              # custom MicroVM kernel (ADR-005)
KERNEL_VMLINUZ="$OUT/vmlinuz-katmate-microvm-${ARCH}-${KERNEL_VERSION}"  # external -kernel, NOT .deb (ARCHITECTURE.md update-flow §4)
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$HOME/katmate-kernels}"             # Makefile copies vmlinuz from here into OUT

VM_AGENT_BIN="$OUT/vm-agent"                                # foundation only (Rust, ADR-039)
INIT_SRC="$ROOT_DIR/init/katmate-init.c"
INIT_BIN="$OUT/katmate-init"

# --- T2: host-side image metadata and payload (ADR-030, ADR-032 §1/§5) -------
# The path IS the tier. Everything the build pipeline produces and a launcher
# later reads lives under this directory; a reader establishes a file's tier
# with `ls`, not by reading an ADR. OUT (out/) stays a BUILD tree and is never
# read at runtime — a unit reading from out/ would be a release running from
# build artifacts.
#
# Recorded tension (ADR-020): the build is developer-side and the install is
# user-side, so populating /var/lib/katmate/ at build time collapses two
# stages. foundation.meta below already does exactly this; we follow the
# precedent rather than invent a second pattern for the same fact.
KATMATE_STATE_DIR="/var/lib/katmate"

# --- T2: the shared MicroVM kernel (ADR-032 §5) ------------------------------
# Built once, used by every AppVM. <image>.meta records WHICH kernel an image
# requires (KERNEL_VERSION), never where it lies — so the path is composed from
# this directory plus the recorded version, and a unit's -kernel never points
# into a build tree. Stated here for the same reason FOUNDATION_META is: one
# location, one place that says it.
KATMATE_KERNELS_DIR="$KATMATE_STATE_DIR/kernels"

# --- foundation build metadata (ADR-019) --------------------------------------
# Host-side source of truth for the active foundation version. Written by
# foundation.sh after a successful RO-freeze; read by the instance launch
# preflight (host waypipe --version vs meta — refuse loudly on mismatch) and
# updated by katmate-update at each release bump.
FOUNDATION_META="$KATMATE_STATE_DIR/foundation.meta"

# --- app-layer metadata, one per image (ADR-030 T2, ADR-032 §5) --------------
# Naming: app-<type>.meta, after the IMAGE (app-<type>, ADR-010/ADR-014), NOT
# after the manifest. A bare `web.meta` sitting beside foundation.meta would
# read as metadata about manifests/web.list. Composed by app-layer.sh, which
# owns the <type>; kept here so the location is stated in one place.
#   $KATMATE_STATE_DIR/app-<type>.meta
# KatMate waypipe patch queue (ADR-019, strip & harden only). May not exist
# yet — patch level 0 until the scaffold lands.
WAYPIPE_PATCHES_DIR="$ROOT_DIR/third_party/waypipe/patches"
