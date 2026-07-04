#!/usr/bin/env bash
#
# katmate-update.sh — waypipe version-bump release orchestrator (MVP).
#
# Per ADR-019 / ARCHITECTURE.md §Update flow, a waypipe version bump is a
# deliberate release act. This script chains the already-proven build steps in
# dependency order:
#
#   (WAYPIPE_VERSION already edited in config.sh, by hand)
#     -> rebase patch queue (manual; reminded, not performed)
#     -> build host binary          (build/waypipe-host.sh)
#     -> rebuild foundation          (make foundation)   [writes foundation.meta]
#     -> re-snapshot each app-<type> (make app-<type>)
#     -> recreate instance deltas    (qemu-img create ... -b vm_app_<type>)
#   Home LVs are never touched.
#
# MVP scope (deliberately narrow):
#   * Assumes all instance VMs are STOPPED. It does NOT tear them down
#     (teardown = policy: disposable vs persistent, must not kill netVM/CID 3 —
#     that belongs to the launch daemon, not the rebuild path). Instead it
#     PREFLIGHTS: if any qemu holds an instance delta, it aborts loudly before
#     the destructive foundation rebuild.
#   * WAYPIPE_VERSION is edited by hand in config.sh; this script only READS it.
#     (Note: config.sh's variable is WAYPIPE_VERSION; the foundation.meta KEY
#     written by foundation.sh is WAYPIPE_TAG — same value, two names.)
#   * App types are the two current domains: web, vault (ADR-014), matching the
#     Makefile's APP_TYPES.
#   * vm-agent and the kernel vmlinuz are NOT built here — they are separate
#     steps with their own logic. We only CHECK they exist so a missing artefact
#     fails before the destructive rebuild, not midway through `make foundation`.
#
#   --dry-run : run every check and print the plan, but perform no build,
#               no make, and no delta recreation. Non-destructive.
#
# Runs on MINIS (the build/merge host). Bash per pipeline convention.
#
set -euo pipefail

# --- args -------------------------------------------------------------------
DRY_RUN=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown argument: ${arg} (try --help)" >&2; exit 2 ;;
    esac
done

# --- locate & source config -------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIG="${SCRIPT_DIR}/config.sh"

if [[ ! -r "${CONFIG}" ]]; then
    echo "FATAL: cannot read ${CONFIG}" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG}"

# --- knobs (all interface values come from config.sh; check they are set) ---
APP_TYPES=(web vault)                     # matches Makefile APP_TYPES
INSTANCES_DIR="${INSTANCES_DIR:-/var/lib/katmate/instances}"
DELTA_SIZE="${DELTA_SIZE:-10G}"
: "${VG:?config.sh must export VG}"
: "${APP_LV_PREFIX:?config.sh must export APP_LV_PREFIX}"
: "${WAYPIPE_VERSION:?config.sh must export WAYPIPE_VERSION}"
: "${ROOT_DIR:?config.sh must export ROOT_DIR}"
: "${OUT:?config.sh must export OUT}"
: "${VM_AGENT_BIN:?config.sh must export VM_AGENT_BIN}"
: "${KERNEL_VMLINUZ:?config.sh must export KERNEL_VMLINUZ}"
: "${KERNEL_VERSION:?config.sh must export KERNEL_VERSION}"
: "${FOUNDATION_META:?config.sh must export FOUNDATION_META}"
HOST_BUILD="${SCRIPT_DIR}/waypipe-host.sh"

log()  { printf '[katmate-update] %s\n' "$*"; }
die()  { printf '[katmate-update] FATAL: %s\n' "$*" >&2; exit 1; }
step() { printf '\n[katmate-update] === %s ===\n' "$*"; }
run()  {
    # Execute, or (in dry-run) just print what would run.
    if [[ ${DRY_RUN} -eq 1 ]]; then
        printf '[katmate-update] DRY-RUN would: %s\n' "$*"
    else
        "$@"
    fi
}

confirm() {
    # Interactive gate before the first destructive action. Skipped in dry-run.
    [[ ${DRY_RUN} -eq 1 ]] && { log "DRY-RUN: skipping confirmation"; return 0; }
    local reply
    read -r -p "[katmate-update] $1 [y/N] " reply
    [[ "${reply}" == "y" || "${reply}" == "Y" ]] || die "aborted by user"
}

# --- 0. sanity --------------------------------------------------------------
# Root not required for a dry-run (no LVM / mount / qemu-img touched).
if [[ ${DRY_RUN} -eq 0 ]]; then
    [[ $EUID -eq 0 ]] || die "must run as root (LVM / mount / qemu-img)"
fi
[[ -x "${HOST_BUILD}" ]] || die "missing or non-executable ${HOST_BUILD}"
command -v qemu-img >/dev/null || die "qemu-img not found"
command -v make     >/dev/null || die "make not found"
command -v fuser    >/dev/null || die "fuser not found (install psmisc)"

# Foundation build prerequisites (Makefile: out/vm-agent + kernel vmlinuz).
# Check here so a missing artefact fails BEFORE the destructive rebuild, not
# midway through `make foundation`. We do NOT build them. The kernel is checked
# at its SOURCE (KERNEL_SRC_DIR); the Makefile copies it into OUT itself.
[[ -f "${VM_AGENT_BIN}" ]] \
    || die "missing ${VM_AGENT_BIN} — build it first (cargo build --release in agent/, cp to out/). See Makefile."
[[ -f "${KERNEL_SRC_DIR}/$(basename "${KERNEL_VMLINUZ}")" ]] \
    || die "missing kernel vmlinuz for ${KERNEL_VERSION} in ${KERNEL_SRC_DIR}"

log "repo root:      ${ROOT_DIR}"
log "waypipe:        ${WAYPIPE_VERSION}  (WAYPIPE_VERSION, read from config.sh)"
log "app types:      ${APP_TYPES[*]}"
log "instances dir:  ${INSTANCES_DIR}"
log "kernel src:     ${KERNEL_SRC_DIR}/$(basename "${KERNEL_VMLINUZ}")"
log "vm-agent:       ${VM_AGENT_BIN}"
[[ ${DRY_RUN} -eq 1 ]] && log "MODE:           DRY-RUN (no build, no make, no recreate)"

# --- 1. remind about the manual patch-queue rebase --------------------------
# The patch queue must already be rebased onto the new pinned tag. We cannot
# verify a human's intent; we only make the requirement impossible to forget.
step "patch-queue rebase (manual precondition)"
log "Ensure ${WAYPIPE_PATCHES_DIR:-third_party/waypipe/patches/} is rebased onto ${WAYPIPE_VERSION}"
log "and applies cleanly with 'git apply' in ascending filename order."
log "Not performed here."

# --- 2. preflight: no instance delta may be held by a running qemu ----------
# Foundation rebuild is destructive to the whole backing chain below it. A
# running instance holding a delta would (a) desync and (b) block qemu-img at
# recreate with a write lock. Refuse before touching anything.
step "preflight: instances must be stopped"
mapfile -t DELTAS < <(find "${INSTANCES_DIR}" -maxdepth 1 -name '*.qcow2' -type f 2>/dev/null | sort)

if [[ ${#DELTAS[@]} -eq 0 ]]; then
    log "no instance deltas found in ${INSTANCES_DIR}"
else
    log "found ${#DELTAS[@]} instance delta(s):"
    printf '           %s\n' "${DELTAS[@]}"
    held=0
    for d in "${DELTAS[@]}"; do
        # fuser is quiet and exact about "which process holds this file".
        if fuser "${d}" &>/dev/null; then
            log "  HELD by a running process: ${d}"
            held=1
        fi
    done
    [[ ${held} -eq 0 ]] || die "one or more instance deltas are in use — stop VMs first (ping-client shutdown <cid>). Do NOT kill netVM (CID 3)."
    log "all deltas free (no qemu holds them)"
fi

# Validate the delta -> app-type mapping now, so a stray/unknown type aborts in
# the preflight rather than after foundation has already been rebuilt.
for d in "${DELTAS[@]}"; do
    base="$(basename "${d}" .qcow2)"      # e.g. test_web
    type="${base##*_}"                    # e.g. web
    known=0
    for t in "${APP_TYPES[@]}"; do [[ "${t}" == "${type}" ]] && known=1; done
    [[ ${known} -eq 1 ]] || die "delta '${d}' maps to unknown app type '${type}' — expected one of: ${APP_TYPES[*]}"
done
[[ ${#DELTAS[@]} -gt 0 ]] && log "delta -> app-type mapping OK"

confirm "This rebuilds foundation + app layers and RECREATES every instance delta above. Proceed?"

# --- 3. build host waypipe binary -------------------------------------------
step "build host waypipe (${WAYPIPE_VERSION}) -> /opt/katmate/bin/waypipe"
run "${HOST_BUILD}"

# --- 4. rebuild foundation (writes foundation.meta at RO-freeze) ------------
step "make foundation"
run make -C "${ROOT_DIR}" foundation

# --- 5. re-snapshot each app-<type> -----------------------------------------
for t in "${APP_TYPES[@]}"; do
    step "make app-${t}"
    run make -C "${ROOT_DIR}" "app-${t}"
done

# --- 6. recreate instance deltas --------------------------------------------
# Delta -> app-type mapping is by filename convention: <instance>_<type>.qcow2.
# The type is the last '_' segment before .qcow2. (Mapping validated in the
# preflight.)
step "recreate instance deltas"
if [[ ${#DELTAS[@]} -eq 0 ]]; then
    log "nothing to recreate"
else
    for d in "${DELTAS[@]}"; do
        base="$(basename "${d}" .qcow2)"
        type="${base##*_}"
        backing="/dev/${VG}/${APP_LV_PREFIX}${type}"

        if [[ ${DRY_RUN} -eq 0 ]]; then
            [[ -e "${backing}" ]] || die "backing LV missing: ${backing}"
        fi

        log "recreate ${d}  (backing: ${backing})"
        run rm -f -- "${d}"
        run qemu-img create -f qcow2 -F raw -b "${backing}" "${d}" "${DELTA_SIZE}"
    done
    log "recreated ${#DELTAS[@]} delta(s)"
fi

# --- 7. done ----------------------------------------------------------------
step "done"
if [[ ${DRY_RUN} -eq 1 ]]; then
    log "DRY-RUN complete — no changes made."
    exit 0
fi
log "foundation.meta now records:"
if [[ -r "${FOUNDATION_META}" ]]; then
    sed 's/^/           /' "${FOUNDATION_META}"
fi
log "Instances will preflight host waypipe (${WAYPIPE_VERSION}) against the meta at next launch."
