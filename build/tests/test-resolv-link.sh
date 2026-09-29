#!/usr/bin/env bash
# Katmate OS — tests for build/lib.sh resolv_link_install / resolv_link_check
# (ADR-038 §7) against temporary directory trees. Sources lib.sh only; needs no
# root, no LVM, no mount. This pre-tests the refusal logic of ADR-038 G3; it is
# not G3, which reads a frozen layer after a real build.
#
# Usage: build/tests/test-resolv-link.sh      exit 0 = every case passed

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build/lib.sh
source "$HERE/../lib.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
n=0

# A tree shaped like a mounted layer: etc/ and run/ directories.
tree() { mkdir -p "$T/$1/etc" "$T/$1/run"; echo "$T/$1"; }

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# expect_ok <name> <cmd...>: the command (run in a subshell, so die's exit
# stays there) must succeed.
expect_ok() {
  local name="$1"; shift; n=$((n + 1))
  local out
  if out="$( ("$@") 2>&1 )"; then pass "$name"; else fail "$name"; fi
  [[ -z "$out" ]] || echo "      output: ${out//$'\n'/ | }"
}

# expect_die <name> <substring> <cmd...>: the command must fail, and its
# message must contain the substring (so it failed for the stated reason).
expect_die() {
  local name="$1" sub="$2"; shift 2; n=$((n + 1))
  local out rc=0
  out="$( ("$@") 2>&1 )" || rc=$?
  if [[ $rc -ne 0 && "$out" == *"$sub"* ]]; then pass "$name"; else fail "$name (rc=$rc)"; fi
  echo "      output: ${out//$'\n'/ | }"
}

# expect_eq <name> <got> <want>
expect_eq() {
  n=$((n + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1"; fi
  echo "      got: [$2]  want: [$3]"
}

echo "==> 1. fresh tree, regular etc/resolv.conf -> install -> check passes"
d="$(tree fresh)"
echo "nameserver 192.0.2.53" >"$d/etc/resolv.conf"
expect_ok "install on a fresh tree" resolv_link_install "$d"
expect_ok "check passes after install" resolv_link_check "$d"
expect_eq "link target" "$(readlink "$d/etc/resolv.conf")" "../run/resolv.conf"
expect_eq "run/resolv.conf absent" "$(ls -A "$d/run")" ""

echo "==> 2. etc/resolv.conf a regular file -> check dies"
d="$(tree regular)"
echo "nameserver 192.0.2.53" >"$d/etc/resolv.conf"
expect_die "regular file refused" "is not the relative link" resolv_link_check "$d"

echo "==> 3. link present and run/resolv.conf present -> check dies"
d="$(tree leftover)"
ln -s ../run/resolv.conf "$d/etc/resolv.conf"
echo "nameserver 192.0.2.53" >"$d/run/resolv.conf"
expect_die "build-time copy left in run/ refused" "exists in the image" resolv_link_check "$d"

echo "==> 3b. link present and run/resolv.conf a dangling link -> check dies"
d="$(tree leftover-link)"
ln -s ../run/resolv.conf "$d/etc/resolv.conf"
ln -s nowhere "$d/run/resolv.conf"
expect_die "dangling link in run/ refused (the -L branch)" "exists in the image" resolv_link_check "$d"

echo "==> 4. absolute link -> check dies"
d="$(tree absolute)"
ln -s /run/resolv.conf "$d/etc/resolv.conf"
expect_die "absolute link refused" "is not the relative link" resolv_link_check "$d"

echo "==> 4b. etc/resolv.conf absent -> check dies"
d="$(tree absent)"
expect_die "absent refused" "is not the relative link" resolv_link_check "$d"

echo "==> 5. install on an already-linked tree -> idempotent"
d="$(tree relinked)"
ln -s ../run/resolv.conf "$d/etc/resolv.conf"
expect_ok "check passes before (the foundation carries the link)" resolv_link_check "$d"
# app-layer.sh's build-time copy: explicitly into the image's run/.
echo "nameserver 192.0.2.53" >"$T/host-resolv.conf"
cp "$T/host-resolv.conf" "$d/run/resolv.conf"
expect_eq "the chroot-side view reads the copy through the link" \
  "$(cat "$d/etc/resolv.conf")" "nameserver 192.0.2.53"
expect_ok "install (1st)" resolv_link_install "$d"
expect_ok "install (2nd)" resolv_link_install "$d"
expect_ok "check passes after two installs" resolv_link_check "$d"
expect_eq "link target unchanged" "$(readlink "$d/etc/resolv.conf")" "../run/resolv.conf"
expect_eq "copy removed from run/" "$(ls -A "$d/run")" ""

echo "==> 6. host-side cp through the relative link (GNU coreutils, measured 9.11)"
# 6a: with the link dangling -- the state of every built layer -- cp refuses to
# write through it. This is why app-layer.sh copies explicitly into run/.
d="$(tree through)"
ln -s ../run/resolv.conf "$d/etc/resolv.conf"
expect_die "cp through the dangling relative link is refused" \
  "dangling symlink" cp "$T/host-resolv.conf" "$d/etc/resolv.conf"
expect_eq "nothing landed in run/" "$(ls -A "$d/run")" ""
# 6b: with the target present, cp through the relative link lands inside the
# tree, not on this machine -- the defence the relative form provides.
echo "old" >"$d/run/resolv.conf"
expect_ok "cp through the relative link, target present" \
  cp "$T/host-resolv.conf" "$d/etc/resolv.conf"
expect_eq "it landed in the tree's run/" "$(cat "$d/run/resolv.conf")" "nameserver 192.0.2.53"
expect_eq "etc/resolv.conf is still the link" "$(readlink "$d/etc/resolv.conf")" "../run/resolv.conf"
# (The absolute-link counterpart would write this machine's /run/resolv.conf
#  when it exists; it is deliberately not run.)

echo "==> $n cases, $fails failed: $([[ $fails -eq 0 ]] && echo PASS || echo FAIL)"
[[ $fails -eq 0 ]]
