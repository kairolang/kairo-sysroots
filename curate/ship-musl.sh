#!/usr/bin/env bash
# musl source, unpacked. The user side runs its configure+make with kcc.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
a=$(fetch musl)
dst="$SHARE/musl"
unpack "$a" "$dst"
test -f "$dst/configure" && test -d "$dst/arch/riscv32" || die "not a musl tree"
stamp "$dst" musl
log "musl $(src_field musl version) -> $dst"
