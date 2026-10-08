#!/usr/bin/env bash
# Curate a Darwin sysroot from the LOCALLY installed Apple SDK. Never packed
# into dist/: the SDK license forbids redistribution. Run on a Mac.
#
# Layout is SDK-shaped, not flattened: libSystem.tbd re-exports
# /usr/lib/system/*.dylib by install name and lld resolves those (and
# frameworks) under -syslibroot, which the linker sets to this root.
#
# Ours, not Apple's: libc++/libc++abi (LLVM 22, static, hermetic) replace the
# SDK's, and compiler-rt TF builtins fill what libSystem lacks (binary128).
#
# Example (from the kairo-sysroots checkout, Kairo cloned at ~/kairo):
#   OUT=~/kairo/build/arm64-apple-macosx/sysroots ./curate/darwin.sh ~/kairo arm64 x86_64 arm64e
#
# Expects <kairo-repo> to hold the LLVM fork source at Lib/llvm-runtimes and
# its build at build/llvm (Scripts/build_llvm.py). Each triple is staged to
# $OUT/<triple>; any previous stage of that triple is replaced.
#
# build_llvm.py builds the libraries Kairo links, not the clang driver, so
# build/llvm/bin/clang is usually missing. Build it and the clang++ name the
# libc++ configure needs, from <kairo-repo>:
#   ninja -C build/llvm clang && ln -sf clang build/llvm/bin/clang++
# That clang compiles libc++ and the TF builtins for every arch, so it must
# carry the fork's __float128 patches for each Darwin target requested; the
# per-arch check below stops before staging if one is missing.
#
# Usage: ./curate/darwin.sh <kairo-repo> [arm64|arm64e|x86_64 ...]
#   OUT=...         default: <this repo>/staging; each triple lands in OUT/<triple>
#   SDK=...         default: xcrun --sdk macosx --show-sdk-path
#   MIN_MACOS=...   default: 11.0 (arm64, arm64e), 10.15 (x86_64)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAIRO="$(cd "${1:?usage: darwin.sh <kairo-repo> [arch...]}" && pwd)"; shift
ARCHES=("$@"); [[ ${#ARCHES[@]} -eq 0 ]] && ARCHES=(arm64)
STAGE="${OUT:-$ROOT/staging}"
WORK="$ROOT/extract/darwin-build"

LLVM_SRC="$KAIRO/Lib/llvm-runtimes"
LLVM_BIN="$KAIRO/build/llvm/bin"
CLANG="$LLVM_BIN/clang"; CLANGXX="$LLVM_BIN/clang++"

[[ "$(uname -s)" == Darwin ]]   || { echo "!! run on macOS" >&2; exit 1; }
SDK="${SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
SDK="$(cd "$SDK" && pwd -P)"                       # MacOSX.sdk -> MacOSX26.x.sdk

test -x "$CLANG"                || { echo "!! no fork clang at $CLANG" >&2; exit 1; }
test -f "$SDK/SDKSettings.json" || { echo "!! $SDK is not an SDK" >&2; exit 1; }
test -d "$LLVM_SRC/runtimes"    || { echo "!! no $LLVM_SRC/runtimes" >&2; exit 1; }
for t in cmake ninja rsync libtool nm; do
  command -v $t >/dev/null || { echo "!! need $t" >&2; exit 1; }
done

# Binary128 needs the fork's HasFloat128 on the Darwin target of EACH arch
# (DarwinAArch64TargetInfo, DarwinX86_64TargetInfo); without it compiler-rt's
# int_types.h finds no tf_float and the TF sources compile empty. Checked per
# arch in the loop, before anything is staged.
check_float128() {   # $1 = arch, $2 = min
  "$CLANG" -target "$1-apple-macos$2" -dM -E -x c /dev/null | grep -q __SIZEOF_FLOAT128__ \
    || { echo "!! fork clang has no __float128 on $1-apple-macos (patch its Darwin TargetInfo first)" >&2; exit 1; }
}

emit_toml() {
  cat >"$2" <<EOF
triple        = "$1"
llvm_version  = "22.1.0"
family        = "darwin"
sysroot       = "."
resource_dir  = "clang"
include_dirs  = ["usr/include/c++/v1", "usr/include"]
lib_dirs      = ["usr/lib"]
has_libcxx    = true
static        = false
crt_startup   = []
crt_end       = []
libc_link     = ["-lSystem"]
libcxx_link   = ["-lc++"]
rtlib         = "compiler-rt"
linker        = "lld"
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

stage_sdk() {   # $1 = dst
  local dst="$1"
  mkdir -p "$dst/usr" "$dst/System/Library"
  cp "$SDK/SDKSettings.json" "$dst/"
  [[ -f "$SDK/SDKSettings.plist" ]] && cp "$SDK/SDKSettings.plist" "$dst/"
  # Apple's libc++ headers out: ours go in their place.
  rsync -a --exclude 'c++/' "$SDK/usr/include/" "$dst/usr/include/"
  # .tbd stubs only; Apple's libc++/libc++abi out (ld64 prefers a dylib/tbd
  # over our .a in the same dir), swift out.
  rsync -a --exclude 'swift/' --exclude 'libc++*.tbd' \
        "$SDK/usr/lib/" "$dst/usr/lib/"
  rsync -a --exclude '*.swiftmodule' --exclude '*.swiftinterface' \
        --exclude '*.swiftdoc' --exclude '*.abi.json' \
        "$SDK/System/Library/Frameworks" "$dst/System/Library/"
}

build_libcxx() {   # $1 = arch, $2 = min, $3 = dst
  local arch="$1" min="$2" dst="$3" b="$WORK/libcxx-$arch"
  rm -rf "$b"
  cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$b" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CLANG" -DCMAKE_CXX_COMPILER="$CLANGXX" \
    -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$min" \
    -DCMAKE_INSTALL_PREFIX="$dst/usr" \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_STATIC=ON  -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
    -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXX_INSTALL_LIBRARY_DIR=lib -DLIBCXXABI_INSTALL_LIBRARY_DIR=lib \
    -DLIBCXX_INSTALL_INCLUDE_DIR=include/c++/v1 \
    -DLIBCXX_INSTALL_INCLUDE_TARGET_DIR=include/c++/v1
  ninja -C "$b" install-cxx install-cxxabi
  # Merged into libc++.a; a separate one would only invite a double link.
  rm -f "$dst/usr/lib/libc++abi.a"
}

build_tf_builtins() {   # $1 = arch, $2 = min, $3 = dst
  local arch="$1" min="$2" dst="$3" b="$WORK/tf-$arch"
  local B="$LLVM_SRC/compiler-rt/lib/builtins"
  local srcs
  srcs=$(sed -n '/^set(GENERIC_TF_SOURCES/,/)/p' "$B/CMakeLists.txt" | grep -oE '[a-z0-9_]+\.c')
  [[ -n "$srcs" ]] || { echo "!! GENERIC_TF_SOURCES not found" >&2; exit 1; }
  rm -rf "$b"; mkdir -p "$b" "$dst/clang/lib/darwin"
  for f in $srcs; do
    "$CLANG" -target "$arch-apple-macos$min" -isysroot "$SDK" \
      -O2 -fPIC -ffreestanding -fno-builtin -fvisibility=hidden \
      -c "$B/$f" -o "$b/${f%.c}.o"
  done
  libtool -static -o "$dst/clang/lib/darwin/libclang_rt.osx.a" "$b"/*.o
  nm "$dst/clang/lib/darwin/libclang_rt.osx.a" | grep -q ' T ___addtf3' \
    || { echo "!! [$arch] TF archive has no ___addtf3" >&2; exit 1; }
}

for arch in "${ARCHES[@]}"; do
  case "$arch" in
    arm64)  min="${MIN_MACOS:-11.0}" ;;
    # Pointer-authentication ABI (Xcode 26 "Enhanced Security"). The fork's
    # clang driver turns on the -fptrauth-* set for an arm64e triple, so
    # libc++ and the TF builtins come out signed with no extra flags here.
    arm64e) min="${MIN_MACOS:-11.0}" ;;
    x86_64) min="${MIN_MACOS:-10.15}" ;;
    *) echo "!! unknown arch $arch" >&2; exit 1 ;;
  esac
  check_float128 "$arch" "$min"
  triple="$arch-apple-macosx"
  dst="$STAGE/$triple"
  echo ">> [$triple] staging from $SDK (min $min) -> $dst"
  rm -rf "$dst"; mkdir -p "$dst" "$WORK"
  stage_sdk "$dst"
  build_libcxx "$arch" "$min" "$dst"
  build_tf_builtins "$arch" "$min" "$dst"
  emit_toml "$triple" "$dst/SYSROOT.toml"

  test -f "$dst/usr/include/stdio.h"       || { echo "!! [$triple] no stdio.h" >&2; exit 1; }
  test -f "$dst/usr/include/c++/v1/vector" || { echo "!! [$triple] no libc++ headers" >&2; exit 1; }
  test -f "$dst/usr/lib/libSystem.tbd"     || { echo "!! [$triple] no libSystem.tbd" >&2; exit 1; }
  test -d "$dst/usr/lib/system"            || { echo "!! [$triple] no usr/lib/system" >&2; exit 1; }
  test -f "$dst/usr/lib/libc++.a"          || { echo "!! [$triple] no libc++.a" >&2; exit 1; }
  if ls "$dst"/usr/lib/libc++*.tbd >/dev/null 2>&1; then
    echo "!! [$triple] Apple libc++ stub leaked" >&2; exit 1
  fi
  echo ">> [$triple] staged ($(du -sh "$dst" | cut -f1))"
done
echo "darwin staging complete (local only: never tar-dist / emit-manifest these)."
