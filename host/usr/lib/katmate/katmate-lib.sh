# shellcheck shell=bash
# katmate-lib.sh — shared readers for the T4 executables (ADR-032 §2)
#
# Installed at /usr/lib/katmate/katmate-lib.sh, mode 0644. It is SOURCED, never
# executed, and it is not one of the five T4 executables: it carries no check,
# no policy and no decision. Only these things live here — the canonical paths,
# a diagnostic style, the two readers (T1 and T2) that three of the four
# executables would otherwise each carry a copy of, and the layer-manifest
# reader (ADR-043 §6), which the build scripts source by path. The T1 reader is a flat
# key = value parser that takes a path (km_flat_read), and km_t1_read is its
# wrapper for <instance>.toml.
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
    # The guest takes the name as its hostname (km.name=, R125), and
    # katmate-init refuses more than 63 bytes by exiting the VM at boot. The
    # host refuses first, here, where the reason can be named.
    (( ${#name} <= 63 )) \
        || km_die "instance name '$name' is ${#name} bytes; at most 63 (it becomes the guest hostname, R125)"
}

# --- T1: the flat key = value reader -----------------------------------------
# km_flat_read <file> <array> fills the associative array named <array> from
# <file>. It is the one parser for both T1 forms (ADR-032 §1 and its note of
# 2026-09-27): <instance>.toml through km_t1_read below, and the per-concern
# files in <instance>.d/ (ADR-037 R37). It knows the syntax and nothing else —
# which file, which keys and what they mean are the caller's.
#
# Presence is tested with `[[ -v ARRAY[key] ]]`, never with -n: an EMPTY value
# is a valid value and differs from an absent key (ADR-032 §3 — `netvm = ""` is
# a declared offline domain, an absent `netvm` is an unstated assumption).
#
# This is a reader for the subset of TOML the schema uses — flat key = value,
# quoted strings, integers, booleans, comments — and it refuses everything else
# rather than skipping it. A line it cannot parse is an error, because a T1 line
# silently dropped is the silent-wrong-object class the schema exists to close.
#
# A missing file is the caller's to diagnose: km_t1_read's absence means "no
# such instance", and an absent <instance>.d/ file can mean "not configured".
km_flat_read() {
    local file="$1" line key val lineno=0
    local -n km_flat_out="$2"
    km_flat_out=()

    [[ -f "$file" && -r "$file" ]] \
        || km_die "$file is not a readable regular file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$(( lineno + 1 ))
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]]; then continue; fi
        if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
            km_die "$file:$lineno: TOML tables are not part of the T1 schema — every key is top-level"
        fi

        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
        else
            km_die "$file:$lineno: not a 'key = value' line: $line"
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
            km_die "$file:$lineno: unparsable value for '$key' — expected \"string\", integer or true/false"
        fi

        # TOML forbids a duplicate key, and the last-wins reading a naive parser
        # gives it is precisely a file that says one thing and means another.
        if [[ -v km_flat_out[$key] ]]; then
            km_die "$file:$lineno: duplicate key '$key' — a T1 file has one value per key, and last-wins would make the file disagree with itself"
        fi

        # The target is associative (KM_T1 is `declare -gA`), which shellcheck
        # cannot see through the nameref: without the `$` the subscript would
        # be the literal string "key".
        # shellcheck disable=SC2004
        km_flat_out[$key]="$val"
    done < "$file"
}

# --- T1: /etc/katmate/vm/<instance>.toml -------------------------------------
# Fills the associative array KM_T1 and sets KM_T1_FILE: km_flat_read, bound to
# the instance's properties file, plus the one key every reader of that file
# needs before it can evaluate anything else.
declare -gA KM_T1=()
KM_T1_FILE=""

km_t1_read() {
    local instance="$1"
    km_check_instance "$instance"
    KM_T1_FILE="$KM_ETC_VM/$instance.toml"
    KM_T1=()

    [[ -e "$KM_T1_FILE" ]] \
        || km_die "no T1 properties for instance '$instance': $KM_T1_FILE does not exist. T1 is user-authored and is never shipped (ADR-032 §1); the installer seeds it at build-order step 6."
    km_flat_read "$KM_T1_FILE" KM_T1

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

# km_t1_instances: the name of every T1 file, sorted.
km_t1_instances() {
    local f
    for f in "$KM_ETC_VM"/*.toml; do
        [[ -e "$f" ]] || continue
        f="${f##*/}"
        printf '%s\n' "${f%.toml}"
    done
}

# km_t1_cid_pairs: "<instance> <cid>" for every T1 file, read with km_t1_read
# (R150); katmate-alloc's `cid check` and `cid next` take this as input. Run
# in $(…), every failure exits explicitly.
km_t1_cid_pairs() {
    local inst cid
    while read -r inst; do
        km_t1_read "$inst"
        cid="$(km_t1_require cid)" || exit 1
        printf '%s %s\n' "$inst" "$cid"
    done < <(km_t1_instances)
}

# --- layer manifests (ADR-043 §6) ---------------------------------------------
# One schema, two tiers, and the path is the tier. Flat TOML with exactly three
# keys, all required, none empty: kind (a string), packages and run (arrays of
# strings on one line; a multi-line array is refused, cu2 ruling D2). Names in
# both lists match the package regex, which `run` shares (D5).
# shellcheck disable=SC2034
KM_LAYER_T3_DIR="/usr/lib/katmate/layer"
# shellcheck disable=SC2034
KM_LAYER_T1_DIR="/etc/katmate/layer"
KM_LAYER_NAME_RE='^[a-z][a-z0-9]*$'
KM_PKG_NAME_RE='^[a-z0-9][a-z0-9+.-]*$'
KM_LAYER_KINDS=(debian-manifest)

declare -g KM_MF_FILE="" KM_MF_TIER="" KM_MF_KIND=""
declare -ga KM_MF_PACKAGES=() KM_MF_RUN=() KM_MF_LIST=()

# km_manifest_list <where> <key> <value>: one single-line array into KM_MF_LIST.
km_manifest_list() {
    local where="$1" key="$2" val="$3" inner rest part name
    local -a parts=()
    local -A seen=()
    KM_MF_LIST=()
    [[ "$val" == \[* ]] \
        || km_die "$where: '$key' must be an array of strings: [\"a\", \"b\"]"
    [[ "$val" == *']'* ]] \
        || km_die "$where: '$key' opens an array that does not close on this line. Multi-line arrays are not part of the manifest schema: write the array on one line."
    inner="${val#\[}"
    inner="${inner%%]*}"
    rest="${val#*]}"
    [[ "$rest" =~ ^[[:space:]]*(#.*)?$ ]] \
        || km_die "$where: unexpected text after the array of '$key': '$rest'"
    [[ ! "$inner" =~ ,[[:space:]]*$ ]] \
        || km_die "$where: '$key' ends with a comma"
    [[ ! "$inner" =~ ^[[:space:]]*$ ]] || return 0
    IFS=, read -r -a parts <<<"$inner"
    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[[:space:]]*\"([^\"]*)\"[[:space:]]*$ ]] \
            || km_die "$where: '$key' has an element that is not a \"string\": '$part'"
        name="${BASH_REMATCH[1]}"
        [[ "$name" =~ $KM_PKG_NAME_RE ]] \
            || km_die "$where: '$key' entry '$name' does not match $KM_PKG_NAME_RE"
        [[ ! -v seen[$name] ]] \
            || km_die "$where: '$key' lists '$name' twice"
        seen[$name]=1
        KM_MF_LIST+=("$name")
    done
}

# km_manifest_parse <file>: sets KM_MF_FILE, KM_MF_KIND, KM_MF_PACKAGES, KM_MF_RUN.
km_manifest_parse() {
    local file="$1" line key val lineno=0
    local -A seen=()
    KM_MF_FILE="$file" KM_MF_KIND=""
    KM_MF_PACKAGES=() KM_MF_RUN=()
    [[ -f "$file" && -r "$file" ]] \
        || km_die "$file is not a readable regular file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$(( lineno + 1 ))
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]]; then continue; fi
        if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
            km_die "$file:$lineno: TOML tables are not part of the manifest schema — every key is top-level"
        fi
        [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] \
            || km_die "$file:$lineno: not a 'key = value' line: $line"
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        [[ ! -v seen[$key] ]] \
            || km_die "$file:$lineno: duplicate key '$key'"
        seen[$key]=1
        case "$key" in
        kind)
            [[ "$val" =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]] \
                || km_die "$file:$lineno: 'kind' must be a \"string\""
            KM_MF_KIND="${BASH_REMATCH[1]}"
            ;;
        packages)
            km_manifest_list "$file:$lineno" "$key" "$val"
            KM_MF_PACKAGES=("${KM_MF_LIST[@]}")
            ;;
        run)
            km_manifest_list "$file:$lineno" "$key" "$val"
            KM_MF_RUN=("${KM_MF_LIST[@]}")
            ;;
        *)
            km_die "$file:$lineno: unknown key '$key'; a manifest has kind, packages and run only (ADR-043 §6)"
            ;;
        esac
    done < "$file"

    for key in kind packages run; do
        [[ -v seen[$key] ]] || km_die "$file: missing required key '$key' (ADR-043 §6)"
    done
    [[ -n "$KM_MF_KIND" ]] || km_die "$file: 'kind' is empty"
    local k ok=""
    for k in "${KM_LAYER_KINDS[@]}"; do [[ "$KM_MF_KIND" == "$k" ]] && ok=1; done
    [[ -n "$ok" ]] \
        || km_die "$file: kind='$KM_MF_KIND' is not one of {${KM_LAYER_KINDS[*]}} (ADR-043 §8)"
    (( ${#KM_MF_PACKAGES[@]} > 0 )) || km_die "$file: 'packages' is empty"
    (( ${#KM_MF_RUN[@]} > 0 )) || km_die "$file: 'run' is empty: a layer that may run nothing is refused (ADR-043 §6)"
}

# km_manifest_read <name> <t3-dir> <t1-dir>: resolves a layer name to its one
# manifest. An empty <t1-dir> means no T1 tier (the dev build from manifests/).
# A T1 name equal to a T3 name is refused: release names are reserved, and two
# sources for one name is the failure class ADR-043 §6 names. Sets KM_MF_TIER.
km_manifest_read() {
    local name="$1" t3="$2" t1="$3" f3 f1=""
    [[ "$name" =~ $KM_LAYER_NAME_RE ]] \
        || km_die "layer name '$name' does not match $KM_LAYER_NAME_RE"
    f3="$t3/$name.toml"
    [[ -n "$t1" ]] && f1="$t1/$name.toml"
    if [[ -n "$f1" ]] && [[ -e "$f1" || -L "$f1" ]]; then
        if [[ -e "$f3" || -L "$f3" ]]; then
            km_die "$f1: layer name '$name' is a release name ($f3). Release names are reserved; a T1 manifest may not take one (ADR-043 §6)."
        fi
        km_manifest_parse "$f1"
        KM_MF_TIER=T1
    elif [[ -e "$f3" || -L "$f3" ]]; then
        km_manifest_parse "$f3"
        KM_MF_TIER=T3
    else
        km_die "no manifest for layer '$name': neither $f3 nor ${f1:-<no T1 tier>} exists"
    fi
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
#
# km_run_subdir <sub> [mode]. The mode defaults to 0755, which the projection
# and the nic labels use: they are read by the unit's own user. The config
# disk's directory is 0700 (ADR-037 R32), because what it holds may carry a
# secret from networking arc step 5 on, and only root reads it. `install -d -m`
# also resets the mode of a directory that already exists, so a directory left
# with a wider mode by anything earlier is narrowed on the next call.
km_run_subdir() {
    # Two `local` statements, not one: in bash 5.3 the right-hand sides of a
    # single `local a=… b="$a"` are all expanded before any of the assignments
    # take effect, so `dir` would have been built from an empty `sub` and the
    # projection would have landed in /run/katmate/ instead of /run/katmate/vm/.
    # Caught by shellcheck SC2318 (see the note in the report: a static check
    # earning its keep on a path a behavioural test would also have found, but
    # later).
    local sub="$1"
    local mode="${2:-0755}"
    local dir="$KM_RUN_DIR/$sub"
    [[ "$mode" =~ ^0[0-7]{3}$ ]] \
        || km_usage "km_run_subdir: mode '$mode' is not an octal 0NNN"
    install -d -m "$mode" "$dir" \
        || km_die "cannot create $dir"
    printf '%s' "$dir"
}
