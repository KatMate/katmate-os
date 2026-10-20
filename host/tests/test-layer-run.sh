#!/usr/bin/env bash
# KatMate OS — tests for the layer-manifest data model (ADR-043 §5–7): the
# manifest reader in katmate-lib.sh, the RUN and CID checks in katmate-launch,
# the layer checks and --faces in katmate-generate-env, the layer checks in
# katmate-check-image and katmate-activate-lvs, and
# installer/gen-desktop-entries. Needs no root, no LVM and no VM.
#
# The T4 executables run from copies whose path constants (and the uid guards)
# are rewritten to a fixture tree; every rewrite must match, or the harness
# stops. What this cannot reach: app-layer.sh (root, LVM, mount), vm-agent and
# katmate-alloc's pool (cargo test, agent/), and katmate-launch's routed start
# (root, /run/katmate, a netVM).
#
# Usage: host/tests/test-layer-run.sh      exit 0 = every case passed

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K="$ROOT/host/usr/lib/katmate"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
n=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; [[ -z "${2:-}" ]] || printf '      %s\n' "$2"; fails=$((fails + 1)); }

# expect_ok <name> <pattern|""> <cmd...>: exit 0, and the output matches.
expect_ok() {
  local name="$1" pat="$2" out; shift 2; n=$((n + 1))
  if out="$( ("$@") 2>&1 )" && [[ -z "$pat" || "$out" == *"$pat"* ]]; then
    pass "$name"
  else
    fail "$name" "$(tail -n 2 <<<"$out")"
  fi
}

# expect_fail <name> <code> <pattern> <cmd...>: that exit code and the message.
expect_fail() {
  local name="$1" code="$2" pat="$3" out rc; shift 3; n=$((n + 1))
  rc=0; out="$( ("$@") 2>&1 )" || rc=$?
  if [[ "$rc" == "$code" && "$out" == *"$pat"* ]]; then
    pass "$name"
  else
    fail "$name" "rc=$rc: $(tail -n 2 <<<"$out")"
  fi
}

die() { echo "HARNESS: $*" >&2; exit 2; }

# rw <file> <from> <to>: literal replacement that must match at least once.
rw() {
  local f="$1"
  grep -qF -- "$2" "$f" || die "rewrite target absent in $f: $2"
  A="$2" B="$3" perl -0pi -e 's/\Q$ENV{A}\E/$ENV{B}/g' "$f"
  ! grep -qF -- "$2" "$f" || die "rewrite left a match in $f: $2"
}

# katmate-launch's CID check runs the real allocator.
cargo build -q -p katmate-alloc --manifest-path "$ROOT/agent/Cargo.toml" || die "cargo build -p katmate-alloc failed"
ALLOC_BIN="$ROOT/agent/target/debug/katmate-alloc"

# --- the fixture tree --------------------------------------------------------
mkdir -p "$T/etc/katmate/vm" "$T/etc/katmate/layer" "$T/usr/lib/katmate/layer" \
         "$T/var/lib/katmate/kernels" "$T/var/lib/katmate/instances" \
         "$T/run" "$T/lib" "$T/bin" "$T/attr" "$T/dev/vg0"

cp "$K/katmate-lib.sh" "$T/lib/katmate-lib.sh"
rw "$T/lib/katmate-lib.sh" 'KM_ETC_VM="/etc/katmate/vm"' "KM_ETC_VM=\"$T/etc/katmate/vm\""
rw "$T/lib/katmate-lib.sh" 'KM_STATE_DIR="/var/lib/katmate"' "KM_STATE_DIR=\"$T/var/lib/katmate\""
rw "$T/lib/katmate-lib.sh" 'KM_RUN_DIR="/run/katmate"' "KM_RUN_DIR=\"$T/run/katmate\""

for x in katmate-launch katmate-generate-env katmate-check-image katmate-activate-lvs katmate-t1-read; do
  cp "$K/$x" "$T/lib/$x"
  rw "$T/lib/$x" 'source /usr/lib/katmate/katmate-lib.sh' "source $T/lib/katmate-lib.sh"
done
rw "$T/lib/katmate-launch" 'if (( EUID != 0 )); then' 'if false; then'
rw "$T/lib/katmate-launch" 'logger -t katmate-launch' 'true'
rw "$T/lib/katmate-launch" 'export PATH=/usr/bin' "export PATH=$T/bin:/usr/bin"
rw "$T/lib/katmate-launch" 'PING_CLIENT=/usr/lib/katmate/ping-client' "PING_CLIENT=$T/bin/ping-client"
rw "$T/lib/katmate-launch" 'ALLOC=/usr/lib/katmate/katmate-alloc' "ALLOC=$ALLOC_BIN"
rw "$T/lib/katmate-launch" 'GENERATE_ENV=/usr/lib/katmate/katmate-generate-env' "GENERATE_ENV=$T/lib/katmate-generate-env"
rw "$T/lib/katmate-generate-env" '(( EUID == 0 ))' '(( 1 ))'
rw "$T/lib/katmate-activate-lvs" '(( EUID == 0 ))' '(( 1 ))'
# shellcheck disable=SC2016  # literal source text
rw "$T/lib/katmate-activate-lvs" 'node="/dev/${spec}"' "node=\"$T/dev/\${spec}\""

# Stubs. systemctl reports every unit `activating`, so katmate-launch stops
# right after its checks with "in transition"; ping-client must never be run.
printf '#!/bin/bash\necho activating\n' >"$T/bin/systemctl"
printf '#!/bin/bash\necho "ping-client called: $*" >>%q\nexit 1\n' "$T/ping-client.log" >"$T/bin/ping-client"
printf '#!/bin/bash\nexit 0\n' >"$T/bin/lvchange"
# shellcheck disable=SC2016  # the stub's own text
printf '#!/bin/bash\nspec="${@: -1}"\ncat %q/"${spec//\\//_}"\n' "$T/attr" >"$T/bin/lvs"
chmod +x "$T/bin/"*

for f in "$ROOT"/installer/t1/*.toml.in; do
  b="$(basename "$f" .toml.in)"
  cp "$f" "$T/etc/katmate/vm/$b.toml"
done

FB=2026-10-06T12:24:57Z
printf 'KATMATE_META_VERSION=1\nBUILD_DATE=%s\nFOUNDATION_LV=vg0/vm_tpl_foundation\nKERNEL_VERSION=6.12.87\n' "$FB" \
  >"$T/var/lib/katmate/foundation.meta"
# app_meta <layer> <RUN> [<KIND>] [<BASE_BUILT>]; an empty RUN omits the key.
app_meta() {
  local f="$T/var/lib/katmate/app-$1.meta"
  {
    printf 'KATMATE_META_VERSION=1\nAPP_TYPE=%s\nAPP_LV=vg0/vm_app_%s\nAPP_ROOTFSTYPE=ext4\n' "$1" "$1"
    printf 'BASE_LV=vg0/vm_tpl_foundation\nBASE_BUILT=%s\nKERNEL_VERSION=6.12.87\n' "${4:-$FB}"
    printf 'KIND=%s\n' "${3:-debian-manifest}"
    [[ -z "$2" ]] || printf 'RUN=%s\n' "$2"
  } >"$f"
}
std_metas() {
  app_meta web "firefox-esr foot pcmanfm"
  app_meta office "libreoffice foot pcmanfm"
  app_meta vault "keepassxc foot pcmanfm"
}
std_metas
: >"$T/var/lib/katmate/kernels/vmlinuz-katmate-microvm-amd64-6.12.87"
for i in app_web app_personal app_work app_vault app_sandbox; do
  : >"$T/var/lib/katmate/instances/$i.qcow2"
done
for lv in vm_tpl_foundation vm_app_web vm_app_office vm_app_vault vm_app_vault_home; do
  : >"$T/dev/vg0/$lv"
done
echo 'Vri-a-tz--' >"$T/attr/vg0_vm_tpl_foundation"
echo 'Vri-a-tz-k' >"$T/attr/vg0_vm_app_vault"
echo 'Vwi-a-tz--' >"$T/attr/vg0_vm_app_vault_home"

# set_manifest <instance> <layer>: rewrite one T1 file's manifest line.
set_manifest() { sed -i "s/^manifest = \".*\"/manifest = \"$2\"/" "$T/etc/katmate/vm/$1.toml"; }

# --- 1. the manifest reader --------------------------------------------------
# mf <name> <t3> <t1>: read through the real katmate-lib.sh and print the result.
mf() {
  # shellcheck source=host/usr/lib/katmate/katmate-lib.sh
  source "$K/katmate-lib.sh"
  km_manifest_read "$1" "$2" "$3"
  printf 'tier=%s kind=%s packages=%s run=%s\n' "$KM_MF_TIER" "$KM_MF_KIND" "${KM_MF_PACKAGES[*]}" "${KM_MF_RUN[*]}"
}
mfile() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${@:2}" >"$1"; }
M3="$T/usr/lib/katmate/layer"
M1="$T/etc/katmate/layer"
OKK='kind = "debian-manifest"'
OKP='packages = ["foot", "pcmanfm"]'
OKR='run = ["foot"]'

# The converted release manifests carry the packages of the .list files they
# replace (538f112) and the run sets of katmate-launch's APPS table there.
declare -A WANT_RUN=([web]="firefox-esr foot pcmanfm" [office]="libreoffice foot pcmanfm" [vault]="keepassxc foot pcmanfm")
for l in web office vault; do
  if git -C "$ROOT" cat-file -e "538f112:manifests/$l.list" 2>/dev/null; then
    want_p="$(git -C "$ROOT" show "538f112:manifests/$l.list" | grep -vE '^[[:space:]]*(#|$)' | tr '\n' ' ')"
    want_p="${want_p% }"
    expect_ok "repo manifest $l: packages as $l.list, run as APPS" \
      "tier=T3 kind=debian-manifest packages=$want_p run=${WANT_RUN[$l]}" mf "$l" "$ROOT/manifests" ""
  else
    echo "SKIP  repo manifest $l: 538f112 is not in this clone"
  fi
done
expect_ok "repo manifest web resolves with an empty T1 tier present" "tier=T3" mf web "$ROOT/manifests" "$M1"

mfile "$M3/rel.toml" "$OKK" "$OKP" "$OKR"
mfile "$M1/rel.toml" "$OKK" "$OKP" "$OKR"
expect_fail "T1/T3 name clash is refused" 1 "is a release name" mf rel "$M3" "$M1"
rm -f "$M1/rel.toml"
expect_ok "T3 only resolves to T3" "tier=T3" mf rel "$M3" "$M1"
mfile "$M1/mine.toml" "$OKK" "$OKP" "$OKR"
expect_ok "T1 only resolves to T1" "tier=T1 kind=debian-manifest packages=foot pcmanfm run=foot" mf mine "$M3" "$M1"
expect_fail "unknown layer is refused" 1 "no manifest for layer 'nosuch'" mf nosuch "$M3" "$M1"
expect_fail "bad layer name is refused" 1 "does not match" mf 'Web' "$M3" "$M1"

# case <name> <expected message> <manifest lines...>
case_bad() {
  local name="$1" msg="$2"; shift 2
  mfile "$M1/bad.toml" "$@"
  expect_fail "$name" 1 "$msg" mf bad "$M3" "$M1"
}
case_bad "bad package name"      "does not match"          "$OKK" 'packages = ["foot", "Bad_Name"]' "$OKR"
case_bad "bad run name"          "does not match"          "$OKK" "$OKP" 'run = ["../foot"]'
case_bad "empty run"             "'run' is empty"          "$OKK" "$OKP" 'run = []'
case_bad "empty packages"        "'packages' is empty"     "$OKK" 'packages = [ ]' "$OKR"
case_bad "multi-line array"      "Multi-line arrays"       "$OKK" 'packages = [' '  "foot",' ']' "$OKR"
case_bad "duplicate entry"       "lists 'foot' twice"      "$OKK" 'packages = ["foot", "foot"]' "$OKR"
case_bad "trailing comma"        "ends with a comma"       "$OKK" 'packages = ["foot",]' "$OKR"
case_bad "unquoted element"      "not a \"string\""        "$OKK" 'packages = [foot]' "$OKR"
case_bad "missing run"           "missing required key 'run'"  "$OKK" "$OKP"
case_bad "missing kind"          "missing required key 'kind'" "$OKP" "$OKR"
case_bad "unknown key"           "unknown key 'name'"      "$OKK" "$OKP" "$OKR" 'name = "x"'
case_bad "duplicate key"         "duplicate key 'run'"     "$OKK" "$OKP" "$OKR" "$OKR"
case_bad "unknown kind"          "is not one of"           'kind = "installer"' "$OKP" "$OKR"
case_bad "TOML table"            "TOML tables"             "[layer]" "$OKK" "$OKP" "$OKR"
case_bad "string instead of array" "must be an array"      "$OKK" 'packages = "foot pcmanfm"' "$OKR"
mfile "$M1/cmt.toml" "# a comment" "" "$OKK  # trailing" 'packages = ["foot", "pcmanfm"]   # trailing' "$OKR"
expect_ok "comments and blank lines are accepted" "packages=foot pcmanfm run=foot" mf cmt "$M3" "$M1"

# --- 2. katmate-launch: the RUN check ----------------------------------------
L() { "$T/lib/katmate-launch" "$@"; }
expect_fail "launch: a listed app passes the RUN check" 1 "refusing to act on a unit in transition" L app_web firefox-esr
expect_fail "launch: an unlisted app is refused with a reason" 1 "app 'libreoffice' is not in the RUN list of layer 'web'" L app_web libreoffice
expect_fail "launch: offline instance, unlisted app refused" 1 "app 'firefox-esr' is not in the RUN list of layer 'vault'" L app_vault firefox-esr
expect_fail "launch: app name outside the pattern refused" 1 "does not match" L app_web 'foot;id'
expect_fail "launch: instance without a T1 file refused" 1 "no T1 properties for instance 'app_other'" L app_other foot
expect_ok "launch --cid-check: the shipped T1 set passes" "6 T1 files, every CID unique" L --cid-check
cp "$T/etc/katmate/vm/app_web.toml" "$T/etc/katmate/vm/app_dup.toml"
expect_fail "launch: a duplicate CID in the T1 tree refuses every launch" 1 "cid 21 is carried by more than one T1 file: app_dup app_web" L app_personal foot
expect_fail "launch --cid-check: the duplicate is named" 1 "cid 21 is carried by more than one T1 file" L --cid-check
rm "$T/etc/katmate/vm/app_dup.toml"
sed -i "s/^cid = 25\$/cid = 30/" "$T/etc/katmate/vm/app_sandbox.toml"
expect_fail "launch: a reserved CID in T1 is refused" 1 "app_sandbox: cid 30 is reserved for gw_w2" L app_web foot
sed -i "s/^cid = 30\$/cid = 25/" "$T/etc/katmate/vm/app_sandbox.toml"
expect_ok "launch --cid-check: restored" "every CID unique" L --cid-check
app_meta web ""
expect_fail "launch: a meta without RUN refuses every app" 1 "records no RUN" L app_web foot
std_metas
set_manifest app_web nosuch
expect_fail "launch: unknown layer refused" 1 "T2 image metadata not found" L app_web foot
set_manifest app_web web
n=$((n + 1))
if [[ -e "$T/ping-client.log" ]]; then fail "launch: ping-client was never called" "$(cat "$T/ping-client.log")"; else pass "launch: ping-client was never called"; fi

# --- 3. katmate-generate-env -------------------------------------------------
G() { "$T/lib/katmate-generate-env" katmate-app-offline app_vault; }
expect_ok "generate-env: app_vault on a valid layer" "" G
n=$((n + 1))
if grep -q '^KM_HOME_DEV=' "$T/run/katmate/vm/app_vault.env" 2>/dev/null; then pass "generate-env: projection written"; else fail "generate-env: projection written"; fi
set_manifest app_vault nosuch
expect_fail "generate-env: unknown layer refused" 1 "names no built layer" G
set_manifest app_vault 'no-such'
expect_fail "generate-env: manifest outside the layer pattern refused" 1 "does not match the layer-name pattern" G
set_manifest app_vault vault
app_meta vault "keepassxc foot pcmanfm" installer
expect_fail "generate-env: KIND not valid for class=app refused" 1 "is not valid for class=app" G
app_meta vault ""
expect_fail "generate-env: meta without RUN refused" 1 "records no RUN" G
app_meta vault "keepassxc"
sed -i '/^KIND=/d' "$T/var/lib/katmate/app-vault.meta"
expect_fail "generate-env: meta without KIND refused" 1 "records no KIND" G
app_meta vault "keepassxc ../x"
expect_fail "generate-env: RUN entry outside the pattern refused" 1 "RUN entry '../x'" G
std_metas

F() { "$T/lib/katmate-generate-env" --faces "$@"; }
expect_ok "generate-env --faces: slot 03" "KM_SLOT_MAC=52:54:01:00:00:03
KM_GUEST_ADDR=10.100.1.19" F netvm 03
expect_ok "generate-env --faces: slot 0f" "KM_SLOT_MAC=52:54:01:00:00:0f
KM_GUEST_ADDR=10.100.1.31" F netvm 0f
expect_fail "generate-env --faces: a slot outside the pool refused" 1 "slot '10' is not one of" F netvm 10
expect_fail "generate-env --faces: a bad netVM name refused" 1 "is not [a-z]" F ../x 01
expect_fail "generate-env --faces: usage" 2 "--faces <netvm> <slot>" F netvm

# --- 4. katmate-check-image: the stale layer ---------------------------------
C() { "$T/lib/katmate-check-image" app_vault; }
expect_ok "check-image: current layer" "the layer's BASE_BUILT matches" C
app_meta vault "keepassxc foot pcmanfm" "" 2026-09-01T00:00:00Z
expect_fail "check-image: stale layer refused" 1 "layer 'vault' is stale" C
std_metas
set_manifest app_vault nosuch
expect_fail "check-image: unknown layer refused" 1 "names no built layer" C
set_manifest app_vault vault

# --- 5. katmate-activate-lvs: the frozen layer -------------------------------
A() { PATH="$T/bin:$PATH" "$T/lib/katmate-activate-lvs" app_vault; }
expect_ok "activate-lvs: frozen layer" "block devices ready" A
echo 'Vwi-a-tz--' >"$T/attr/vg0_vm_app_vault"
expect_fail "activate-lvs: writable layer refused" 1 "app layer LV: vg0/vm_app_vault has lv_attr 'Vwi-a-tz--', not read-only" A
echo 'Vri-a-tz-k' >"$T/attr/vg0_vm_app_vault"
echo 'Vwi-a-tz--' >"$T/attr/vg0_vm_tpl_foundation"
expect_fail "activate-lvs: writable foundation refused" 1 "foundation LV: vg0/vm_tpl_foundation has lv_attr 'Vwi-a-tz--', not read-only" A
echo 'Vri-a-tz--' >"$T/attr/vg0_vm_tpl_foundation"

# --- 6. installer/gen-desktop-entries ----------------------------------------
D() { rm -rf "$T/apps"; "$ROOT/installer/gen-desktop-entries" "$T/etc/katmate/vm" "$T/var/lib/katmate" "$T/apps"; }
expect_ok "gen-desktop-entries: 15 entries for 5 instances" "15 entries for 5 instances" D
# cu2's sixteen files, indexed in instance name order since cu3 (the T1 tree,
# not a list in katmate-launch).
want="km-00-app_personal-firefox-esr km-00-app_personal-foot km-00-app_personal-pcmanfm km-01-app_sandbox-firefox-esr km-01-app_sandbox-foot km-01-app_sandbox-pcmanfm km-02-app_vault-foot km-02-app_vault-keepassxc km-02-app_vault-pcmanfm km-03-app_web-firefox-esr km-03-app_web-foot km-03-app_web-pcmanfm km-04-app_work-foot km-04-app_work-libreoffice km-04-app_work-pcmanfm km-99-appvms"
have="$(cd "$T/apps" && ls | sed 's/\.desktop$//' | LC_ALL=C sort | tr '\n' ' ')"
n=$((n + 1))
if [[ "${have% }" == "$want" ]]; then pass "gen-desktop-entries: 16 files in instance name order (cardinality 16)"; else fail "gen-desktop-entries: 16 files in instance name order" "$have"; fi
app_meta web "firefox-esr gimp"
D >/dev/null
n=$((n + 1))
if grep -qx 'Name=\[web\] gimp' "$T/apps/km-03-app_web-gimp.desktop" 2>/dev/null; then pass "gen-desktop-entries: unlabelled binary shown by its name"; else fail "gen-desktop-entries: unlabelled binary shown by its name"; fi
app_meta web ""
expect_fail "gen-desktop-entries: meta without RUN refused" 1 "records no RUN" D
std_metas
set_manifest app_work nosuch
expect_fail "gen-desktop-entries: unknown layer refused, no partial set" 1 "T2 image metadata not found" D
n=$((n + 1))
if [[ ! -e "$T/apps" ]]; then pass "gen-desktop-entries: nothing written on refusal"; else fail "gen-desktop-entries: nothing written on refusal"; fi
set_manifest app_work office

# --- 7. cu4: katmate-t1-read and the --layer modes ----------------------------
R() { "$T/lib/katmate-t1-read" "$@"; }
expect_ok "t1-read: app_vault, nine keys sorted" "cid=24
class=app
disposable=false
identity=false
manifest=vault
mem=2G
netvm=
persistence=persistent
vcpus=2" R app_vault
n=$((n + 1))
if [[ "$(R app_vault | wc -l)" == 9 ]]; then pass "t1-read: app_vault prints exactly 9 lines"; else fail "t1-read: app_vault prints exactly 9 lines" "$(R app_vault 2>&1)"; fi
expect_ok "t1-read --pairs: six T1 files" "app_personal 22
app_sandbox 25
app_vault 24
app_web 21
app_work 23
netvm 3" R --pairs
expect_fail "t1-read: absent instance refused" 1 "no T1 properties for instance 'nosuch'" R nosuch
expect_fail "t1-read: bad name refused" 1 "is not [a-z]" R ../x
expect_fail "t1-read: usage" 2 "USAGE" R
expect_fail "t1-read: two arguments" 2 "USAGE" R app_web app_vault
printf 'class = "app"\nclass = "app"\n' >"$T/etc/katmate/vm/dup.toml"
expect_fail "t1-read --pairs: an unreadable T1 file stops the list" 1 "duplicate key 'class'" R --pairs
rm "$T/etc/katmate/vm/dup.toml"

CL() { "$T/lib/katmate-check-image" --layer "$@"; }
out="$(CL vault 2>&1)" || true
n=$((n + 1))
if [[ "$(tail -n 1 <<<"$out")" == "APP_LV=vg0/vm_app_vault" ]]; then pass "check-image --layer: last line APP_LV"; else fail "check-image --layer: last line APP_LV" "$(tail -n 2 <<<"$out")"; fi
app_meta vault "keepassxc foot pcmanfm" "" 2026-09-01T00:00:00Z
expect_fail "check-image --layer: stale layer refused" 1 "layer 'vault' is stale" CL vault
std_metas
expect_fail "check-image --layer: unknown layer refused" 1 "layer 'nosuch' names no built layer" CL nosuch
expect_fail "check-image --layer: bad layer name refused" 1 "layer '../x' does not match" CL ../x
expect_fail "check-image --layer: usage" 2 "USAGE" CL
mv "$T/var/lib/katmate/kernels/vmlinuz-katmate-microvm-amd64-6.12.87" "$T/k.away"
expect_fail "check-image --layer: missing kernel refused" 1 "kernel not found" CL web
mv "$T/k.away" "$T/var/lib/katmate/kernels/vmlinuz-katmate-microvm-amd64-6.12.87"
# The instance mode still checks the delta, now after the layer.
mv "$T/var/lib/katmate/instances/app_vault.qcow2" "$T/d.away"
expect_fail "check-image: missing delta refused" 1 "instance delta not found" C
mv "$T/d.away" "$T/var/lib/katmate/instances/app_vault.qcow2"

AL() { PATH="$T/bin:$PATH" "$T/lib/katmate-activate-lvs" --layer "$@"; }
expect_ok "activate-lvs --layer: frozen chain" "block devices ready for layer 'vault'" AL vault
echo 'Vwi-a-tz--' >"$T/attr/vg0_vm_app_vault"
expect_fail "activate-lvs --layer: writable layer refused" 1 "app layer LV: vg0/vm_app_vault has lv_attr 'Vwi-a-tz--', not read-only" AL vault
echo 'Vri-a-tz-k' >"$T/attr/vg0_vm_app_vault"
expect_fail "activate-lvs --layer: bad layer name refused" 1 "does not match the layer-name pattern" AL ../x
expect_fail "activate-lvs --layer: usage" 2 "USAGE" AL

echo "$((n - fails))/$n passed"
(( fails == 0 ))
