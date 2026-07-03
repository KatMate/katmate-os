#!/usr/bin/env bash
#
# waypipe-host.sh — build the KatMate host-side waypipe binary (ADR-019/020).
#
# Builds waypipe from the project-pinned upstream tag + KatMate patch queue,
# with the SAME feature flags as the guest build, and installs it to
# /opt/katmate/bin/waypipe (outside the package manager).
#
# This is BUILD-TIME developer tooling (ADR-020): it runs on the developer
# host, never at OS install time. Build dependencies are CHECKED, never
# installed — the installed OS must not depend on git/toolchain.
#
# Host is NOT an appliance: build-deps are NOT purged afterwards.

set -euo pipefail

# --- Pin (single source of truth for the project-wide waypipe version) -------
WAYPIPE_REPO="https://gitlab.freedesktop.org/mstoeckl/waypipe.git"
WAYPIPE_TAG="v0.11.0"

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/../third_party/waypipe/patches"
INSTALL_DIR="/opt/katmate/bin"
INSTALL_PATH="${INSTALL_DIR}/waypipe"

# --- Build dependencies: CHECK ONLY (ADR-020) --------------------------------
# Must match the guest recipe (ARCHITECTURE.md). bindgen ships as the
# `bindgen` CLI on Debian/Arch; verify the binary, not the crate.
REQUIRED_TOOLS=(git meson ninja cargo rustc bindgen pkg-config gcc)

check_build_deps() {
    local missing=()
    local t
    for t in "${REQUIRED_TOOLS[@]}"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done

    # gbm wrapper's build.rs calls pkg-config gbm even with the feature off
    # (guest gotcha #3); libgbm-dev must be present at build time.
    pkg-config --exists gbm 2>/dev/null || missing+=("gbm (libgbm-dev)")
    # waypipe links libwayland, lz4, zstd.
    pkg-config --exists wayland-client 2>/dev/null || missing+=("wayland-client (libwayland-dev)")
    pkg-config --exists liblz4 2>/dev/null || missing+=("liblz4 (liblz4-dev)")
    pkg-config --exists libzstd 2>/dev/null || missing+=("libzstd (libzstd-dev)")

    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: missing build dependencies (install them manually; this" >&2
        echo "       script never auto-installs — ADR-020):" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

# --- Ephemeral build tree ----------------------------------------------------
BUILD_TREE=""
cleanup() {
    [[ -n "$BUILD_TREE" && -d "$BUILD_TREE" ]] && rm -rf "$BUILD_TREE"
}
trap cleanup EXIT

main() {
    echo "==> checking build dependencies"
    check_build_deps

    if [[ ! -d "$PATCH_DIR" ]]; then
        echo "ERROR: patch queue not found: $PATCH_DIR" >&2
        exit 1
    fi

    BUILD_TREE="$(mktemp -d)"
    local src="${BUILD_TREE}/waypipe"

    echo "==> cloning waypipe ${WAYPIPE_TAG}"
    git clone --depth 1 --branch "$WAYPIPE_TAG" "$WAYPIPE_REPO" "$src"
    cd "$src"

    # --- Apply KatMate patch queue in ascending filename order ---------------
    shopt -s nullglob
    local patches=("$PATCH_DIR"/*.patch)
    shopt -u nullglob
    if (( ${#patches[@]} == 0 )); then
        echo "==> patch queue empty (patch level 0) — building pristine ${WAYPIPE_TAG}"
    else
        echo "==> applying ${#patches[@]} patch(es)"
        local p
        for p in "${patches[@]}"; do
            echo "    - $(basename "$p")"
            git apply "$p"
        done
    fi

    # --- Build (SAME flags as the guest — ARCHITECTURE.md) -------------------
    # cargo fetch BEFORE meson: the compile wrapper runs cargo --frozen
    # (guest gotcha #4).
    echo "==> cargo fetch"
    cargo fetch

    echo "==> meson setup"
    # lz4/zstd forced enabled so a missing lib fails loudly instead of
    # producing a binary that cannot talk to the guest (gotcha #2).
    meson setup build \
        -Dbuildtype=release \
        -Dwith_lz4=enabled \
        -Dwith_zstd=enabled \
        -Dwith_gbm=disabled \
        -Dwith_dmabuf=disabled \
        -Dwith_video=disabled

    echo "==> ninja build"
    ninja -C build

    # --- Install (outside the package manager) -------------------------------
    echo "==> installing to ${INSTALL_PATH}"
    sudo install -d "$INSTALL_DIR"
    sudo install -m 0755 build/waypipe "$INSTALL_PATH"

    echo "==> done:"
    "$INSTALL_PATH" --version
    echo
    echo "Verify: lz4 and zstd must both report true."
}

main "$@"
