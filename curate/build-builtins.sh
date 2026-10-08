#!/usr/bin/env bash
# Build compiler-rt builtins from Kairo's own LLVM source for the linux-musl
# and windows-gnu sysroots, replacing the prebuilt archives they shipped with
# (Alpine's compiler-rt apk, llvm-mingw's bundle):
#
#   staging/<arch>-linux-musl/compiler-rt/lib/<arch>-unknown-linux-musl/libclang_rt.builtins.a
#   staging/<arch>-windows-gnu/compiler-rt/lib/windows/libclang_rt.builtins-<rtarch>.a
#
# Why: those were built by a stock clang. It has no __float128 on most of
# these targets and does not force __int128 on the 32-bit ones, so the
# quad-float (__addtf3, __netf2, ...) and __int128 (__divti3, ...) routines
# that Kairo's f128 and i128 lower to are missing. It also has no
# __trunctfbf2 outside x86_64. Built here with the fork's clang and
# COMPILER_RT_ENABLE_SOFTWARE_INT128, every target gets the full set.
#
# Only the builtins archive is replaced. musl's clang_rt.crtbegin/crtend.o
# stay as staged (they hold no float code).
#
# Run after musl.sh / mingw.sh (which replace staging/<sysroot> wholesale).
#
# Env: LLVM_SRC   llvm-project checkout (default: kairo-lang/Lib/llvm-runtimes)
#      CC / CXX   Kairo's own clang (default: kairo-lang/build/llvm/bin/clang{,++})
#
# Usage: build-builtins.sh [<sysroot> ...]   (default: every staged *-linux-musl
#                                             and *-windows-gnu)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_SRC="${LLVM_SRC:-$ROOT/../kairo-lang/Lib/llvm-runtimes}"
CC="${CC:-$ROOT/../kairo-lang/build/llvm/bin/clang}"
KBIN="$(dirname "$CC")"
# aarch64 has a C++ source (emupac.cpp); without this CMake picks the host c++
CXX="${CXX:-$KBIN/clang++}"
command -v "$CC" >/dev/null || { echo "!! no clang at $CC (set CC)" >&2; exit 1; }
test -f "$LLVM_SRC/compiler-rt/lib/builtins/CMakeLists.txt" || { echo "!! no compiler-rt at $LLVM_SRC (set LLVM_SRC)" >&2; exit 1; }
tool() { if [[ -x "$KBIN/$1" ]]; then echo "$KBIN/$1"; else command -v "$1" || { echo "!! need $1" >&2; exit 1; }; fi; }
AR=$(tool llvm-ar); RANLIB=$(tool llvm-ranlib); NM=$(tool llvm-nm)

names=("$@")
[[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(cd "$ROOT/staging" && ls -d *-linux-musl/ *-windows-gnu/ 2>/dev/null | tr -d /)

for name in "${names[@]}"; do
  sr="$ROOT/staging/$name"
  arch="${name%%-*}"
  extra=()
  case "$name" in
    *-linux-musl)
      sysname=Linux
      # armv7: Alpine's armv7 is hard-float (VFPv3, AAPCS-VFP); a plain
      # -musl triple makes clang assume soft-float, a different call ABI.
      if [[ "$arch" == armv7 ]]; then target=armv7-unknown-linux-musleabihf; else target="$arch-unknown-linux-musl"; fi
      dst_dir="$sr/compiler-rt/lib/$arch-unknown-linux-musl"
      dst_name=libclang_rt.builtins.a ;;
    *-windows-gnu)
      sysname=Windows
      target="$arch-w64-windows-gnu"
      dst_dir="$sr/compiler-rt/lib/windows"
      case "$arch" in i686) rtarch=i386 ;; armv7) rtarch=arm ;; *) rtarch="$arch" ;; esac
      dst_name="libclang_rt.builtins-$rtarch.a"
      # MinGW has no libatomic: llvm-mingw puts __atomic_* in the builtins,
      # and so must we (compiler-rt leaves atomic.c out by default).
      extra=(-DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=OFF) ;;
    *) echo "!! [$name] not a linux-musl or windows-gnu sysroot" >&2; exit 1 ;;
  esac
  test -f "$sr/SYSROOT.toml" || { echo "!! [$name] not staged" >&2; exit 1; }
  "$CC" --target="$target" -dM -E -x c /dev/null | grep __SIZEOF_FLOAT128__ >/dev/null \
    || { echo "!! [$name] $CC has no __float128 on $target" >&2; exit 1; }

  bld="$ROOT/runtimes-build/builtins-$name"
  out="$ROOT/runtimes-out/builtins-$name"
  rm -rf "$bld" "$out"; mkdir -p "$bld"
  echo ">> [$name] configuring compiler-rt builtins for $target"
  # Standalone builtins build against the staged sysroot's headers only.
  # -fforce-enable-int128 directly as well as via SOFTWARE_INT128: the CMake
  # configure checks (e.g. the bf16 one) must see the same compiler.
  cmake -G Ninja -S "$LLVM_SRC/compiler-rt/lib/builtins" -B "$bld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$out" \
    -DCMAKE_SYSTEM_NAME="$sysname" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_ASM_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_COMPILER_TARGET="$target" -DCMAKE_ASM_COMPILER_TARGET="$target" \
    -DCMAKE_CXX_COMPILER_TARGET="$target" \
    -DCMAKE_CXX_FLAGS="-nostdlibinc -nostdinc++ -isystem $sr/include -fforce-enable-int128" \
    -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" \
    -DCMAKE_SYSROOT="$sr" \
    -DCMAKE_C_FLAGS="-nostdlibinc -isystem $sr/include -fforce-enable-int128" \
    -DCMAKE_ASM_FLAGS="-nostdlibinc -isystem $sr/include" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_ENABLE_SOFTWARE_INT128=ON \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    "${extra[@]}" \
    >"$bld/configure.log" 2>&1 \
    || { tail -30 "$bld/configure.log" >&2; echo "!! [$name] configure failed ($bld/configure.log)" >&2; exit 1; }
  grep -E 'COMPILER_RT_HAS_[a-z0-9_]+_BFLOAT16:INTERNAL=1' "$bld/CMakeCache.txt" >/dev/null \
    || { echo "!! [$name] configure did not detect __bf16 ($bld/CMakeCache.txt)" >&2; exit 1; }

  echo ">> [$name] building"
  ninja -C "$bld" install >"$bld/build.log" 2>&1 \
    || { grep -m20 -E "error|FAILED" "$bld/build.log" >&2; echo "!! [$name] build failed ($bld/build.log)" >&2; exit 1; }

  a=$(find "$out" -name 'libclang_rt.builtins*.a' | head -1)
  [[ -n "$a" ]] || { echo "!! [$name] no builtins archive under $out" >&2; exit 1; }
  # grep reads to EOF (no -q): an early exit would SIGPIPE nm under pipefail.
  syms=$("$NM" "$a" 2>/dev/null | awk '$2 == "T" { print $3 }' | sed 's/^_\(__\)/\1/')
  req=(__addtf3 __netf2 __divti3 __extendhfsf2 __truncsfhf2 __truncsfbf2 __truncdfbf2 __trunctfbf2)
  [[ "$name" == *-windows-gnu ]] && req+=(__atomic_load __atomic_compare_exchange)
  for sym in "${req[@]}"; do
    grep -x -- "$sym" <<<"$syms" >/dev/null || { echo "!! [$name] $a has no $sym" >&2; exit 1; }
  done
  mkdir -p "$dst_dir"
  cp "$a" "$dst_dir/$dst_name"
  echo ">> [$name] builtins -> ${dst_dir#$ROOT/}/$dst_name"
done
