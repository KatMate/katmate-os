#!/usr/bin/env bash
# Katmate OS — build init/tests/test-net.c against the production
# init/katmate-init.c (R88: included with -DKATMATE_INIT_NO_MAIN, compiled with
# foundation.sh's flags plus -g) and run it. Nothing here is baked into an image.
#
# Usage:
#   init/tests/run.sh           parse, inet, select, resolver, ack — unprivileged
#   init/tests/run.sh --apply   the apply group: root, in a private network
#                               namespace, never the host's:
#                                 sudo -n unshare -n init/tests/run.sh --apply
#
# Exit 0 = every case that ran passed.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

CFLAGS=(-static -O2 -Wall -Wextra -std=gnu11 -g -DKATMATE_INIT_NO_MAIN)
echo "==> gcc ${CFLAGS[*]} -o test-net init/tests/test-net.c"
gcc "${CFLAGS[@]}" -o "$T/test-net" "$HERE/test-net.c"

if [[ "${1:-}" != "--apply" ]]; then
  [[ $EUID -ne 0 ]] || die "run the unprivileged groups as a normal user (the ack group needs the kernel to refuse it)"
  rc=0
  echo "==> parse";    "$T/test-net" parse || rc=1
  echo "==> inet (a reading, no verdict)"; "$T/test-net" inet
  echo "==> select";   mkdir "$T/sel"; "$T/test-net" select "$T/sel" || rc=1
  echo "==> resolver"; mkdir "$T/res"; "$T/test-net" resolver "$T/res" || rc=1
  echo "==> ack";      "$T/test-net" ack || rc=1
  echo "==> apply: not run in this mode (needs: sudo -n unshare -n $0 --apply)"
  echo "==> overall: $([[ $rc -eq 0 ]] && echo PASS || echo FAIL)"
  exit "$rc"
fi

# ---- apply: the guard lives here, not in the instructions -------------------
# As root in the host's namespace this group would put 10.100.1.17/32 and a
# default route on the host. Refuse unless this namespace is not PID 1's.
[[ $EUID -eq 0 ]] || die "--apply needs root (it creates a link and programs it)"
self_ns="$(readlink /proc/self/ns/net)"
init_ns="$(readlink /proc/1/ns/net)"
echo "==> netns: self $self_ns, pid 1 $init_ns"
[[ -n "$self_ns" && -n "$init_ns" && "$self_ns" != "$init_ns" ]] \
  || die "refusing: this is PID 1's network namespace — run under unshare -n"

echo "==> before: ip link show (the fresh namespace; lo is expected DOWN)"
ip link show | cat

if ip link add km0 type dummy 2>"$T/dummy.err"; then
  kind=dummy
else
  echo "dummy unavailable: $(cat "$T/dummy.err")"
  ip link add km0 type veth peer name km1
  ip link set km1 up                 # else km0 has no carrier and routes read linkdown
  kind=veth
fi
echo "==> test link km0: $kind"

rc=0
echo "==> apply"; mkdir "$T/app"; "$T/test-net" apply "$T/app" || rc=1

verdict() {  # name, got, want
  if [[ "$2" == "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi
  echo "      got:  [$2]"
  echo "      want: [$3]"
}

addr="$(ip -4 -o addr show dev km0 | awk '{print $4}')"
# iproute2 7.2.0 ends each route line with a space ("... onlink "), so the
# verdict compares each line with trailing whitespace stripped; the raw
# listing below is printed untrimmed (s4b-impl-B § P1).
route="$(ip -4 route show | sed 's/[[:space:]]*$//')"
lo_flags="$(ip link show lo | sed -n '1s/^[0-9]*: lo: \(<[^>]*>\).*/\1/p')"
resolv="$(cat "$T/app/resolv.conf" 2>&1 || true)"

echo "==> read-back, raw"
ip -4 addr show | cat
ip -4 route show | cat
ip link show lo | cat
stat -c '%A %s %n' "$T/app/resolv.conf" 2>&1 | cat

echo "==> read-back, verdicts"
verdict "exactly 10.100.1.17/32 on km0" "$addr" "10.100.1.17/32"
verdict "main table is the one on-link default" "$route" "default via 10.100.1.1 dev km0 onlink"
verdict "lo UP" "$lo_flags" "<LOOPBACK,UP,LOWER_UP>"
verdict "resolver file" "$resolv" "nameserver 10.100.1.1"

echo "==> overall: $([[ $rc -eq 0 ]] && echo PASS || echo FAIL)"
exit "$rc"
