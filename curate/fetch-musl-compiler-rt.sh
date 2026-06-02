#!/usr/bin/env bash
# Pull Alpine's compiler-rt (LLVM 22.1.3-r0) for each musl arch and stage the
# three pieces a link actually needs builtins + crtbegin + crtend into a
# clang resource-dir tree:
#
#   compiler-rt/lib/clang/22/lib/<normalized-triple>/{libclang_rt.builtins.a,
#                                                     clang_rt.crtbegin.o,
#                                                     clang_rt.crtend.o}
#
# This is the per-target runtime layout clang 22 prefers (no -<arch> suffix). It
# is the COMPILER's resource dir, NOT a sysroot it ships with the Kairo clang.
# The sanitizer/xray/profile archives in the apk are dropped (not needed to link).
#
# Re-runnable: skips download if the apk is already present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="22.1.3-r0"
BASE="https://dl-cdn.alpinelinux.org/alpine/edge/main"
RES="$ROOT/staging/compiler-rt-musl/lib/clang/22/lib"

# kairo-triple -> (alpine arch dir, alpine internal triple, normalized clang triple)
rows=(
  "x86_64-linux-musl|x86_64|x86_64-alpine-linux-musl|x86_64-unknown-linux-musl"
  "aarch64-linux-musl|aarch64|aarch64-alpine-linux-musl|aarch64-unknown-linux-musl"
  "armv7-linux-musl|armv7|armv7-alpine-linux-musleabihf|armv7-unknown-linux-musl"
  "i686-linux-musl|x86|i586-alpine-linux-musl|i686-unknown-linux-musl"
  "riscv64-linux-musl|riscv64|riscv64-alpine-linux-musl|riscv64-unknown-linux-musl"
)

rm -rf "$ROOT/staging/compiler-rt-musl"
for row in "${rows[@]}"; do
  IFS='|' read -r triple arch atriple ntriple <<<"$row"
  apk="compiler-rt-${VER}.apk"
  dest="$ROOT/alpine-pull/$triple/$apk"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    echo ">> [$triple] downloading $apk"
    curl -fsSL --retry 3 -o "$dest" "$BASE/$arch/$apk"
  else
    echo ">> [$triple] $apk already present"
  fi

  tmp="$(mktemp -d)"
  # apk = gzip tar with PAX APK-TOOLS.checksum keywords -> filter the warning noise
  tar -xz -C "$tmp" -f "$dest" 2>&1 | grep -v 'APK-TOOLS.checksum' || true
  asrc="$tmp/usr/lib/llvm22/lib/clang/22/lib/$atriple"

  out="$RES/$ntriple"
  mkdir -p "$out"
  cp -a "$asrc/libclang_rt.builtins-$arch.a" "$out/libclang_rt.builtins.a" 2>/dev/null \
    || cp -a "$asrc"/libclang_rt.builtins-*.a "$out/libclang_rt.builtins.a"
  cp -a "$asrc"/clang_rt.crtbegin-*.o "$out/clang_rt.crtbegin.o"
  cp -a "$asrc"/clang_rt.crtend-*.o   "$out/clang_rt.crtend.o"
  rm -rf "$tmp"

  test -f "$out/libclang_rt.builtins.a" || { echo "!! [$triple] no builtins" >&2; exit 1; }
  test -f "$out/clang_rt.crtbegin.o"    || { echo "!! [$triple] no crtbegin" >&2; exit 1; }
  test -f "$out/clang_rt.crtend.o"      || { echo "!! [$triple] no crtend" >&2; exit 1; }
  echo ">> [$triple] staged builtins+crt -> lib/clang/22/lib/$ntriple"
done
echo "compiler-rt staging complete -> $ROOT/staging/compiler-rt-musl"
