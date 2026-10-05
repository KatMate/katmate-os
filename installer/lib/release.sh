# shellcheck shell=bash
# ---------------------------------------------------------------------------
# KatMate OS — release source and verification (sourced, not executed)
# ---------------------------------------------------------------------------
#
# A release (ADR-020; operator rulings R2, R3, U1, 2026-10-05) is a flat set
# of files: a `git archive` of the release tag, the guest images (zstd), their
# T2 metadata, kernels, host binaries, release.env and images.list. One
# SHA256SUMS lists them all and SHA256SUMS.asc signs it, detached, with the
# release key.
#
# Two sources, verified identically: a local directory (USB), or a base URL
# whose files are fetched into a staging directory first (GitHub Releases).
# Nothing a release file says is used before its hash matched a line of a
# SHA256SUMS whose signature verified against the pinned fingerprint.
#
# The trust anchor is not this file. It is the user's manual check of the key
# fingerprint and of SHA256SUMS.asc before the installer is run at all
# (docs/INSTALL.md); this library repeats that check so a release that changed
# after it, or a file that was swapped, is refused rather than installed.
#
# Needs: gpg, sha256sum, curl (URL source only), tar, diff, mktemp.
# The caller defines die() and log().
# ---------------------------------------------------------------------------

# Set by rel_open. REL_SRC is a directory or an https:// base URL; REL_DIR is
# where the files are read from (REL_SRC itself for a directory).
REL_SRC=""
REL_DIR=""
REL_IS_URL=0
declare -gA REL_SUM=()     # file name -> sha256, from the verified SHA256SUMS

rel_open() {
  local src="$1" stage="$2"
  REL_SRC="$src"
  if [[ "$src" =~ ^https:// ]]; then
    REL_IS_URL=1
    REL_DIR="$stage"
    mkdir -p "$REL_DIR"
  elif [[ -d "$src" ]]; then
    REL_IS_URL=0
    REL_DIR="$(cd "$src" && pwd)"
  else
    die "Release source '$src' is neither an https:// URL nor a directory."
  fi
}

# rel_stage <dir>: move the staging directory for later downloads (the images
# are too large for the live system's RAM; they go to the target's root once
# it is mounted). Files already fetched stay where they are and keep working.
rel_stage() {
  (( REL_IS_URL )) || return 0
  local new="$1" f
  mkdir -p "$new"
  for f in "$REL_DIR"/*; do [[ -e "$f" ]] && mv -- "$f" "$new/"; done
  REL_DIR="$new"
}

# rel_fetch <name>: make <name> present in REL_DIR. A name is a flat file name;
# anything else is refused before it can become a path or a URL.
rel_fetch() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "Release file name '$name' is not a flat name."
  if (( REL_IS_URL )); then
    [[ -f "$REL_DIR/$name" ]] && return 0
    curl -fL --retry 3 --proto '=https' --tlsv1.2 -o "$REL_DIR/.$name.part" "$REL_SRC/$name" \
      || die "Cannot download $REL_SRC/$name"
    mv -f -- "$REL_DIR/.$name.part" "$REL_DIR/$name"
  else
    [[ -f "$REL_DIR/$name" ]] || die "Release file missing from $REL_DIR: $name"
  fi
}

rel_path() { printf '%s/%s' "$REL_DIR" "$1"; }

# rel_verify_sums <key file> <fingerprint>: verify SHA256SUMS.asc over
# SHA256SUMS with only the release key in a throwaway keyring, and require the
# good signature to be by the pinned primary key (VALIDSIG's last field, so a
# signing subkey is accounted for). Then load SHA256SUMS into REL_SUM.
rel_verify_sums() {
  local keyfile="$1" fpr="$2" gh status line name sum n=0
  rel_fetch SHA256SUMS
  rel_fetch SHA256SUMS.asc
  [[ -r "$keyfile" ]] || die "Release public key $keyfile is missing."

  gh="$(mktemp -d)"
  gpg --batch --quiet --homedir "$gh" --import "$keyfile" 2>/dev/null \
    || { rm -rf "$gh"; die "Cannot import the release key $keyfile."; }
  gpg --batch --homedir "$gh" --with-colons --fingerprint 2>/dev/null \
      | awk -F: '$1 == "fpr" {print $10}' | grep -qxF "$fpr" \
    || { rm -rf "$gh"; die "$keyfile does not carry the pinned release key $fpr."; }
  status="$(gpg --batch --homedir "$gh" --status-fd 1 \
              --verify "$(rel_path SHA256SUMS.asc)" "$(rel_path SHA256SUMS)" 2>/dev/null)" \
    || { rm -rf "$gh"; die "SHA256SUMS: the signature does not verify (gpg --verify failed)."; }
  rm -rf "$gh"
  awk -v f="$fpr" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $NF == f {ok = 1} END {exit !ok}' <<<"$status" \
    || die "SHA256SUMS: no valid signature by the release key $fpr."

  REL_SUM=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^([0-9a-f]{64})\ [\ *]([A-Za-z0-9][A-Za-z0-9._-]*)$ ]] \
      || die "SHA256SUMS: malformed line: $line"
    sum="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"
    [[ ! -v REL_SUM[$name] ]] || die "SHA256SUMS lists $name twice."
    REL_SUM[$name]="$sum"
    n=$((n + 1))
  done < "$(rel_path SHA256SUMS)"
  (( n > 0 )) || die "SHA256SUMS lists no files."
  log "SHA256SUMS: good signature by $fpr, $n files listed."
}

# rel_check <name>: fetch <name> and refuse unless its hash is the one the
# verified SHA256SUMS lists. Every release file goes through here before use.
rel_check() {
  local name="$1" have
  [[ -v REL_SUM[$name] ]] || die "$name is not listed in the signed SHA256SUMS."
  rel_fetch "$name"
  have="$(sha256sum -- "$(rel_path "$name")" | awk '{print $1}')"
  [[ "$have" == "${REL_SUM[$name]}" ]] \
    || die "$name: sha256 $have does not match the signed SHA256SUMS (${REL_SUM[$name]})."
}

# rel_env_get <file> <key>: read KEY=value from a verified flat file without
# sourcing it.
rel_env_get() { sed -n "s/^$2=//p" "$1" | head -n 1; }

# rel_check_tree <archive name> <prefix> <tree>: the installer runs only from
# the verified archive (R2). Unpack the verified archive and compare it with
# the tree this installer is running from. A file that differs or is missing
# refuses; a file only in the running tree (a preflight report, say) is listed
# and ignored, because nothing the installer runs is looked up by listing.
rel_check_tree() {
  local archive="$1" prefix="$2" tree="$3" x out bad extra
  rel_check "$archive"
  x="$(mktemp -d)"
  tar -xzf "$(rel_path "$archive")" -C "$x" || { rm -rf "$x"; die "Cannot unpack $archive."; }
  [[ -d "$x/$prefix" ]] || { rm -rf "$x"; die "$archive does not unpack to $prefix/."; }
  out="$(LC_ALL=C diff -rq --no-dereference "$x/$prefix" "$tree" 2>&1 || true)"
  rm -rf "$x"
  extra="$(grep -F "Only in $tree" <<<"$out" || true)"
  bad="$(grep -vF "Only in $tree" <<<"$out" | grep -v '^$' || true)"
  if [[ -n "$bad" ]]; then
    printf '%s\n' "$bad" >&2
    die "This installer does not match the signed release archive $archive (above). Run it from the verified archive, not from a clone or an edited copy."
  fi
  [[ -z "$extra" ]] || { echo "Files only in the running tree (ignored):"; printf '  %s\n' "$extra"; }
  log "Running tree equals the signed archive $archive."
}
