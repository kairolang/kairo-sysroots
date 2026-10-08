#!/usr/bin/env bash
# Curate the 4 windows-gnu (llvm-mingw) sysroots into staging/<triple>/{include,lib}.
# Source dirs are already include/+lib/ shaped per arch; we just copy and write TOML.
#
# crtbegin/crtend ARE shipped in the mingw sysroot lib/ (unlike musl, where they
# come from compiler-rt). compiler-rt builtins themselves still come from the
# compiler (llvm-mingw bundles them at lib/clang/22/lib/windows, outside the
# per-arch sysroot). Here they live in the sysroot instead: build-builtins.sh
# builds them from Kairo's LLVM into compiler-rt/lib/windows/ (resource_dir).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"
M="$ROOT/extract/mingw/llvm-mingw-20260224-ucrt-ubuntu-22.04-x86_64"

# kairo-triple -> mingw arch dir
declare -A SRC=(
  [x86_64-windows-gnu]=x86_64-w64-mingw32
  [aarch64-windows-gnu]=aarch64-w64-mingw32
  [armv7-windows-gnu]=armv7-w64-mingw32
  [i686-windows-gnu]=i686-w64-mingw32
)

emit_toml() {
  local triple="$1" out="$2"
  cat >"$out" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "windows-gnu"
sysroot       = "."
include_dirs  = ["include/c++/v1", "include"]
lib_dirs      = ["lib"]
has_libcxx    = true
static        = true
crt_startup   = ["crt2.o", "crtbegin.o"]
crt_end       = ["crtend.o"]
libc_link     = ["-lmingw32", "-lmoldname", "-lmingwex", "-lmsvcrt", "-ladvapi32", "-lshell32", "-luser32", "-lkernel32"]
libcxx_link   = ["-lc++", "-lunwind"]
rtlib         = "compiler-rt"
unwindlib     = "libunwind"
linker        = "lld"
resource_dir  = "compiler-rt"
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

for triple in "${!SRC[@]}"; do
  src="$M/${SRC[$triple]}"
  dst="$STAGE/$triple"
  echo ">> [$triple] staging from ${SRC[$triple]}"
  test -d "$src/include/c++/v1" || { echo "!! [$triple] no libc++ headers" >&2; exit 1; }
  rm -rf "$dst"; mkdir -p "$dst/include" "$dst/lib"
  cp -a "$src/include/." "$dst/include/"
  cp -a "$src/lib/."     "$dst/lib/"
  emit_toml "$triple" "$dst/SYSROOT.toml"
  test -f "$dst/lib/crt2.o"   || { echo "!! [$triple] no crt2.o" >&2; exit 1; }
  test -f "$dst/lib/libc++.a" || { echo "!! [$triple] no libc++.a" >&2; exit 1; }
  echo ">> [$triple] staged -> $dst"
done
echo "mingw staging complete."
