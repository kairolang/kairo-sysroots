#!/usr/bin/env bash
# Build the LLVM runtimes for each linux-gnu sysroot from Kairo's own LLVM
# source (the same tree Kairo's clang is built from), against the pristine
# focal root fetch-glibc.sh unpacked:
#
#   compiler-rt  builtins + crtbegin/crtend   -> runtimes-out/<name>/rt/
#   libunwind, libc++abi, libc++  (static, PIC) -> runtimes-out/<name>/{include,lib}
#
# Ubuntu's own libc++ is not used: focal ships LLVM 10, and anything built on
# a newer distro may reference glibc symbols past 2.31. Built here, every
# glibc reference resolves against the 2.31 stubs, so the floor holds.
# Static only: a Kairo binary then needs nothing beyond glibc on the target.
#
# Env: LLVM_SRC   llvm-project checkout (default: kairo-lang/Lib/llvm-runtimes)
#      CC / CXX   Kairo's own clang (default: kairo-lang/build/llvm/bin/clang).
#                 A stock clang has no __float128 on armv7, so compiler-rt's
#                 quad-float routines would silently compile to nothing there.
#
# compiler-rt is built with COMPILER_RT_ENABLE_SOFTWARE_INT128: on the 32-bit
# targets that adds the __int128 routines (__divti3, ...) and, with the
# Kairo clang patch, the quad-float ones (__addtf3, ...), which Kairo's i128
# and f128 lower to.
#
# Usage: build-glibc-runtimes.sh [<name> ...]   (default: all extract/*-glibc*)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_SRC="${LLVM_SRC:-$ROOT/../kairo-lang/Lib/llvm-runtimes}"
KCLANG="$ROOT/../kairo-lang/build/llvm/bin"
CC="${CC:-$KCLANG/clang}"
CXX="${CXX:-$KCLANG/clang++}"
command -v "$CC" >/dev/null || { echo "!! no clang at $CC (build it: ninja -C kairo-lang/build/llvm clang, or set CC/CXX)" >&2; exit 1; }
test -f "$LLVM_SRC/runtimes/CMakeLists.txt" || { echo "!! no llvm-project at $LLVM_SRC (set LLVM_SRC)" >&2; exit 1; }

# name -> clang target triple: the manifest triple, minus the -glibc<v> tag.
triple_of() { echo "${1%-glibc*}"; }

names=("$@")
[[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(cd "$ROOT/extract" && ls -d *-glibc*/ | tr -d /)

for name in "${names[@]}"; do
  sr="$ROOT/extract/$name"
  test -d "$sr/usr/include" || { echo "!! [$name] not extracted; run fetch-glibc.sh" >&2; exit 1; }
  triple=$(triple_of "$name")
  bld="$ROOT/runtimes-build/$name"
  out="$ROOT/runtimes-out/$name"
  rm -rf "$bld" "$out"
  mkdir -p "$bld"
  echo ">> [$name] configuring runtimes for $triple"

  # try_compile stays compile-only: there is no libc++ or builtins to link
  # against until this build produces them.
  cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$bld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$out" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_ASM_COMPILER="$CC" \
    -DCMAKE_C_COMPILER_TARGET="$triple" \
    -DCMAKE_CXX_COMPILER_TARGET="$triple" \
    -DCMAKE_ASM_COMPILER_TARGET="$triple" \
    -DCMAKE_SYSROOT="$sr" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="-fPIC" \
    -DCMAKE_CXX_FLAGS="-fPIC" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_ENABLE_SOFTWARE_INT128=ON \
    -DCOMPILER_RT_BUILD_CRT=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXX_ENABLE_SHARED=OFF \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=OFF \
    >"$bld/configure.log" 2>&1 \
    || { tail -30 "$bld/configure.log" >&2; echo "!! [$name] configure failed ($bld/configure.log)" >&2; exit 1; }

  echo ">> [$name] building"
  ninja -C "$bld" install >"$bld/build.log" 2>&1 \
    || { grep -m20 -E "error|FAILED" "$bld/build.log" >&2; echo "!! [$name] build failed ($bld/build.log)" >&2; exit 1; }

  # Gather compiler-rt from wherever this layout put it: lib/linux/ with
  # -<arch> suffixes when the per-target dir is off.
  mkdir -p "$out/rt"
  b=$(find "$out" -name 'libclang_rt.builtins*.a' | head -1)
  cb=$(find "$out" -name 'clang_rt.crtbegin*.o' | head -1)
  ce=$(find "$out" -name 'clang_rt.crtend*.o' | head -1)
  [[ -n "$b" && -n "$cb" && -n "$ce" ]] || { echo "!! [$name] compiler-rt incomplete" >&2; exit 1; }
  cp "$b" "$out/rt/libclang_rt.builtins.a"
  cp "$cb" "$out/rt/clang_rt.crtbegin.o"
  cp "$ce" "$out/rt/clang_rt.crtend.o"

  for f in lib/libc++.a lib/libc++abi.a lib/libunwind.a include/c++/v1/vector; do
    test -f "$out/$f" || { echo "!! [$name] missing $f" >&2; exit 1; }
  done
  echo ">> [$name] runtimes -> $out"
done
