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

# --- paths -------------------------------------------------------------------
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$BUILD_DIR/.." && pwd)"
OUT="$ROOT_DIR/out"
MANIFESTS="$ROOT_DIR/manifests"

# --- external artifacts (foundation step only — produced by sub-pipelines) ---
# vm-agent is now Rust (ADR-018) and is baked into the FOUNDATION, not the
# app-layer. App-layer builds need neither the kernel nor vm-agent.
KERNEL_DEB="$OUT/linux-image-katmate-microvm-${ARCH}.deb"   # foundation only (ADR-005)
VM_AGENT_BIN="$OUT/vm-agent"                                # foundation only (Rust, ADR-018)
