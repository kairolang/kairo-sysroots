#!/usr/bin/env bash
# Curate the 5 linux-musl sysroots into canonical staging/<triple>/{include,lib}
# and write SYSROOT.toml. Tarballs are produced by tar-dist.sh, not here.
#
# Canonical mapping (musl-dev + linux-headers + libc++ + libunwind, all static):
#   usr/include/*  -> include/   (C headers, kernel headers asm|asm-generic|linux,
#                                  libc++ headers under c++/v1)
#   usr/lib/*      -> lib/       (.a archives + crt1/crti/crtn/Scrt1/rcrt1 objects)
#
# crtbegin/crtend are NOT shipped: they come from the compiler's compiler-rt
# resource dir (clang_rt.crtbegin-<arch>.o). See link-templates/ for the proof.
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

  # sanity
  test -f "$dst/include/c++/v1/vector" || { echo "!! [$triple] no libc++ in staging" >&2; exit 1; }
  test -f "$dst/lib/libc.a"            || { echo "!! [$triple] no libc.a in staging" >&2; exit 1; }
  test -f "$dst/lib/crt1.o"            || { echo "!! [$triple] no crt1.o in staging" >&2; exit 1; }
  echo ">> [$triple] staged -> $dst"
done

echo "musl staging complete."
