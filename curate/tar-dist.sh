#!/usr/bin/env bash
# Pack staging/<triple> -> dist/<triple>-llvm22.tar.xz with the tarball root dir
# being <triple>/ (so Kairo unpacks to cache/<triple>/). Symlinks preserved
# (tar stores them verbatim; never dereferenced).
#
# Usage: tar-dist.sh <triple> [<triple> ...]   (default: all in staging/)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"; DIST="$ROOT/dist"
mkdir -p "$DIST"

triples=("$@")
[[ ${#triples[@]} -eq 0 ]] && mapfile -t triples < <(cd "$STAGE" && ls -d */ | tr -d /)

for triple in "${triples[@]}"; do
  test -d "$STAGE/$triple" || { echo "!! no staging/$triple" >&2; exit 1; }
  test -f "$STAGE/$triple/SYSROOT.toml" || { echo "!! no SYSROOT.toml in $triple" >&2; exit 1; }
  out="$DIST/$triple-llvm22.tar.xz"
  echo ">> packing $triple -> $out"
  # Deterministic-ish: sort names, zero owner. -h is NOT passed so symlinks stay links.
  tar --sort=name --owner=0 --group=0 --numeric-owner \
      -cJf "$out" -C "$STAGE" "$triple"
  echo "   $(du -h "$out" | cut -f1)  $(tar -tJf "$out" | wc -l) entries"
done
