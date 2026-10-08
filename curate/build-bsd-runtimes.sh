#!/usr/bin/env bash
# Build LLVM 22's C++ runtimes and compiler-rt builtins from Kairo's own LLVM
# source for the FreeBSD and NetBSD sysroots, against each base system's own
# headers and libc, and install them beside the base system:
#
#   staging/<name>/libcxx/include/c++/v1       libc++ headers (LLVM 22)
#   staging/<name>/libcxx/lib/{libc++,libc++abi,libunwind}.a   static, PIC
#   staging/<name>/compiler-rt/lib/<os>/libclang_rt.builtins-<arch>.a
#
# Why not the base system's C++ runtime: FreeBSD 14.4 ships libc++ 19 on
# libcxxrt, NetBSD 10.1 ships GCC 10's libstdc++ (no libc++ at all). Kairo's
# C++ interop builds against libc++ 22 on every other target. And why not
# base libgcc: NetBSD's is GCC's (no f16/bf16 routines), FreeBSD's is
# compiler-rt 19 (no __trunctfbf2). Built here, every target gets the same
# runtime set, and static libc++ means a Kairo binary needs no C++ runtime
# on the target.
#
# The base tree is left as is (usr/include/c++/v1 on FreeBSD stays libc++ 19
# for C interop with base C++ libraries); SYSROOT.toml puts libcxx/ first.
# Run after freebsd.sh / netbsd.sh (which replace staging/<name> wholesale);
# this script also rewrites their SYSROOT.toml to the libc++ form.
#
# Env: LLVM_SRC   llvm-project checkout (default: kairo-lang/Lib/llvm-runtimes)
#      CC / CXX   Kairo's own clang (default: kairo-lang/build/llvm/bin/clang{,++})
#
# Usage: build-bsd-runtimes.sh [<name> ...]   (default: every staged *-freebsd / *-netbsd)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_SRC="${LLVM_SRC:-$ROOT/../kairo-lang/Lib/llvm-runtimes}"
KBIN="$ROOT/../kairo-lang/build/llvm/bin"
CC="${CC:-$KBIN/clang}"
CXX="${CXX:-$KBIN/clang++}"
command -v "$CC" >/dev/null || { echo "!! no clang at $CC (set CC/CXX)" >&2; exit 1; }
test -f "$LLVM_SRC/runtimes/CMakeLists.txt" || { echo "!! no llvm-project at $LLVM_SRC (set LLVM_SRC)" >&2; exit 1; }
tool() { if [[ -x "$KBIN/$1" ]]; then echo "$KBIN/$1"; else command -v "$1" || { echo "!! need $1" >&2; exit 1; }; fi; }
AR=$(tool llvm-ar); RANLIB=$(tool llvm-ranlib); NM=$(tool llvm-nm)

# sysroot name -> clang target triple (with the base release it targets)
declare -A TRIPLE=(
  [x86_64-unknown-freebsd]=x86_64-unknown-freebsd14.4
  [aarch64-unknown-freebsd]=aarch64-unknown-freebsd14.4
  [x86_64-unknown-netbsd]=x86_64-unknown-netbsd10.1
)

# The libc++ form of the BSD manifests. crt objects are the base system's.
# crtbegin*/crtend are not listed: Kairo's linker adds the right variant
# itself (crtbeginT.o for -static), as on glibc. libc++ needs the threads
# library for std::thread.
emit_toml() {   # $1 = name, $2 = os (freebsd|netbsd), $3 = out
  local name="$1" os="$2" start thr
  if [[ "$os" == freebsd ]]; then start=crt1.o; thr=-lthr
  else                            start=crt0.o; thr=-lpthread; fi
  cat >"$3" <<EOF
triple        = "$name"
llvm_version  = "22.1.0"
family        = "$os"
sysroot       = "."
include_dirs  = ["libcxx/include/c++/v1", "usr/include"]
lib_dirs      = ["libcxx/lib", "usr/lib", "lib"]
has_libcxx    = true
static        = true
crt_startup   = ["$start", "crti.o"]
crt_end       = ["crtn.o"]
libc_link     = ["-lm", "$thr", "-lc"]
libcxx_link   = ["-lc++", "-lc++abi", "-lunwind"]
rtlib         = "compiler-rt"
unwindlib     = "libunwind"
linker        = "lld"
resource_dir  = "compiler-rt"
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

names=("$@")
[[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(cd "$ROOT/staging" && ls -d *-freebsd/ *-netbsd/ 2>/dev/null | tr -d /)

for name in "${names[@]}"; do
  sr="$ROOT/staging/$name"
  triple="${TRIPLE[$name]:-}"
  [[ -n "$triple" ]] || { echo "!! [$name] no clang triple known for this sysroot" >&2; exit 1; }
  test -f "$sr/usr/include/stdio.h" || { echo "!! [$name] not staged; run freebsd.sh / netbsd.sh" >&2; exit 1; }
  arch="${name%%-*}"
  case "$name" in *-freebsd) os=freebsd; sysname=FreeBSD ;; *-netbsd) os=netbsd; sysname=NetBSD ;; esac
  "$CC" --target="$triple" -dM -E -x c /dev/null | grep __SIZEOF_FLOAT128__ >/dev/null \
    || { echo "!! [$name] $CC has no __float128 on $triple" >&2; exit 1; }

  bld="$ROOT/runtimes-build/$name"
  out="$ROOT/runtimes-out/$name"
  rm -rf "$bld" "$out"; mkdir -p "$bld"

  # LLVM 22's libunwind (Registers.hpp, the aarch64 SME check) calls
  # getauxval() whenever <sys/auxv.h> exists. FreeBSD 14 has the header but
  # only elf_aux_info(), so the aarch64 build fails with "undeclared
  # identifier 'getauxval'". Force-include a getauxval built on elf_aux_info
  # into the C++ compiles (no C runtime declares it on FreeBSD, so nothing
  # can clash).
  cxx_extra=""
  if [[ "$os" == freebsd && "$arch" == aarch64 ]]; then
    cat >"$bld/freebsd_getauxval.h" <<'EOH'
#pragma once
#include <sys/auxv.h>
static inline unsigned long getauxval(int type) {
  unsigned long v = 0;
  return elf_aux_info(type, &v, sizeof v) == 0 ? v : 0;
}
EOH
    cxx_extra="-include $bld/freebsd_getauxval.h"
  fi
  echo ">> [$name] configuring runtimes for $triple"
  # try_compile stays compile-only: there is no libc++ or builtins to link
  # against until this build produces them. -nostdinc++ keeps the base
  # system's libc++ 19 headers (usr/include/c++/v1) out of every compile.
  cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$bld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$out" \
    -DCMAKE_SYSTEM_NAME="$sysname" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_ASM_COMPILER="$CC" \
    -DCMAKE_C_COMPILER_TARGET="$triple" -DCMAKE_CXX_COMPILER_TARGET="$triple" \
    -DCMAKE_ASM_COMPILER_TARGET="$triple" \
    -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" \
    -DCMAKE_SYSROOT="$sr" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="-fPIC -fforce-enable-int128" \
    -DCMAKE_CXX_FLAGS="-fPIC -nostdinc++ $cxx_extra" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_ENABLE_SOFTWARE_INT128=ON \
    -DCOMPILER_RT_BUILD_CRT=OFF \
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

  rt=$(find "$out" -name 'libclang_rt.builtins*.a' | head -1)
  [[ -n "$rt" ]] || { echo "!! [$name] no builtins archive under $out" >&2; exit 1; }
  for f in lib/libc++.a lib/libc++abi.a lib/libunwind.a include/c++/v1/vector; do
    test -f "$out/$f" || { echo "!! [$name] missing $f" >&2; exit 1; }
  done
  # grep reads to EOF (no -q): an early exit would SIGPIPE nm under pipefail.
  syms=$("$NM" "$rt" 2>/dev/null | awk '$2 == "T" { print $3 }')
  for sym in __addtf3 __netf2 __divti3 __extendhfsf2 __truncsfhf2 __truncsfbf2 __truncdfbf2 __trunctfbf2; do
    grep -x -- "$sym" <<<"$syms" >/dev/null || { echo "!! [$name] builtins have no $sym" >&2; exit 1; }
  done

  rm -rf "$sr/libcxx" "$sr/compiler-rt"
  mkdir -p "$sr/libcxx/include" "$sr/libcxx/lib" "$sr/compiler-rt/lib/$os"
  cp -a "$out/include/c++" "$sr/libcxx/include/"
  cp "$out/lib/libc++.a" "$out/lib/libc++abi.a" "$out/lib/libunwind.a" "$sr/libcxx/lib/"
  # __config_site is per target; libc++ installs it under include/<triple>/
  # when the per-target dir is on, include/c++/v1 otherwise. Either way it
  # must sit beside the headers that include it.
  test -f "$sr/libcxx/include/c++/v1/__config_site" || { echo "!! [$name] no __config_site" >&2; exit 1; }
  cp "$rt" "$sr/compiler-rt/lib/$os/libclang_rt.builtins-$arch.a"
  emit_toml "$name" "$os" "$sr/SYSROOT.toml"
  echo ">> [$name] runtimes -> libcxx/, compiler-rt/lib/$os/; SYSROOT.toml now has_libcxx = true"
done
