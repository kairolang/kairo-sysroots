#!/usr/bin/env bash
# Emit dist/manifest.json: one entry per dist/<triple>-llvm22.tar.xz with its
# release asset URL, sha256, size, and the family/has_libcxx pulled from the
# matching staging/<triple>/SYSROOT.toml. This is the file Kairo reads at runtime
# to pull + verify the right sysroot.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"; DIST="$ROOT/dist"
BASE="https://github.com/kairolang/sysroots/releases/download/v1-llvm22"
OUT="$DIST/manifest.json"

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
    [[ $first -eq 0 ]] && echo ','
    first=0
    printf '    "%s": {\n' "$triple"
    printf '      "asset": "%s",\n' "$asset"
    printf '      "url": "%s/%s",\n' "$BASE" "$asset"
    printf '      "sha256": "%s",\n' "$sha"
    printf '      "size": %s,\n' "$size"
    printf '      "family": "%s",\n' "$family"
    printf '      "has_libcxx": %s\n' "$has_libcxx"
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
  fi
  echo '}'
} > "$OUT"

echo ">> wrote $OUT"
command -v jq >/dev/null 2>&1 && jq -e . "$OUT" >/dev/null && echo ">> manifest.json is valid JSON ($(jq '.targets|length' "$OUT") targets)"
