#!/usr/bin/env bash
# Decompress SHF_COMPRESSED debug sections in every .o / .a under staging/<triple>.
#
# Alpine's x86 musl-dev (crt*.o, libc.a, libssp_nonshared.a) and FreeBSD's base
# archives ship .debug_* sections zlib-compressed. A linker reading them must
# be built with zlib, and an lld without it rejects the whole link:
#   libc.a(__lock.lo):(.debug_info) is compressed with ELFCOMPRESS_ZLIB,
#   but lld is not built with zlib support
# Decompressing costs nothing after xz and makes the sysroot linkable by any
# lld. The debug info itself is kept: stripping it would lose libc frames in
# a debugger.
#
# Usage: decompress-debug.sh <triple> [<triple> ...]   (default: all in staging/)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"
OBJCOPY="${LLVM_OBJCOPY:-llvm-objcopy}"
READOBJ="${LLVM_READOBJ:-llvm-readobj}"
command -v "$OBJCOPY" >/dev/null || { echo "!! $OBJCOPY not found (set LLVM_OBJCOPY)" >&2; exit 1; }
command -v "$READOBJ" >/dev/null || { echo "!! $READOBJ not found (set LLVM_READOBJ)" >&2; exit 1; }

# Not `grep -q`: it exits on the first match, readobj takes SIGPIPE on a big
# archive, and under pipefail the pipeline fails -- reading as "not compressed".
compressed() { "$READOBJ" -S "$1" 2>/dev/null | grep SHF_COMPRESSED >/dev/null; }

triples=("$@")
[[ ${#triples[@]} -eq 0 ]] && mapfile -t triples < <(cd "$STAGE" && ls -d */ | tr -d /)

for triple in "${triples[@]}"; do
  dir="$STAGE/$triple"
  test -d "$dir" || { echo "!! no staging/$triple" >&2; exit 1; }
  n=0
  # -type f: symlinked archives are fixed through their target, once.
  while IFS= read -r -d '' f; do
    compressed "$f" || continue
    # Keep the mtime so the repacked tarball differs only in content.
    ts=$(stat -c %Y "$f")
    "$OBJCOPY" --decompress-debug-sections "$f"
    touch -d "@$ts" "$f"
    compressed "$f" && { echo "!! [$triple] still compressed: $f" >&2; exit 1; }
    n=$((n + 1))
  done < <(find "$dir" -type f \( -name '*.o' -o -name '*.a' \) -print0)
  echo ">> [$triple] decompressed debug sections in $n file(s)"
done
