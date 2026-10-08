#!/usr/bin/env bash
# Emit dist/manifest.json: one entry per dist/<triple>-llvm22.tar.xz with its
# release asset URL, sha256, size, and the family/has_libcxx pulled from the
# matching staging/<triple>/SYSROOT.toml. This is the file Kairo reads at runtime
# to pull + verify the right sysroot.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"; DIST="$ROOT/dist"
BASE="https://github.com/kairolang/kairo-sysroots/releases/download/v1-llvm22"
OUT="$DIST/manifest.json"

# The compiler-rt bundle is uploaded once and rarely rebuilt; when its tarball
# is not in dist/, carry the published entry over instead of dropping it.
prev_rt=$(jq -c '.compiler_rt // empty' "$OUT" 2>/dev/null || true)

tval() { grep -E "^$2[[:space:]]*=" "$1" | head -1 | sed -E 's/^[^=]+=[[:space:]]*//; s/^"//; s/"$//'; }

{
  echo '{'
  echo '  "release": "v1-llvm22",'
  echo '  "llvm_version": "22.1.0",'
  echo '  "targets": {'
  first=1
  for tar in "$DIST"/*-llvm22.tar.xz; do
    asset=$(basename "$tar")
    # the compiler-rt bundle is not a per-triple sysroot; handled separately below
    [[ "$asset" == compiler-rt-* ]] && continue
    triple=${asset%-llvm22.tar.xz}
    toml="$STAGE/$triple/SYSROOT.toml"
    test -f "$toml" || { echo "!! no SYSROOT.toml for $triple" >&2; exit 1; }
    sha=$(sha256sum "$tar" | cut -d' ' -f1)
    size=$(stat -c%s "$tar")
    family=$(tval "$toml" family)
    has_libcxx=$(tval "$toml" has_libcxx)
    glibc=$(tval "$toml" glibc_version || true)
    resdir=$(tval "$toml" resource_dir || true)
    # TOML string arrays are JSON as written; local_only tells Kairo which dirs
    # the user must supply (windows-msvc: msvc/, the Microsoft CRT + SDK)
    local_only=$(grep -E '^local_only[[:space:]]*=' "$toml" | sed -E 's/^[^=]+=[[:space:]]*//' || true)
    [[ $first -eq 0 ]] && echo ','
    first=0
    printf '    "%s": {\n' "$triple"
    printf '      "asset": "%s",\n' "$asset"
    printf '      "url": "%s/%s",\n' "$BASE" "$asset"
    printf '      "sha256": "%s",\n' "$sha"
    printf '      "size": %s,\n' "$size"
    printf '      "family": "%s",\n' "$family"
    # optional keys, comma-joined so the last one carries no trailing comma
    extra=()
    [[ -n "$glibc" ]]  && extra+=("$(printf '"glibc_version": "%s"' "$glibc")")
    [[ -n "$resdir" ]] && extra+=("$(printf '"resource_dir": "%s"' "$resdir")")
    [[ -n "$local_only" ]] && extra+=("\"local_only\": $local_only")
    if [[ ${#extra[@]} -gt 0 ]]; then
      printf '      "has_libcxx": %s,\n' "$has_libcxx"
      for i in "${!extra[@]}"; do
        printf '      %s' "${extra[$i]}"
        [[ $i -lt $((${#extra[@]} - 1)) ]] && printf ','
        printf '\n'
      done
    else
      printf '      "has_libcxx": %s\n' "$has_libcxx"
    fi
    printf '    }'
  done
  echo ''
  echo '  }'
  # Optional compiler-rt bundle: builtins + crtbegin/crtend for the musl targets.
  # It is the COMPILER's resource-dir overlay (lib/clang/22/lib/<triple>/...), not
  # a sysroot Kairo unpacks it into its clang install, not into a sysroot.
  rt="$DIST/compiler-rt-musl-llvm22.tar.xz"
  if [[ -f "$rt" ]]; then
    rtsha=$(sha256sum "$rt" | cut -d' ' -f1)
    rtsize=$(stat -c%s "$rt")
    echo '  ,'
    echo '  "compiler_rt": {'
    echo '    "linux-musl": {'
    printf '      "asset": "%s",\n' "$(basename "$rt")"
    printf '      "url": "%s/%s",\n' "$BASE" "$(basename "$rt")"
    printf '      "sha256": "%s",\n' "$rtsha"
    printf '      "size": %s,\n' "$rtsize"
    echo '      "layout": "lib/clang/22/lib/<triple>/{libclang_rt.builtins.a,clang_rt.crtbegin.o,clang_rt.crtend.o}",'
    echo '      "applies_to": ["x86_64-linux-musl","aarch64-linux-musl","armv7-linux-musl","i686-linux-musl","riscv64-linux-musl"]'
    echo '    }'
    echo '  }'
  elif [[ -n "$prev_rt" ]]; then
    echo '  ,'
    echo "  \"compiler_rt\": $prev_rt"
  fi
  echo '}'
} > "$OUT"

echo ">> wrote $OUT"
command -v jq >/dev/null 2>&1 && jq -e . "$OUT" >/dev/null && echo ">> manifest.json is valid JSON ($(jq '.targets|length' "$OUT") targets)"
