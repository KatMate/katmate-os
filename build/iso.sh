#!/usr/bin/env bash
# build/iso.sh — the KatMate install medium (iso/; archiso, derived from releng)
#
# Usage (on the build host, as root, from the synced tree):
#   sudo build/iso.sh --archive <dir>/katmate-os-<tag>.tar.gz --out <empty dir>
#
# The medium is defined by the archive alone: its iso/ profile, its
# installer/lib/packages.sh, and the archive itself, which the medium carries
# for katmate-install to unpack. For a release that is the `git archive` of the
# release tag; this tree only supplies the script.
#
# The offline repository is the host package set with its full dependency
# closure, resolved against an EMPTY package database (the target is empty; the
# build host's installed set must not prune the closure), together with the
# core and extra databases it was resolved against. Those databases carry the
# packages' signatures, so no repo-add and no detached .sig files are needed.
# The guest images are not on the medium (operator ruling, 2026-10-16).
#
# iso.env records ISO_VALID_UNTIL, the earliest expiry among the keys that sign
# the repository; install.sh refuses the medium from that date on, and this
# script refuses to build one with fewer than 60 days left.
#
# Output in --out: the ISO and ISO.sha256; work/ keeps the profile and logs.

set -euo pipefail
# shellcheck source=build/lib.sh
source "$(dirname "$(readlink -f -- "$0")")/lib.sh"

usage() { echo "Usage: $0 --archive <katmate-os-<tag>.tar.gz> --out <empty dir>" >&2; exit 2; }

ARCHIVE="" OUT=""
while (( $# )); do
  case "$1" in
    --archive) ARCHIVE="${2:-}"; shift 2 || usage ;;
    --out)     OUT="${2:-}";     shift 2 || usage ;;
    *) usage ;;
  esac
done
[[ -n "$ARCHIVE" && -n "$OUT" ]] || usage
require_root

for c in mkarchiso pacman tar sha256sum mksquashfs; do
  command -v "$c" >/dev/null || die "Missing command: $c (pacman -S archiso)."
done

ANAME="$(basename -- "$ARCHIVE")"
[[ "$ANAME" =~ ^katmate-os-([A-Za-z0-9][A-Za-z0-9._-]*)\.tar\.gz$ ]] \
  || die "$ANAME is not katmate-os-<tag>.tar.gz."
TAG="${BASH_REMATCH[1]}"
[[ -f "$ARCHIVE" ]] || die "No such archive: $ARCHIVE"
if [[ -e "$OUT" ]]; then
  [[ -d "$OUT" && -z "$(ls -A -- "$OUT")" ]] || die "$OUT exists and is not an empty directory."
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
W="$OUT/work"
SECONDS=0

log "Tree: $ANAME (tag $TAG)"
mkdir -p "$W"
tar -xzf "$ARCHIVE" -C "$W"
TREE="$W/katmate-os-$TAG"
[[ -d "$TREE/iso" && -r "$TREE/installer/lib/packages.sh" ]] \
  || die "$ANAME does not unpack to katmate-os-$TAG/ with iso/ and installer/lib/packages.sh."
# shellcheck source=installer/lib/packages.sh
source "$TREE/installer/lib/packages.sh"
(( ${#KM_HOST_PKGS[@]} > 0 && ${#KM_UCODE_PKGS[@]} > 0 )) || die "packages.sh lists no packages."

P="$W/profile"
cp -a "$TREE/iso" "$P"
sed -i "s/@TAG@/$TAG/" "$P/profiledef.sh"
grep -qx "iso_version=\"$TAG\"" "$P/profiledef.sh" || die "profiledef.sh: iso_version not set to $TAG."
install -D -m 0644 "$ARCHIVE" "$P/airootfs/usr/share/katmate-iso/$ANAME"
install -D -m 0644 /dev/null "$P/airootfs/etc/katmate-iso/iso.env"
printf 'ISO_RELEASE_TAG=%s\n' "$TAG" >"$P/airootfs/etc/katmate-iso/iso.env"

log "Offline repository: ${#KM_HOST_PKGS[@]} + ${#KM_UCODE_PKGS[@]} packages and their closure"
REPO="$P/airootfs/usr/share/katmate-iso/repo"
DB="$W/repo-db"
mkdir -p "$REPO" "$DB"
# A large transfer can stall on some network paths and pacman then aborts the
# whole transaction; a re-run resumes from the cache directory.
for try in 1 2 3; do
  pacman -Syw --noconfirm --config "$P/pacman.conf" --dbpath "$DB" --cachedir "$REPO" \
    --logfile "$W/pacman-repo.log" "${KM_HOST_PKGS[@]}" "${KM_UCODE_PKGS[@]}" && break
  (( try < 3 )) || die "Offline repository: the download failed three times."
  log "Offline repository: download failed (attempt $try of 3), retrying"
done
install -m 0644 "$DB/sync/core.db" "$DB/sync/extra.db" "$REPO/"

# The check that can fire: resolve the same set again, from the repository
# alone, as pacstrap will, and require every file it names to be present.
log "Offline repository: resolution from the repository alone"
CHK="$W/repo-check"
mkdir -p "$CHK/db"
sed "s|file:///usr/share/katmate-iso/repo|file://$REPO|" \
  "$P/airootfs/etc/katmate-iso/pacman-offline.conf" >"$CHK/pacman.conf"
pacman -Sy --config "$CHK/pacman.conf" --dbpath "$CHK/db" --logfile "$CHK/pacman.log" >/dev/null
pacman -Sp --config "$CHK/pacman.conf" --dbpath "$CHK/db" --print-format '%f' \
  "${KM_HOST_PKGS[@]}" "${KM_UCODE_PKGS[@]}" >"$CHK/files"
missing=0
while IFS= read -r f; do
  [[ -f "$REPO/$f" ]] || { echo "missing from the repository: $f" >&2; missing=$((missing + 1)); }
done <"$CHK/files"
(( missing == 0 )) || die "$missing package files of the closure are not in the repository."
NPKG="$(wc -l <"$CHK/files")"
REPO_BYTES="$(du -sb "$REPO" | awk '{print $1}')"
echo "Closure: $NPKG packages, all present; repository $REPO_BYTES bytes."

# Medium validity (operator ruling, iso1 H2): pacman refuses a package whose
# signing key has expired, and reports it as "required key missing from
# keyring". The medium therefore installs only until the earliest expiry among
# the keys that sign its repository, read from the keyring the repository
# carries; after mkarchiso the live keyring must be that same file.
log "Medium validity: expiry of the keys that sign the repository"
KR="$W/keyring"
mkdir -p "$KR/gnupg"
chmod 0700 "$KR/gnupg"
KPKG="$(find "$REPO" -maxdepth 1 -name 'archlinux-keyring-*.pkg.tar.zst' -print -quit)"
[[ -n "$KPKG" ]] || die "No archlinux-keyring package in the repository."
tar -xf "$KPKG" -C "$KR" usr/share/pacman/keyrings/archlinux.gpg
KEYRING="$KR/usr/share/pacman/keyrings/archlinux.gpg"
gpg --batch --quiet --homedir "$KR/gnupg" --import "$KEYRING" 2>/dev/null || die "Cannot import $KEYRING."

declare -A SIGNERS=()
NSIG=0
for s in "$REPO"/*.pkg.tar.zst.sig; do
  [[ -e "$s" ]] || continue
  pk="$(gpg --batch --homedir "$KR/gnupg" --list-packets "$s" 2>/dev/null || true)"
  [[ "$pk" =~ :signature\ packet:.*keyid\ ([0-9A-F]{16}) ]] || die "No issuer key id in $s."
  SIGNERS[${BASH_REMATCH[1]}]=1
  NSIG=$((NSIG + 1))
done
NFILES="$(find "$REPO" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)"
(( NSIG == NFILES )) || die "$NSIG signatures for $NFILES packages in the repository."

NOW="$(date -u +%s)"
EARLIEST="" EXPIRIES=""
for id in "${!SIGNERS[@]}"; do
  cl="$(gpg --batch --homedir "$KR/gnupg" --with-colons --fixed-list-mode --list-keys "$id" 2>/dev/null)" \
    || die "Signing key $id is not in the medium's keyring."
  # The signing (sub)key's expiry, or the primary's if earlier; validity of both.
  read -r exp pv sv < <(awk -F: -v id="$id" '
    $1 == "pub" { pe = $7; pv = $2; if ($5 == id) { se = $7; sv = $2 } }
    $1 == "sub" && $5 == id { se = $7; sv = $2 }
    END { e = pe; if (se != "" && (e == "" || se + 0 < e + 0)) e = se
          printf "%s %s %s\n", (e == "" ? "none" : e), pv, (sv == "" ? "-" : sv) }' <<<"$cl")
  [[ "$pv$sv" != *[er]* ]] || die "Signing key $id is already expired or revoked at build time (validity $pv/$sv)."
  if [[ "$exp" != none ]]; then
    EXPIRIES+="$id $exp $(date -u -d "@$exp" +%F)"$'\n'
    if [[ -z "$EARLIEST" || "$exp" -lt "$EARLIEST" ]]; then EARLIEST="$exp"; fi
  fi
done
[[ -n "$EARLIEST" ]] || die "None of the ${#SIGNERS[@]} signing keys has an expiry: the computation is suspect."
ISO_VALID_UNTIL="$(date -u -d "@$EARLIEST" +%F)"
DAYS_LEFT=$(( (EARLIEST - NOW) / 86400 ))
echo "$NSIG signatures by ${#SIGNERS[@]} keys; the earliest expiries:"
printf '%s' "$EXPIRIES" | sort -k2,2n | awk 'NR <= 5 { print "  " $1 "  expires " $3 }'
echo "ISO_VALID_UNTIL=$ISO_VALID_UNTIL ($DAYS_LEFT days from now)"
(( DAYS_LEFT >= 60 )) \
  || die "The medium would be valid for $DAYS_LEFT days only (under 60): a signing key expires on $ISO_VALID_UNTIL."
printf 'ISO_VALID_UNTIL=%s\n' "$ISO_VALID_UNTIL" >>"$P/airootfs/etc/katmate-iso/iso.env"

log "mkarchiso"
mkarchiso -v -w "$W/archiso" -o "$OUT" "$P"

ISO="$(find "$OUT" -maxdepth 1 -name '*.iso' -print -quit)"
[[ -n "$ISO" ]] || die "mkarchiso wrote no ISO into $OUT."
LIVE_KEYRING="$W/archiso/x86_64/airootfs/usr/share/pacman/keyrings/archlinux.gpg"
if ! cmp -s "$KEYRING" "$LIVE_KEYRING"; then
  rm -f -- "$ISO"
  die "The live keyring ($LIVE_KEYRING) is not the repository's ($KPKG): ISO_VALID_UNTIL would describe another keyring. ISO removed."
fi
rm -rf -- "$W/archiso"
(cd "$OUT" && sha256sum -- "$(basename -- "$ISO")" >"$(basename -- "$ISO").sha256")
ISO_BYTES="$(stat -c %s -- "$ISO")"
log "Done in ${SECONDS} s"
echo "ISO:        $ISO"
echo "ISO bytes:  $ISO_BYTES ($( (( ISO_BYTES < 2 * 1024 ** 3 )) && echo 'under' || echo 'NOT under') 2 GiB)"
echo "Repository: $NPKG packages, $REPO_BYTES bytes"
echo "Valid until: $ISO_VALID_UNTIL (earliest signing-key expiry, UTC)"
cat -- "$ISO.sha256"
