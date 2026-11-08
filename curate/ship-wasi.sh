#!/usr/bin/env bash
# wasi-libc + the EH libc++ from wasi-sdk 33 (same llvm commit as the fork; its
# libc++ is kept and only the builtins are rebuilt on the user side).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
a=$(fetch wasi-sysroot); x="$WORK/wasi-sysroot"; unpack "$a" "$x"
dst="$SHARE/wasi/33"; fresh "$dst"
rsync -a "$x/include/wasm32-wasi/" "$dst/include/wasm32-wasi/"
rsync -a --exclude 'noeh/' "$x/lib/wasm32-wasi/" "$dst/lib/wasm32-wasi/"
# the deprecated unsplit libc++ at the top level duplicates eh/; drop it
rm -f "$dst/lib/wasm32-wasi"/libc++*.a "$dst/lib/wasm32-wasi"/libunwind.a
test -f "$dst/lib/wasm32-wasi/crt1-command.o" || die "no crt1-command.o"
test -f "$dst/lib/wasm32-wasi/eh/libc++.a" || die "no eh libc++"
stamp "$dst" wasi-sysroot
log "wasi -> $dst"
