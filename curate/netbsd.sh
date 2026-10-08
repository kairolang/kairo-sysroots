#!/usr/bin/env bash
# Curate the NetBSD sysroot (x86_64 only). Same structure-preserving approach as
# FreeBSD (keep usr/include + usr/lib + lib so relative symlinks resolve).
# NetBSD startup object is crt0.o (not crt1.o). This writes a C-only
# SYSROOT.toml; build-bsd-runtimes.sh then adds LLVM 22 libc++ (base NetBSD
# has only GCC's libstdc++) and compiler-rt builtins (base libgcc is GCC's,
# without f16/bf16), and rewrites the TOML.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"
triple="x86_64-unknown-netbsd"
src="$ROOT/extract/$triple"
dst="$STAGE/$triple"

echo ">> [$triple] staging (preserving usr/lib + lib split)"
test -f "$src/usr/lib/crt0.o" || { echo "!! no crt0.o" >&2; exit 1; }
rm -rf "$dst"; mkdir -p "$dst/usr"
cp -a "$src/usr/include" "$dst/usr/include"
cp -a "$src/usr/lib"     "$dst/usr/lib"
cp -a "$src/lib"         "$dst/lib"

cat >"$dst/SYSROOT.toml" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "netbsd"
sysroot       = "."
include_dirs  = ["usr/include"]
lib_dirs      = ["usr/lib", "lib"]
has_libcxx    = false
static        = false
crt_startup   = ["crt0.o", "crti.o"]
crt_end       = ["crtn.o"]
libc_link     = ["-lc"]
libcxx_link   = []
linker        = "lld"
cc_isolation  = ["-nostdlibinc"]
EOF

test -f "$dst/usr/include/stdio.h" || { echo "!! no stdio.h" >&2; exit 1; }
test -f "$dst/usr/lib/libc.a"      || { echo "!! no libc.a" >&2; exit 1; }
echo ">> [$triple] staged -> $dst"
