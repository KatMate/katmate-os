# shellcheck shell=bash
# katmate-lib.sh — shared readers for the T4 executables (ADR-032 §2)
#
# Installed at /usr/lib/katmate/katmate-lib.sh, mode 0644. It is SOURCED, never
# executed, and it is not one of the five T4 executables: it carries no check,
# no policy and no decision. Only three things live here — the canonical paths,
# a diagnostic style, and the two readers (T1 and T2) that three of the four
# executables would otherwise each carry a copy of.
#
# Why a library at all, when /usr/lib/katmate/ is a flat directory of
# single-purpose executables: `katmate-check-image`, `katmate-activate-lvs` and
# `katmate-generate-env` all have to read a T1 file and a T2 meta. Three copies
# of one parser is this project's characteristic failure — a second source that
# drifts — and the parser is the part where a divergence would be silent rather
# than loud: a copy that treats `netvm = ""` as absent instead of empty inverts
# ADR-032 §3's "declared offline domain" into "unstated assumption".
#
# What is deliberately NOT here:
#
#  * The profile function. ADR-032 §2 permits deriving the profile only from
#    `(class, netvm, nic)`, and there is exactly one path to it. It lives in
#    `katmate-generate-env`, which is its only caller. A copy here would be a
#    second path, which is what the authority limit exists to prevent.
#  * The T1 schema (which keys are legal for which class). That is enforced
#    where it is consumed, in `katmate-generate-env`. This file knows the file's
#    SYNTAX and nothing about its meaning.

# The path is the tier (ADR-032 §1). Stated once here, for the same reason
# build/config.sh states its own locations once: a second literal is a second
# thing to keep true.
# Each of these is read by the sourcing executable rather than by this file, and
# the use is invisible to a static checker across an absolute `source` path.
# shellcheck disable=SC2034
KM_ETC_VM="/etc/katmate/vm"          # T1, user-authored
KM_STATE_DIR="/var/lib/katmate"      # T2, build-pipeline-authored
KM_KERNELS_DIR="$KM_STATE_DIR/kernels"
KM_INSTANCES_DIR="$KM_STATE_DIR/instances"
KM_RUN_DIR="/run/katmate"            # the projection; nothing else may be written

# KM_PROG is the name in every diagnostic. Each executable sets it; the default
# only exists so a sourcing mistake does not print an empty prefix.
KM_PROG="${KM_PROG:-katmate}"

km_log()  { printf '[%s] %s\n' "$KM_PROG" "$*"; }

# A T4 executable decides binarily — proceed, or fail loudly (ADR-032 §2).
# Two exit codes, because they mean different things to whoever reads the
# journal: 1 = the check failed (this is the answer), 2 = the executable was
# called wrongly (there is no answer). `tools/validate-properties.fish` already
# separates these two, and anything reading exit status must not treat non-zero
# as uniformly "invalid".
km_die()   { printf '[%s] FATAL: %s\n' "$KM_PROG" "$*" >&2; exit 1; }
km_usage() { printf '[%s] USAGE: %s\n' "$KM_PROG" "$*" >&2; exit 2; }

# --- instance names ----------------------------------------------------------
# The instance name arrives as systemd's %i and becomes a filename under
# /etc/katmate/vm/. It is checked before it is concatenated into any path: %i is
# whatever `systemctl start katmate-sys-driver@<anything>` was given, and a
# name containing `/` or `..` would read a T1 file from outside the tier
# directory — a T1 file whose path no longer asserts its tier.
#
# The pattern is the validator's rule for a VM name (`netvm = "<name>"`,
# [a-z][a-z0-9_]*), not a second convention.
km_check_instance() {
    local name="${1-}"
    [[ -n "$name" ]] || km_usage "empty instance name"
    [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] \
        || km_die "instance name '$name' is not [a-z][a-z0-9_]* — it is used as a filename under $KM_ETC_VM and is not taken on trust"
}

# --- T1: /etc/katmate/vm/<instance>.toml -------------------------------------
# Fills the associative array KM_T1 and sets KM_T1_FILE. Presence is tested
# with `[[ -v KM_T1[key] ]]`, never with -n: an EMPTY value is a valid value and
# differs from an absent key (ADR-032 §3 — `netvm = ""` is a declared offline
# domain, an absent `netvm` is an unstated assumption).
#
# This is a reader for the subset of TOML the schema uses — flat key = value,
# quoted strings, integers, booleans, comments — and it refuses everything else
# rather than skipping it. A line it cannot parse is an error, because a T1 line
# silently dropped is the silent-wrong-object class the schema exists to close.
declare -gA KM_T1=()
KM_T1_FILE=""

km_t1_read() {
    local instance="$1" line key val lineno=0
    km_check_instance "$instance"
    KM_T1_FILE="$KM_ETC_VM/$instance.toml"
    KM_T1=()

    [[ -e "$KM_T1_FILE" ]] \
        || km_die "no T1 properties for instance '$instance': $KM_T1_FILE does not exist. T1 is user-authored and is never shipped (ADR-032 §1); the installer seeds it at build-order step 6."
    [[ -f "$KM_T1_FILE" && -r "$KM_T1_FILE" ]] \
        || km_die "$KM_T1_FILE is not a readable regular file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$(( lineno + 1 ))
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]]; then continue; fi
        if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
            km_die "$KM_T1_FILE:$lineno: TOML tables are not part of the T1 schema — every key is top-level"
        fi

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
        else
            km_die "$KM_T1_FILE:$lineno: not a 'key = value' line: $line"
        fi

        # A quoted value is taken literally, so a '#' inside it is not a
        # comment; an unquoted value is a bare int or bool and may carry a
        # trailing comment. Anything else (arrays, multi-line strings, an
        # unterminated quote) is refused rather than guessed at.
        if [[ "$val" =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
            val="${BASH_REMATCH[1]}"
        elif [[ "$val" =~ ^([^[:space:]\"#]+)[[:space:]]*(#.*)?$ ]]; then
            val="${BASH_REMATCH[1]}"
        else
            km_die "$KM_T1_FILE:$lineno: unparsable value for '$key' — expected \"string\", integer or true/false"
        fi

        # TOML forbids a duplicate key, and the last-wins reading a naive parser
        # gives it is precisely a file that says one thing and means another.
        if [[ -v KM_T1[$key] ]]; then
            km_die "$KM_T1_FILE:$lineno: duplicate key '$key' — a T1 file has one value per key, and last-wins would make the file disagree with itself"
        fi

        KM_T1[$key]="$val"
    done < "$KM_T1_FILE"

    [[ -v KM_T1[class] ]] \
        || km_die "$KM_T1_FILE: no 'class' key. Everything class-dependent — the required and forbidden key sets, the manifest values, the CID band, the profile — is unevaluable without it (ADR-032 §3)."
}

# Read a key this executable needs, or fail naming the file it came from.
km_t1_require() {
    local key="$1"
    [[ -v KM_T1[$key] ]] \
        || km_die "$KM_T1_FILE: missing required key '$key'"
    printf '%s' "${KM_T1[$key]}"
}

# --- T2: <image>.meta --------------------------------------------------------
# Flat KEY=value, the foundation.meta pattern (ADR-030 T2). Read with sed and
# never sourced: build/app-layer.sh states the reason and it holds here with
# more force — these run before QEMU in the launch path, and executing a data
# file to read it would make a T2 file a code path.
km_meta_get() {
    local file="$1" key="$2"
    sed -n "s/^${key}=//p" "$file" | head -n1
}

km_meta_require() {
    local file="$1" key="$2" val
    val="$(km_meta_get "$file" "$key")"
    [[ -n "$val" ]] \
        || km_die "$file records no $key — the image metadata cannot answer what this check needs"
    printf '%s' "$val"
}

# KATMATE_META_VERSION guards a schema change; a meta from a future pipeline is
# refused rather than half-understood.
km_meta_open() {
    local file="$1" version
    [[ -e "$file" ]] \
        || km_die "T2 image metadata not found: $file. It is written by the build pipeline after a successful freeze (ADR-032 §5); a missing meta means no image was built, or it was built by a pipeline that predates the meta."
    [[ -f "$file" && -r "$file" ]] || km_die "$file is not a readable regular file"
    version="$(km_meta_require "$file" KATMATE_META_VERSION)"
    [[ "$version" == "1" ]] \
        || km_die "$file has KATMATE_META_VERSION=$version; this executable understands version 1 only"
}

# --- /run/katmate ------------------------------------------------------------
# The only tree a T4 executable may write (ADR-032 §2). The executables create
# their own subtrees rather than the unit declaring RuntimeDirectory=, because
# RuntimeDirectory is removed when an instance stops and would take the shared
# parent — and every other instance's projection and the boot's nic labels —
# with it.
km_run_subdir() {
    # Two `local` statements, not one: in bash 5.3 the right-hand sides of a
    # single `local a=… b="$a"` are all expanded before any of the assignments
    # take effect, so `dir` would have been built from an empty `sub` and the
    # projection would have landed in /run/katmate/ instead of /run/katmate/vm/.
    # Caught by shellcheck SC2318 (see the note in the report: a static check
    # earning its keep on a path a behavioural test would also have found, but
    # later).
    local sub="$1"
    local dir="$KM_RUN_DIR/$sub"
    install -d -m 0755 "$dir" \
        || km_die "cannot create $dir"
    printf '%s' "$dir"
}
