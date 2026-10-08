#!/usr/bin/env bash
# Curate the wasm32-wasi sysroot from wasi-sdk-33 (LLVM 22.1.0, git 4434dabb6991 -
# the EXACT commit the Kairo fork clang-22 is built from, so libc++ ABI matches).
#
# Structure is preserved (NOT flattened): wasi ships per-target subtrees and an
# eh/noeh libc++ split. We keep include/wasm32-wasi (with its eh/c++/v1 libc++
# headers) and lib/wasm32-wasi (with its eh/ libc++ archives) at the same depth so
# the validated isystem/-L paths below resolve directly.
#
# We use the EH (exception-enabled) libc++ variant, linked with -fwasm-exceptions
# (the wasm exception-handling proposal -> exnref). Running requires a runtime that
# supports it (node --experimental-wasm-exnref); link-only otherwise.
#
# compiler-rt builtins are built afterwards by build-wasi-builtins.sh into
# compiler-rt/lib/wasm32-unknown-wasi/ (resource_dir).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"
triple="wasm32-wasi"
src="$ROOT/extract/wasm32-wasi/wasi-sysroot-33.0+m"
dst="$STAGE/$triple"

echo ">> [$triple] staging (preserving wasm32-wasi + eh/ libc++ split)"
test -f "$src/lib/wasm32-wasi/crt1-command.o" || { echo "!! no crt1-command.o" >&2; exit 1; }
test -f "$src/include/wasm32-wasi/eh/c++/v1/vector" || { echo "!! no eh libc++ headers" >&2; exit 1; }

rm -rf "$dst"; mkdir -p "$dst/include" "$dst/lib"
cp -a "$src/include/wasm32-wasi" "$dst/include/wasm32-wasi"
cp -a "$src/lib/wasm32-wasi"     "$dst/lib/wasm32-wasi"

cat >"$dst/SYSROOT.toml" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "wasi"
sysroot       = "."
include_dirs  = ["include/wasm32-wasi/eh/c++/v1", "include/wasm32-wasi"]
lib_dirs      = ["lib/wasm32-wasi/eh", "lib/wasm32-wasi"]
has_libcxx    = true
static        = false
crt_startup   = ["crt1-command.o"]
crt_end       = []
libc_link     = ["-lc"]
libcxx_link   = ["-lc++", "-lc++abi", "-lunwind"]
extra_cflags  = ["-fwasm-exceptions"]
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
rtlib         = "compiler-rt"
resource_dir  = "compiler-rt"
EOF

test -f "$dst/lib/wasm32-wasi/eh/libc++.a"      || { echo "!! no libc++.a in staging" >&2; exit 1; }
test -f "$dst/include/wasm32-wasi/eh/c++/v1/string" || { echo "!! no libc++ string header" >&2; exit 1; }
echo ">> [$triple] staged -> $dst"
