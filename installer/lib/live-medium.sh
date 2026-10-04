# shellcheck shell=bash
# ---------------------------------------------------------------------------
# KatMate OS — live boot medium resolution (sourced, not executed)
# ---------------------------------------------------------------------------
#
# One implementation, two callers: preflight.sh excludes the medium from the
# install candidates, and install.sh refuses it as a target. Read-only: it
# reads the command line it is given, /dev/disk links and lsblk, and writes
# nothing. It prints nothing either; the caller prints LM_LINES.
#
# Methods, in the archiso hook's own order (mkinitcpio-archiso hooks/archiso,
# read 2026-10-04): an explicit archisodevice=; archisosearchuuid= resolved as
# UUID=<uuid>; archisolabel= as /dev/disk/by-label/<label>. The hook's mount,
# /run/archiso/bootmnt, is a secondary source only: with copytoram (default
# auto) the hook unmounts it after copying the image to RAM.
#
# Needs: lsblk, readlink. findmnt is optional (bootmnt is then not consulted).
# ---------------------------------------------------------------------------

# lm_disk_of <path>: the disk a block device (or a link to one) belongs to.
lm_disk_of() {
  local dev pk
  dev="$(readlink -f -- "$1" 2>/dev/null || true)"
  [[ -n "$dev" && -b "$dev" ]] || return 1
  pk="$(lsblk -n -d -o PKNAME "$dev" 2>/dev/null | head -n 1 || true)"
  pk="${pk//[[:space:]]/}"
  if [[ -z "$pk" ]]; then
    pk="$(lsblk -n -d -o NAME "$dev" 2>/dev/null | head -n 1 || true)"
    pk="${pk//[[:space:]]/}"
  fi
  [[ -n "$pk" ]] || return 1
  printf '%s' "$pk"
}

# lm_resolve <kernel command line>
#   LM_ARCHISO  1 if an archiso parameter is present, else 0
#   LM_PARAMS   the archiso parameters seen (copytoram= included)
#   LM_DISK     the first disk a method resolved to, or empty
#   LM_SEEN     every distinct disk any method resolved to, space-separated
#   LM_LINES    the evidence, one line per element, in order, unindented
# The LM_* outputs are read by the callers, which a check of this file alone
# does not see.
# shellcheck disable=SC2034
lm_resolve() {
  local - tok a_uuid="" a_label="" a_dev="" src="" c how path d
  local -a cands=()
  LM_ARCHISO=0 LM_PARAMS="" LM_DISK="" LM_SEEN=""
  LM_LINES=()

  set -f
  for tok in $1; do
    case "$tok" in
      archisosearchuuid=*) a_uuid="${tok#*=}";  LM_PARAMS+="$tok " ;;
      archisolabel=*)      a_label="${tok#*=}"; LM_PARAMS+="$tok " ;;
      archisodevice=*)     a_dev="${tok#*=}";   LM_PARAMS+="$tok " ;;
      copytoram=*)         LM_PARAMS+="$tok " ;;
    esac
  done
  set +f
  LM_PARAMS="${LM_PARAMS% }"

  if [[ "$LM_PARAMS" != *archiso* ]]; then
    LM_LINES+=("live boot medium: not an archiso live boot: no boot medium to exclude")
    return 0
  fi
  LM_ARCHISO=1
  LM_LINES+=("archiso parameters on the command line: $LM_PARAMS")

  [[ -n "$a_dev" ]]   && cands+=("archisodevice|$a_dev")
  [[ -n "$a_uuid" ]]  && cands+=("archisosearchuuid|/dev/disk/by-uuid/$a_uuid")
  [[ -n "$a_label" ]] && cands+=("archisolabel|/dev/disk/by-label/$a_label")
  if command -v findmnt >/dev/null 2>&1; then
    src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  fi
  if [[ -n "$src" ]]; then
    cands+=("/run/archiso/bootmnt|$src")
  elif [[ -d /run/archiso/copytoram ]]; then
    LM_LINES+=("/run/archiso/bootmnt: not mounted; /run/archiso/copytoram exists, so the hook copied the image to RAM and unmounted the boot medium (copytoram)")
  else
    LM_LINES+=("/run/archiso/bootmnt: not mounted; no /run/archiso/copytoram, so why is not determinable here")
  fi

  for c in "${cands[@]}"; do
    how="${c%%|*}"; path="${c#*|}"
    if d="$(lm_disk_of "$path")"; then
      LM_LINES+=("$how: $path -> $(readlink -f -- "$path") -> disk $d")
      [[ " $LM_SEEN " == *" $d "* ]] || LM_SEEN+="$d "
      [[ -n "$LM_DISK" ]] || LM_DISK="$d"
    else
      LM_LINES+=("$how: $path does not resolve to a block device")
    fi
  done
  LM_SEEN="${LM_SEEN% }"
  return 0
}
