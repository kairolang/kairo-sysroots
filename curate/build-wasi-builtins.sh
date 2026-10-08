#!/usr/bin/env bash
# Build compiler-rt builtins for wasm32-wasi from Kairo's own LLVM source,
# against the wasi-libc headers wasi.sh staged, and install them into
# staging/wasm32-wasi/compiler-rt/lib/wasm32-unknown-wasi/libclang_rt.builtins.a
# (where resource_dir = "compiler-rt" points).
#
# Why not wasi-sdk's prebuilt libclang_rt: it is built by a clang without
# __bf16 on wasm, and compiler-rt only compiles its bf16 routines when the
# configure check finds __bf16, so that archive has no __truncsfbf2 and
# friends. Kairo's bf16 lowers to them. The fork's clang accepts __bf16 on
# wasm, so building here picks them up. The f16 (__extendhfsf2, ...) and
# quad-float (__addtf3, ...; wasm32 long double is binary128) routines are
# built either way.
#
# Run after wasi.sh (which replaces staging/wasm32-wasi wholesale).
#
# Env: LLVM_SRC   llvm-project checkout (default: kairo-lang/Lib/llvm-runtimes)
#      CC         Kairo's own clang (default: kairo-lang/build/llvm/bin/clang)
#
# Usage: build-wasi-builtins.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_SRC="${LLVM_SRC:-$ROOT/../kairo-lang/Lib/llvm-runtimes}"
KBIN="$ROOT/../kairo-lang/build/llvm/bin"
CC="${CC:-$KBIN/clang}"
TRIPLE=wasm32-unknown-wasi
SR="$ROOT/staging/wasm32-wasi"
BLD="$ROOT/runtimes-build/wasm32-wasi-builtins"
OUT="$ROOT/runtimes-out/wasm32-wasi-builtins"
DST="$SR/compiler-rt/lib/$TRIPLE"

command -v "$CC" >/dev/null || { echo "!! no clang at $CC (set CC)" >&2; exit 1; }
test -f "$LLVM_SRC/compiler-rt/lib/builtins/CMakeLists.txt" || { echo "!! no compiler-rt at $LLVM_SRC (set LLVM_SRC)" >&2; exit 1; }
test -f "$SR/include/wasm32-wasi/stdlib.h" || { echo "!! no staged wasm32-wasi; run wasi.sh first" >&2; exit 1; }
AR="$(dirname "$CC")/llvm-ar";         [[ -x "$AR" ]]     || AR=$(command -v llvm-ar)
RANLIB="$(dirname "$CC")/llvm-ranlib"; [[ -x "$RANLIB" ]] || RANLIB=$(command -v llvm-ranlib)
NM="$(dirname "$CC")/llvm-nm";         [[ -x "$NM" ]]     || NM=$(command -v llvm-nm)

# The configure check this whole script exists for, plus real codegen: a
# frontend that accepts __bf16 is not enough. The WebAssembly backend also
# needs bf16 legalized (extload / truncstore / BF16_TO_FP / FP_TO_BF16 set to
# Expand in WebAssemblyISelLowering.cpp, as f16 already is), or it dies with
# "Cannot select: ... anyext from bf16" and the configure check reads as no.
for o in -O0 -O2; do
  printf '__bf16 f(__bf16 x) { return x; }\n__bf16 g(float x) { return (__bf16)x; }\n' \
    | "$CC" --target="$TRIPLE" -c "$o" -x c - -o /dev/null 2>/dev/null \
    || { echo "!! $CC cannot compile __bf16 for $TRIPLE at $o (frontend or WebAssembly backend bf16 lowering missing)" >&2; exit 1; }
done

rm -rf "$BLD" "$OUT"; mkdir -p "$BLD"
echo ">> [$TRIPLE] configuring compiler-rt builtins"
# Standalone builtins build, as wasi-sdk does it: baremetal (no OS runtime
# beyond libc headers), default target only, static archive only.
cmake -G Ninja -S "$LLVM_SRC/compiler-rt/lib/builtins" -B "$BLD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$OUT" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_ASM_COMPILER="$CC" \
  -DCMAKE_C_COMPILER_TARGET="$TRIPLE" -DCMAKE_ASM_COMPILER_TARGET="$TRIPLE" \
  -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_SYSROOT="$SR" \
  -DCMAKE_C_FLAGS="-isystem $SR/include/wasm32-wasi" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCOMPILER_RT_BAREMETAL_BUILD=ON \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_OS_DIR=wasi \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  >"$BLD/configure.log" 2>&1 \
  || { tail -30 "$BLD/configure.log" >&2; echo "!! configure failed ($BLD/configure.log)" >&2; exit 1; }
grep -q 'COMPILER_RT_HAS_wasm32_BFLOAT16:INTERNAL=1' "$BLD/CMakeCache.txt" \
  || { echo "!! configure did not detect __bf16 for wasm32 ($BLD/CMakeCache.txt)" >&2; exit 1; }

echo ">> [$TRIPLE] building"
ninja -C "$BLD" install >"$BLD/build.log" 2>&1 \
  || { grep -m20 -E "error|FAILED" "$BLD/build.log" >&2; echo "!! build failed ($BLD/build.log)" >&2; exit 1; }

a=$(find "$OUT" -name 'libclang_rt.builtins*.a' | head -1)
[[ -n "$a" ]] || { echo "!! no builtins archive under $OUT" >&2; exit 1; }
for sym in __truncsfbf2 __truncdfbf2 __trunctfbf2 __extendhfsf2 __truncsfhf2 __addtf3 __divti3; do
  "$NM" "$a" 2>/dev/null | grep -E " T $sym\$" >/dev/null || { echo "!! $a has no $sym" >&2; exit 1; }
done
mkdir -p "$DST"
cp "$a" "$DST/libclang_rt.builtins.a"
echo ">> [$TRIPLE] builtins -> $DST/libclang_rt.builtins.a"
