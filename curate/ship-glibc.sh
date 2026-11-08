#!/usr/bin/env bash
# glibc inputs per (version, arch), harvested from a full cross build with the
# distro's cross GCC. Nothing GCC-built except the four crt objects and
# libc_nonshared.a ships; the DSOs the user links against are generated from
# the abilists at build time.
#
#   glibc/<X.Y>/<arch>/include/          `make install-headers` output
#   glibc/<X.Y>/<arch>/crt/{crt1,Scrt1,crti,crtn}.o
#   glibc/<X.Y>/<arch>/libc_nonshared.a
#   glibc/<X.Y>/<arch>/abilist/<lib>.abilist   from the source tree, verbatim
#
# Needs: gcc, gcc-i686-linux-gnu, gcc-aarch64-linux-gnu, gcc-arm-linux-gnueabihf,
# gcc-riscv64-linux-gnu, bison, python3, and ship-uapi.sh run first.
# ~5 min per (version, arch); 6 versions x 5 arches runs for a while. Results
# are cached in ship-build/ by (version, arch) and only rebuilt when missing.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need bison python3 make
test -d "$SHARE/linux-uapi/generic" || die "run ship-uapi.sh first"
VERSIONS=(${GLIBC_VERSIONS:-2.28 2.31 2.34 2.35 2.38 2.41})

# kairo arch | gnu host triple | cross gcc | abilist dir (sysdeps/unix/sysv/linux/...)
rows=(
  "x86_64|x86_64-linux-gnu|gcc|x86_64/64"
  "i686|i686-linux-gnu|i686-linux-gnu-gcc|i386"
  "aarch64|aarch64-linux-gnu|aarch64-linux-gnu-gcc|aarch64"
  "armv7|arm-linux-gnueabihf|arm-linux-gnueabihf-gcc|arm/le"
  "riscv64|riscv64-linux-gnu|riscv64-linux-gnu-gcc|riscv/rv64/lp64d"
)

for v in "${VERSIONS[@]}"; do
  a=$(fetch "glibc-$v")
  src="$WORK/glibc-$v"; [[ -f "$src/configure" ]] || unpack "$a" "$src"
  for row in "${rows[@]}"; do
    IFS='|' read -r arch gnu gcc abidir <<<"$row"
    [[ "$arch" == riscv64 && "$(printf '%s\n2.27\n' "$v" | sort -V | head -1)" != 2.27 ]] && { log "[$v/$arch] no riscv64 before 2.27"; continue; }
    command -v "$gcc" >/dev/null || die "[$v/$arch] need $gcc"
    out="$SHARE/glibc/$v/$arch"
    b="$WORK/glibc-$v-$arch"
    if [[ ! -f "$b/.done" ]]; then
      log "[$v/$arch] building"
      rm -rf "$b"; mkdir -p "$b"
      # headers for configure: generic + this arch's asm, merged
      hdr="$b/uapi"; mkdir -p "$hdr"
      rsync -a "$SHARE/linux-uapi/generic/" "$hdr/"; rsync -a "$SHARE/linux-uapi/asm/$arch/asm/" "$hdr/asm/"
      (cd "$b" && CC="$gcc" "$src/configure" --host="$gnu" --prefix=/usr \
         --with-headers="$hdr" --disable-werror --disable-nscd --enable-kernel=3.2 \
         >configure.log 2>&1) || { tail -20 "$b/configure.log" >&2; die "[$v/$arch] configure failed"; }
      make -C "$b" -j"$NPROC" >"$b/build.log" 2>&1 || { grep -m10 -E 'error|Error' "$b/build.log" >&2; die "[$v/$arch] build failed ($b/build.log)"; }
      touch "$b/.done"
    fi
    fresh "$out"
    ir="$b/install"; rm -rf "$ir"
    make -C "$b" -s install-headers install_root="$ir" >/dev/null 2>&1
    cp -a "$ir/usr/include" "$out/include"
    # gnu/stubs.h is a generated header some trees only emit on a full install
    test -f "$out/include/gnu/stubs.h" || cp "$b/csu/stubs.h" "$out/include/gnu/stubs.h" 2>/dev/null || true
    mkdir -p "$out/crt" "$out/abilist"
    for o in crt1.o Scrt1.o crti.o crtn.o; do cp "$b/csu/$o" "$out/crt/"; done
    cp "$b/libc_nonshared.a" "$out/"
    # abilists: this arch's dir plus the generic linux ones a lib may share
    for f in "$src/sysdeps/unix/sysv/linux/$abidir"/*.abilist; do cp "$f" "$out/abilist/"; done
    for f in "$out/abilist"/*.abilist; do [[ -s "$f" ]] || die "[$v/$arch] empty $(basename "$f")"; done
    test -f "$out/abilist/libc.abilist" || die "[$v/$arch] no libc.abilist"
    test -f "$out/include/gnu/lib-names.h" || die "[$v/$arch] no gnu/lib-names.h"
    printf 'version = "%s"\narch = "%s"\nhost = "%s"\n' "$v" "$arch" "$gnu" >"$out/.input"
    log "[$v/$arch] -> $out"
  done
  stamp "$SHARE/glibc/$v" "glibc-$v"
done
printf 'floor = "2.28"\nversions = [%s]\n' "$(printf '"%s",' "${VERSIONS[@]}" | sed 's/,$//')" >"$SHARE/glibc/VERSIONS.toml"
