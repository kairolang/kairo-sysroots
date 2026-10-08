#!/usr/bin/env bash
# Pack staging/<triple> -> dist/<triple>-llvm22.tar.xz with the tarball root dir
# being <triple>/ (so Kairo unpacks to cache/<triple>/). Symlinks preserved
# (tar stores them verbatim; never dereferenced).
#
# A SYSROOT.toml with redistributable = false is skipped (an error when named
# explicitly); dirs it lists in local_only are excluded from the tarball.
#
# Usage: tar-dist.sh <triple> [<triple> ...]   (default: all in staging/)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"; DIST="$ROOT/dist"
mkdir -p "$DIST"

triples=("$@"); explicit=("$@")
[[ ${#triples[@]} -eq 0 ]] && mapfile -t triples < <(cd "$STAGE" && ls -d */ | tr -d /)

for triple in "${triples[@]}"; do
  test -d "$STAGE/$triple" || { echo "!! no staging/$triple" >&2; exit 1; }
  toml="$STAGE/$triple/SYSROOT.toml"
  test -f "$toml" || { echo "!! no SYSROOT.toml in $triple" >&2; exit 1; }
  # License guard. redistributable = false (darwin: Apple SDK) never packs;
  # local_only dirs (windows-msvc: msvc/, the Microsoft CRT + SDK) are left
  # out, so only our own layer ships. Enforced here, not by convention.
  if grep -qE '^redistributable[[:space:]]*=[[:space:]]*false' "$toml"; then
    echo "!! $triple is redistributable = false (vendor SDK license); not packing" >&2
    [[ ${#explicit[@]} -gt 0 ]] && exit 1 || continue
  fi
  local_only=$(grep -E '^local_only[[:space:]]*=' "$toml" | grep -oE '"[^"]+"' | tr -d '"' || true)
  excludes=()
  for d in $local_only; do excludes+=(--exclude="$triple/$d"); done
  # Every tarball, whatever curated it: a compressed debug section anywhere
  # makes the sysroot unlinkable by an lld built without zlib.
  "$ROOT/curate/decompress-debug.sh" "$triple"
  out="$DIST/$triple-llvm22.tar.xz"
  echo ">> packing $triple -> $out"
  # Deterministic-ish: sort names, zero owner. -h is NOT passed so symlinks stay links.
  tar --sort=name --owner=0 --group=0 --numeric-owner "${excludes[@]}" \
      -cJf "$out" -C "$STAGE" "$triple"
  for d in $local_only; do
    # no grep -q: exiting at the first match would SIGPIPE tar, and pipefail
    # would then report "no leak" for exactly the case this check is for
    if tar -tJf "$out" | grep "^$triple/$d/" >/dev/null; then
      rm -f "$out"; echo "!! $triple/$d leaked into the tarball; removed $out" >&2; exit 1
    fi
  done
  echo "   $(du -h "$out" | cut -f1)  $(tar -tJf "$out" | wc -l) entries"
done
