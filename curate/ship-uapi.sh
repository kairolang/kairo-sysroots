#!/usr/bin/env bash
# Kernel UAPI headers as `make headers_install` emits them, split into the
# arch-independent part (shipped once) and asm/ per arch.
#
#   linux-uapi/generic/{linux,asm-generic,scsi,...}
#   linux-uapi/asm/<kairo-arch>/asm/
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need make
a=$(fetch linux)
src="$WORK/linux"; unpack "$a" "$src"
dst="$SHARE/linux-uapi"; fresh "$dst/asm"
# kairo arch -> kernel ARCH
declare -A KARCH=( [x86_64]=x86 [i686]=x86 [aarch64]=arm64 [armv7]=arm [armv6]=arm [riscv64]=riscv [riscv32]=riscv )
first=1
for arch in x86_64 i686 aarch64 armv7 armv6 riscv64 riscv32; do
  o="$WORK/uapi-$arch"; rm -rf "$o"
  make -C "$src" -s -j"$NPROC" ARCH="${KARCH[$arch]}" INSTALL_HDR_PATH="$o" headers_install >/dev/null
  mkdir -p "$dst/asm/$arch"
  cp -a "$o/include/asm" "$dst/asm/$arch/asm"
  if [[ $first == 1 ]]; then
    rsync -a --exclude 'asm/' "$o/include/" "$dst/generic/"; first=0
  else
    # everything but asm/ must be identical across arches, or the split is wrong
    diff -rq --exclude asm "$o/include" "$dst/generic" >/dev/null || die "[$arch] non-asm UAPI headers differ"
  fi
done
stamp "$dst" linux
log "uapi -> $dst"
