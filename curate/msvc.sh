#!/usr/bin/env bash
# Curate the windows-msvc sysroots (x86_64, aarch64 a.k.a. arm64, i686 a.k.a.
# i386) from an xwin splat of the Microsoft CRT + Windows SDK, plus our own
# libc++ and compiler-rt builtins built against it.
#
# Two layers, one directory:
#   staging/<triple>/msvc/                 Microsoft CRT + SDK (xwin splat).
#                                          LOCAL ONLY: the license forbids
#                                          redistribution. SYSROOT.toml lists it
#                                          in local_only, and tar-dist.sh
#                                          excludes it from every tarball.
#   staging/<triple>/include/c++/v1, lib/, compiler-rt/
#                                          Ours (LLVM 22, Apache-2.0 WITH
#                                          LLVM-exception); safe to ship.
#
# Header order matters: include/c++/v1, then clang's resource headers, then
# the CRT/SDK dirs (where clang-cl puts -imsvc). The UCRT's stddef.h lacks
# max_align_t, and searched before clang's it hides the one libc++ needs.
# Kairo's C interop already orders include_dirs that way (c++ dirs, resource
# dir, the rest). libc_link / libcxx_link are lld-link inputs, as Kairo's COFF
# flavor passes them. static = true means the static CRT, not -static.
#
# Static CRT (/MT: libcmt + libvcruntime + libucrt): a Kairo binary needs no
# vcruntime140.dll / VC++ redistributable on the target. libc++ uses the
# vcruntime ABI (exceptions/RTTI come from vcruntime), so there is no
# libc++abi or libunwind here.
#
# libc++ is compiled with _CRT_STDIO_ISO_WIDE_SPECIFIERS, and the UCRT stamps
# every object with /failifmismatch on it: every TU linked against this
# sysroot must define it too (SYSROOT.toml cc_defines), or lld-link refuses.
#
# The splat comes from xwin, run by whoever accepts Microsoft's license:
#   xwin --accept-license --arch x86_64,aarch64,x86 \
#        --cache-dir extract/xwin-cache splat --output extract/xwin
#
# Expects <kairo-repo> to hold the LLVM fork source at Lib/llvm-runtimes and
# the fork's clang-cl + lld-link at build/llvm/bin.
#
# Binary128 needs the fork's __float128 on each *-windows-msvc triple;
# without it compiler-rt's int_types.h finds no tf_float and the quad-float
# (TF) routines compile empty, so Kairo's f128 would not link. Checked per
# arch before anything is staged, and the built archive must define __addtf3.
#
# Usage: ./curate/msvc.sh <kairo-repo> [x86_64|aarch64|arm64|i686|i386 ...]
#   XWIN=...  splat dir (default: <this repo>/extract/xwin)
#   OUT=...   default: <this repo>/staging; each triple lands in OUT/<triple>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAIRO="$(cd "${1:?usage: msvc.sh <kairo-repo> [arch...]}" && pwd)"; shift
ARCHES=("$@"); [[ ${#ARCHES[@]} -eq 0 ]] && ARCHES=(x86_64 aarch64 i686)
XWIN="$(cd "${XWIN:-$ROOT/extract/xwin}" && pwd)"
STAGE="${OUT:-$ROOT/staging}"
WORK="$ROOT/runtimes-build/msvc"

LLVM_SRC="$KAIRO/Lib/llvm-runtimes"
LLVM_BIN="$KAIRO/build/llvm/bin"
CLANG="$LLVM_BIN/clang"; CLANG_CL="$LLVM_BIN/clang-cl"; LLD_LINK="$LLVM_BIN/lld-link"

test -x "$CLANG_CL"                     || { echo "!! no fork clang-cl at $CLANG_CL" >&2; exit 1; }
test -x "$LLD_LINK"                     || { echo "!! no fork lld-link at $LLD_LINK" >&2; exit 1; }
test -d "$LLVM_SRC/runtimes"            || { echo "!! no $LLVM_SRC/runtimes" >&2; exit 1; }
test -f "$XWIN/sdk/include/um/Windows.h" || { echo "!! $XWIN is not an xwin splat (run xwin splat first)" >&2; exit 1; }
# The fork builds no llvm-lib/rc/mt; any LLVM 22 host copy does the same job.
tool() { if [[ -x "$LLVM_BIN/$1" ]]; then echo "$LLVM_BIN/$1"; else command -v "$1" || { echo "!! need $1" >&2; exit 1; }; fi; }
LLVM_LIB=$(tool llvm-lib); LLVM_RC=$(tool llvm-rc); LLVM_MT=$(tool llvm-mt); LLVM_NM=$(tool llvm-nm)
for t in cmake ninja; do command -v $t >/dev/null || { echo "!! need $t" >&2; exit 1; }; done

# <triple> <xwin-arch>  ->  SYSROOT.toml
emit_toml() {
  local triple="$1" xa="$2"
  cat >"$3" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "windows-msvc"
sysroot       = "."
include_dirs  = ["include/c++/v1", "msvc/crt/include", "msvc/sdk/include/ucrt", "msvc/sdk/include/um", "msvc/sdk/include/shared"]
lib_dirs      = ["lib", "msvc/crt/lib/$xa", "msvc/sdk/lib/um/$xa", "msvc/sdk/lib/ucrt/$xa"]
has_libcxx    = true
static        = true
crt_startup   = []
crt_end       = []
libc_link     = ["libcmt.lib", "libvcruntime.lib", "libucrt.lib", "oldnames.lib", "kernel32.lib", "user32.lib", "advapi32.lib", "shell32.lib", "uuid.lib"]
libcxx_link   = ["libc++.lib"]
rtlib         = "compiler-rt"
linker        = "lld-link"
resource_dir  = "compiler-rt"
msvc_crt      = "static"
local_only    = ["msvc"]
cc_defines    = ["_CRT_STDIO_ISO_WIDE_SPECIFIERS"]
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

# Microsoft's half: headers for every arch, libs for this arch only. cp -a
# keeps xwin's case-variant symlinks (Windows.h -> windows.h), which is what
# lets the SDK's mixed-case #includes resolve on a case-sensitive filesystem.
stage_msvc() {   # $1 = xwin arch, $2 = dst
  local xa="$1" m="$2/msvc"
  mkdir -p "$m/crt/lib" "$m/sdk/include" "$m/sdk/lib/um" "$m/sdk/lib/ucrt"
  cp -a "$XWIN/crt/include"             "$m/crt/"
  cp -a "$XWIN/crt/lib/$xa"             "$m/crt/lib/"
  for d in ucrt um shared winrt; do
    [[ -d "$XWIN/sdk/include/$d" ]] && cp -a "$XWIN/sdk/include/$d" "$m/sdk/include/"
  done
  cp -a "$XWIN/sdk/lib/um/$xa"          "$m/sdk/lib/um/"
  cp -a "$XWIN/sdk/lib/ucrt/$xa"        "$m/sdk/lib/ucrt/"
}

build_runtimes() {   # $1 = triple, $2 = xwin arch, $3 = dst
  local triple="$1" xa="$2" dst="$3" b="$WORK/$1" out="$WORK/$1-out" m="$3/msvc"
  local inc="-imsvc $m/crt/include -imsvc $m/sdk/include/ucrt -imsvc $m/sdk/include/um -imsvc $m/sdk/include/shared"
  # COMPILER_RT_ENABLE_SOFTWARE_INT128 adds -fforce-enable-int128, which
  # clang-cl ignores ("unknown argument"): on i686 the __int128 and quad-float
  # routines then compile empty. Pass it in the spelling clang-cl forwards.
  # A no-op on the 64-bit targets, where __int128 is native.
  inc="$inc -Xclang -fforce-enable-int128"
  local libp="/libpath:$m/crt/lib/$xa /libpath:$m/sdk/lib/um/$xa /libpath:$m/sdk/lib/ucrt/$xa"
  rm -rf "$b" "$out"; mkdir -p "$b"
  echo ">> [$triple] configuring runtimes"
  # ClangClCMakeCompileRules: '-' flag spelling, so clang-cl never mistakes a
  # /mnt/... path for a /m option. try_compile stays compile-only (no libc++
  # or builtins to link until this build makes them).
  cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$b" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$out" \
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_VERSION=10.0 \
    -DCMAKE_USER_MAKE_RULES_OVERRIDE="$LLVM_SRC/llvm/cmake/platforms/ClangClCMakeCompileRules.cmake" \
    -DCMAKE_C_COMPILER="$CLANG_CL" -DCMAKE_CXX_COMPILER="$CLANG_CL" \
    -DCMAKE_ASM_COMPILER="$CLANG_CL" \
    -DCMAKE_C_COMPILER_TARGET="$triple" -DCMAKE_CXX_COMPILER_TARGET="$triple" \
    -DCMAKE_ASM_COMPILER_TARGET="$triple" \
    -DCMAKE_LINKER="$LLD_LINK" -DCMAKE_AR="$LLVM_LIB" \
    -DCMAKE_RC_COMPILER="$LLVM_RC" -DCMAKE_MT="$LLVM_MT" \
    -DCMAKE_C_FLAGS="$inc" -DCMAKE_CXX_FLAGS="$inc" -DCMAKE_ASM_FLAGS="$inc" \
    -DCMAKE_EXE_LINKER_FLAGS="$libp" -DCMAKE_SHARED_LINKER_FLAGS="$libp" \
    -DCMAKE_C_STANDARD_LIBRARIES="" -DCMAKE_CXX_STANDARD_LIBRARIES="" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxx" \
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
    -DLIBCXX_CXX_ABI=vcruntime \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    >"$b/configure.log" 2>&1 \
    || { tail -30 "$b/configure.log" >&2; echo "!! [$triple] configure failed ($b/configure.log)" >&2; exit 1; }

  echo ">> [$triple] building"
  ninja -C "$b" install >"$b/build.log" 2>&1 \
    || { grep -m20 -E "error|FAILED" "$b/build.log" >&2; echo "!! [$triple] build failed ($b/build.log)" >&2; exit 1; }

  local cxx rt
  cxx=$(find "$out" -name 'libc++.lib' | head -1)
  rt=$(find "$out" -name 'clang_rt.builtins*.lib' | head -1)
  [[ -n "$cxx" && -n "$rt" ]] || { echo "!! [$triple] runtimes incomplete" >&2; exit 1; }
  mkdir -p "$dst/include" "$dst/lib" "$dst/compiler-rt/lib/windows"
  cp -a "$out/include/c++" "$dst/include/"
  cp "$cxx" "$dst/lib/libc++.lib"
  cp "$rt"  "$dst/compiler-rt/lib/windows/$(basename "$rt")"
  # grep reads to EOF (no -q): an early exit would SIGPIPE the producer and
  # pipefail would turn a match into a failure.
  add_tf_compare_aliases "$triple" "$dst/compiler-rt/lib/windows/$(basename "$rt")" "$b"
  rt="$dst/compiler-rt/lib/windows/$(basename "$rt")"
  for sym in __addtf3 __trunctfbf2 __truncsfbf2; do
    "$LLVM_NM" "$rt" 2>/dev/null | grep -E " T _?$sym\$" >/dev/null \
      || { echo "!! [$triple] builtins have no $sym (TF/bf16 routines compiled empty)" >&2; exit 1; }
  done
  grep -q '_LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS' "$dst/include/c++/v1/__config_site" \
    || { echo "!! [$triple] __config_site is not static-only (would import __imp_ symbols)" >&2; exit 1; }
}

# comparetf2.c defines __letf2 / __getf2 and makes __eqtf2, __lttf2, __netf2,
# __gttf2 (and __cmptf2) aliases of them. COMPILER_RT_ALIAS expands to nothing
# on _WIN32 (COFF has no symbol aliases), so on these targets those names do
# not exist and any f128 comparison fails to link (undefined __netf2). Add
# them as forwarding functions, built with the same headers so CMP_RESULT and
# fp_t match, into the builtins archive.
add_tf_compare_aliases() {   # $1 = triple, $2 = builtins .lib (rewritten), $3 = build dir
  local triple="$1" lib="$2" w="$3/tf-compare-aliases"
  local B="$LLVM_SRC/compiler-rt/lib/builtins"
  mkdir -p "$w"
  cat >"$w/tf_compare_aliases.c" <<'EOC'
#define QUAD_PRECISION
#include "fp_lib.h"
#if defined(CRT_HAS_TF_MODE)
#include "fp_compare_impl.inc"
COMPILER_RT_ABI CMP_RESULT __letf2(fp_t a, fp_t b);
COMPILER_RT_ABI CMP_RESULT __getf2(fp_t a, fp_t b);
COMPILER_RT_ABI CMP_RESULT __cmptf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __eqtf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __lttf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __netf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __gttf2(fp_t a, fp_t b) { return __getf2(a, b); }
#else
#error "no TF mode: __float128 / int128 missing on this target"
#endif
EOC
  # $inc: build_runtimes' CRT/SDK -imsvc flags (and -fforce-enable-int128)
  # shellcheck disable=SC2086
  "$CLANG_CL" --target="$triple" /nologo /c /O2 /MT $inc -I"$B" \
    "$w/tf_compare_aliases.c" /Fo"$w/tf_compare_aliases.obj"
  "$LLVM_LIB" /nologo /out:"$w/merged.lib" "$lib" "$w/tf_compare_aliases.obj"
  mv "$w/merged.lib" "$lib"
  for sym in __eqtf2 __netf2 __lttf2 __gttf2 __cmptf2; do
    "$LLVM_NM" "$lib" 2>/dev/null | grep -E " T _?$sym\$" >/dev/null \
      || { echo "!! [$triple] builtins still have no $sym" >&2; exit 1; }
  done
}

# The validated Kairo-shaped link: GNU-style clang driver, sysroot dirs only,
# C++ with a thrown and caught exception, linked by lld-link. Then the same
# link replayed from SYSROOT.toml alone.
validate() {   # $1 = triple, $2 = xwin arch, $3 = dst
  local triple="$1" xa="$2" r="$3" t="$WORK/$1-test"
  mkdir -p "$t"
  cat >"$t/t.cpp" <<'EOF'
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
int main() {
  std::vector<std::string> v{"a", "b"};
  try { throw std::runtime_error(v[0] + v[1]); }
  catch (const std::exception &e) { std::printf("%s\n", e.what()); }
  return 0;
}
EOF
  "$CLANG" --target="$triple" -nostdlibinc -nostdinc++ \
    -isystem "$r/include/c++/v1" -idirafter "$r/msvc/crt/include" \
    -idirafter "$r/msvc/sdk/include/ucrt" -idirafter "$r/msvc/sdk/include/um" \
    -idirafter "$r/msvc/sdk/include/shared" \
    -D_CRT_STDIO_ISO_WIDE_SPECIFIERS \
    -fms-runtime-lib=static -fexceptions -fcxx-exceptions -std=c++20 -O1 \
    -fuse-ld=lld -B"$LLVM_BIN" "$t/t.cpp" -o "$t/t.exe" \
    -L"$r/lib" -L"$r/msvc/crt/lib/$xa" -L"$r/msvc/sdk/lib/um/$xa" -L"$r/msvc/sdk/lib/ucrt/$xa" \
    -llibc++ "$r"/compiler-rt/lib/windows/clang_rt.builtins*.lib \
    || { echo "!! [$triple] validation link failed" >&2; exit 1; }
  echo "   validated: $(file -b "$t/t.exe" | cut -d, -f1-2)"
  bash "$ROOT/curate/replay-validate.sh" "$r" "$CLANG" -B"$LLVM_BIN" \
    || { echo "!! [$triple] SYSROOT.toml replay failed" >&2; exit 1; }
}

for arch in "${ARCHES[@]}"; do
  case "$arch" in
    x86_64|amd64|x64) arch=x86_64;  xa=x86_64 ;;
    aarch64|arm64)    arch=aarch64; xa=aarch64 ;;
    i686|i386|x86)    arch=i686;    xa=x86 ;;
    *) echo "!! unknown arch $arch (x86_64, aarch64/arm64, i686/i386)" >&2; exit 1 ;;
  esac
  triple="$arch-pc-windows-msvc"
  name="$arch-windows-msvc"
  dst="$STAGE/$name"
  "$CLANG" --target="$triple" -dM -E -x c /dev/null | grep __SIZEOF_FLOAT128__ >/dev/null \
    || { echo "!! fork clang has no __float128 on $triple (patch its MSVC TargetInfo first)" >&2; exit 1; }
  echo ">> [$name] staging from $XWIN -> $dst"
  rm -rf "$dst"; mkdir -p "$dst" "$WORK"
  stage_msvc "$xa" "$dst"
  build_runtimes "$triple" "$xa" "$dst"
  emit_toml "$name" "$xa" "$dst/SYSROOT.toml"
  validate "$triple" "$xa" "$dst"
  echo ">> [$name] staged ($(du -sh "$dst" | cut -f1); msvc/ is local only)"
done
echo "msvc staging complete (tar-dist.sh ships only the non-msvc/ layer)."
