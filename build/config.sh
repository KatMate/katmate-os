# Katmate OS — build pipeline shared config (ADR-011)
# Sourced by foundation.sh and app-layer.sh. Not executed directly.

# --- version pins (reproducibility: ADR-011) ---------------------------------
DEBIAN_SUITE="trixie"                 # Debian stable (ADR-002)
SNAPSHOT="20260601T000000Z"           # snapshot.debian.org pin — bump deliberately
WAYPIPE_VERSION="v0.11.0"             # version-locked to host (ADR-008)
ARCH="amd64"

MIRROR="http://snapshot.debian.org/archive/debian/${SNAPSHOT}"
SECURITY_MIRROR="http://snapshot.debian.org/archive/debian-security/${SNAPSHOT}"

# --- paths -------------------------------------------------------------------
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$BUILD_DIR/.." && pwd)"
OUT="$ROOT_DIR/out"
MANIFESTS="$ROOT_DIR/manifests"

# --- external artifacts (hooks — produced by their own sub-pipelines) --------
# These are NOT built by this skeleton yet. foundation.sh fails clearly if absent.
KERNEL_DEB="$OUT/linux-image-katmate-microvm-${ARCH}.deb"   # TODO: kernel sub-pipeline (Debian LTS + katmate-microvm config, ADR-005)
VM_AGENT_BIN="$OUT/vm-agent"                                # TODO: build ../vm-agent (C), copy binary here

# --- foundation image --------------------------------------------------------
FOUNDATION_SIZE="4G"                  # sparse (qcow2); raise if app layers need headroom

# --- nbd device --------------------------------------------------------------
NBD="/dev/nbd0"
