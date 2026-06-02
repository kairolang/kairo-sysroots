#!/usr/bin/env bash
# Curate the 2 FreeBSD sysroots. Unlike musl/mingw we DO NOT flatten to
# include/+lib/: FreeBSD's usr/lib is full of `../../lib/<x>.so.N` relative
# symlinks. Preserving the usr/include + usr/lib + lib split at the same depth
# under <triple>/ keeps every relative symlink resolving correctly with zero
# rewriting (usr/lib/foo -> ../../lib/bar  resolves to <triple>/lib/bar).
#
# has_libcxx=false: base libc++ is not LLVM 22 (ABI would clash with the Kairo
# compiler). C interop only. FreeBSD links against its own libgcc (shipped in
# usr/lib), not compiler-rt.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"

declare -A SRC=(
  [x86_64-unknown-freebsd]=x86_64-unknown-freebsd
  [aarch64-unknown-freebsd]=aarch64-unknown-freebsd
)

emit_toml() {
  local triple="$1" out="$2"
  cat >"$out" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "freebsd"
sysroot       = "."
include_dirs  = ["usr/include"]
lib_dirs      = ["usr/lib", "lib"]
has_libcxx    = false
static        = false
crt_startup   = ["crt1.o", "crti.o"]
crt_end       = ["crtn.o"]
libc_link     = ["-lc"]
libcxx_link   = []
rtlib         = "libgcc"
linker        = "lld"
cc_isolation  = ["-nostdlibinc"]
EOF
}

for triple in "${!SRC[@]}"; do
  src="$ROOT/extract/${SRC[$triple]}"
  dst="$STAGE/$triple"
  echo ">> [$triple] staging (preserving usr/lib + lib split)"
  test -f "$src/usr/lib/crt1.o" || { echo "!! [$triple] no crt1.o" >&2; exit 1; }
  rm -rf "$dst"; mkdir -p "$dst/usr"
  cp -a "$src/usr/include" "$dst/usr/include"
  cp -a "$src/usr/lib"     "$dst/usr/lib"
  cp -a "$src/lib"         "$dst/lib"
  emit_toml "$triple" "$dst/SYSROOT.toml"
  test -f "$dst/usr/include/stdio.h" || { echo "!! [$triple] no stdio.h" >&2; exit 1; }
  test -f "$dst/usr/lib/libc.a"      || { echo "!! [$triple] no libc.a" >&2; exit 1; }
  echo ">> [$triple] staged -> $dst"
done
echo "freebsd staging complete."
