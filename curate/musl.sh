#!/usr/bin/env bash
# Curate the 5 linux-musl sysroots into canonical staging/<triple>/{include,lib}
# and write SYSROOT.toml. Tarballs are produced by tar-dist.sh, not here.
#
# Canonical mapping (musl-dev + linux-headers + libc++ + libunwind, all static):
#   usr/include/*  -> include/   (C headers, kernel headers asm|asm-generic|linux,
#                                  libc++ headers under c++/v1)
#   usr/lib/*      -> lib/       (.a archives + crt1/crti/crtn/Scrt1/rcrt1 objects)
#
# compiler-rt lives in the sysroot (resource_dir = "compiler-rt"):
#   compiler-rt/lib/<arch>-unknown-linux-musl/{clang_rt.crtbegin.o,clang_rt.crtend.o}
#     copied from fetch-musl-compiler-rt.sh's staging/compiler-rt-musl
#   .../libclang_rt.builtins.a
#     Alpine's, as a placeholder; build-builtins.sh then replaces it with one
#     built from Kairo's LLVM (f128, i128, bf16). Order: fetch-musl-libcxx.sh,
#     fetch-musl-compiler-rt.sh, musl.sh, build-builtins.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"

TRIPLES=(
  x86_64-linux-musl
  aarch64-linux-musl
  armv7-linux-musl
  i686-linux-musl
  riscv64-linux-musl
)

emit_toml() {
  local triple="$1" out="$2"
  cat >"$out" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "linux-musl"
sysroot       = "."
include_dirs  = ["include/c++/v1", "include"]
lib_dirs      = ["lib"]
has_libcxx    = true
static        = true
crt_startup   = ["crt1.o", "crti.o"]
crt_end       = ["crtn.o"]
libc_link     = ["-lc"]
libcxx_link   = ["-lc++", "-lc++abi", "-lunwind"]
rtlib         = "compiler-rt"
unwindlib     = "libunwind"
linker        = "lld"
resource_dir  = "compiler-rt"
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

for triple in "${TRIPLES[@]}"; do
  src="$ROOT/extract/$triple"
  dst="$STAGE/$triple"
  echo ">> [$triple] staging"

  test -f "$src/usr/include/c++/v1/vector" \
    || { echo "!! [$triple] libc++ headers missing; run fetch-musl-libcxx.sh first" >&2; exit 1; }

  rm -rf "$dst"
  mkdir -p "$dst/include" "$dst/lib"

  # cp -a preserves the dangling libc.so symlink (static target, harmless) and
  # all archive perms/timestamps.
  cp -a "$src/usr/include/." "$dst/include/"
  cp -a "$src/usr/lib/."     "$dst/lib/"

  emit_toml "$triple" "$dst/SYSROOT.toml"

  rt_src="$ROOT/staging/compiler-rt-musl/lib/clang/22/lib/${triple%%-*}-unknown-linux-musl"
  test -f "$rt_src/clang_rt.crtbegin.o" \
    || { echo "!! [$triple] no $rt_src; run fetch-musl-compiler-rt.sh first" >&2; exit 1; }
  mkdir -p "$dst/compiler-rt/lib/${triple%%-*}-unknown-linux-musl"
  cp -a "$rt_src"/. "$dst/compiler-rt/lib/${triple%%-*}-unknown-linux-musl/"

  # sanity
  test -f "$dst/include/c++/v1/vector" || { echo "!! [$triple] no libc++ in staging" >&2; exit 1; }
  test -f "$dst/lib/libc.a"            || { echo "!! [$triple] no libc.a in staging" >&2; exit 1; }
  test -f "$dst/lib/crt1.o"            || { echo "!! [$triple] no crt1.o in staging" >&2; exit 1; }
  echo ">> [$triple] staged -> $dst"
done

echo "musl staging complete."
