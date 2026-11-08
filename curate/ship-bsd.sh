#!/usr/bin/env bash
# FreeBSD / NetBSD base, pruned to what a static link reads:
#
#   freebsd/<ver>/include/                 usr/include minus c++/
#   freebsd/<ver>/<arch>/lib/              crt objects + static archives below
#   netbsd/<ver>/include/, netbsd/<ver>/x86_64/lib/
#
# Headers are arch-specific on both (machine/, x86/), so they are shipped per
# arch rather than deduplicated. Debug sections are decompressed here, once.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need llvm-objcopy llvm-readobj
FB_LIBS=(crt1.o Scrt1.o gcrt1.o crti.o crtn.o crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o
         libc.a libm.a libthr.a libpthread.a libdl.a librt.a libutil.a libexecinfo.a libelf.a libkvm.a)
NB_LIBS=(crt0.o crti.o crtn.o crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o gcrt0.o
         libc.a libm.a libpthread.a librt.a libutil.a libexecinfo.a)

decompress() {
  while IFS= read -r -d '' f; do
    llvm-readobj -S "$f" 2>/dev/null | grep SHF_COMPRESSED >/dev/null || continue
    llvm-objcopy --decompress-debug-sections "$f"
  done < <(find "$1" -type f \( -name '*.o' -o -name '*.a' \) -print0)
}

prune() {   # $1 = extracted root, $2 = out dir, $3.. = lib names
  local src="$1" out="$2"; shift 2
  fresh "$out"; mkdir -p "$out/lib"
  rsync -a --exclude 'c++/' "$src/usr/include/" "$out/include/"
  for l in "$@"; do
    if [[ -e "$src/usr/lib/$l" ]]; then cp -aL "$src/usr/lib/$l" "$out/lib/"
    elif [[ -e "$src/lib/$l" ]]; then cp -aL "$src/lib/$l" "$out/lib/"
    else log "   (no $l)"; fi
  done
  test -f "$out/lib/libc.a" || die "no libc.a under $src"
  test -f "$out/include/stdio.h" || die "no stdio.h under $src"
  decompress "$out/lib"
}

v=14.4
for arch in x86_64 aarch64; do
  a=$(fetch "freebsd-$v-$arch"); x="$WORK/freebsd-$v-$arch"
  [[ -f "$x/usr/lib/crt1.o" ]] || { fresh "$x"; tar -xf "$a" -C "$x" ./usr/include ./usr/lib ./lib; }
  prune "$x" "$SHARE/freebsd/$v/$arch" "${FB_LIBS[@]}"
  log "[freebsd $v $arch] -> $SHARE/freebsd/$v/$arch"
done
stamp "$SHARE/freebsd/$v" "freebsd-$v-x86_64"

v=10.1
x="$WORK/netbsd-$v-x86_64"
if [[ ! -f "$x/usr/lib/crt0.o" ]]; then
  fresh "$x"
  tar -xf "$(fetch netbsd-$v-x86_64-base)" -C "$x" ./usr/include ./usr/lib ./lib
  tar -xf "$(fetch netbsd-$v-x86_64-comp)" -C "$x" ./usr/include ./usr/lib
fi
prune "$x" "$SHARE/netbsd/$v/x86_64" "${NB_LIBS[@]}"
stamp "$SHARE/netbsd/$v" "netbsd-$v-x86_64-base"
log "[netbsd $v x86_64] -> $SHARE/netbsd/$v/x86_64"
