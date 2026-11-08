#!/usr/bin/env bash
# mingw-w64 inputs from one release tarball, so headers, defs and crt agree:
#
#   mingw/include/<arch>/               mingw-w64-headers installed per arch
#   mingw/def/<arch>/*.def              preprocessed DLL defs; the user side runs
#                                       kar (dlltool) to make lib<dll>.a from each
#   mingw/crt/<arch>/*.a, *.o           crt2.o dllcrt2.o crtbegin.o crtend.o libmingw32.a
#                                       libmingwex.a libmoldname.a libucrt*.a libmsvcrt-os.a ...
#                                       (every archive the crt build installs that is NOT
#                                       a pure import lib of a shipped def)
#
# The crt is built with llvm-mingw's clang (maintainer only, nothing of it
# ships). The riskiest script here: verify by linking validate/t.cpp per arch
# against import libs regenerated from def/ before trusting it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need make autoconf
a=$(fetch mingw-w64); src="$WORK/mingw-w64"; [[ -f "$src/mingw-w64-headers/configure" ]] || unpack "$a" "$src"
t=$(fetch llvm-mingw); tc="$WORK/llvm-mingw"; [[ -x "$tc/bin/clang" ]] || unpack "$t" "$tc"
export PATH="$tc/bin:$PATH"

# kairo arch | mingw host | crt lib subdir
rows=(
  "x86_64|x86_64-w64-mingw32|lib64"
  "i686|i686-w64-mingw32|lib32"
  "aarch64|aarch64-w64-mingw32|libarm64"
  "armv7|armv7-w64-mingw32|libarm32"
)
dst="$SHARE/mingw"; fresh "$dst"
for row in "${rows[@]}"; do
  IFS='|' read -r arch host libdir <<<"$row"
  bh="$WORK/mingw-headers-$arch"; bc="$WORK/mingw-crt-$arch"; ins="$WORK/mingw-install-$arch"
  rm -rf "$bh" "$bc" "$ins"; mkdir -p "$bh" "$bc" "$ins"
  log "[$arch] headers"
  (cd "$bh" && "$src/mingw-w64-headers/configure" --host="$host" --prefix="$ins" \
     --with-default-msvcrt=ucrt --enable-idl >configure.log 2>&1 && make -s install >build.log 2>&1) \
     || die "[$arch] headers failed ($bh)"
  log "[$arch] crt"
  (cd "$bc" && CC="$host-clang" CXX="$host-clang++" AR="llvm-ar" RANLIB="llvm-ranlib" DLLTOOL="$host-dlltool" \
     "$src/mingw-w64-crt/configure" --host="$host" --prefix="$ins" --with-default-msvcrt=ucrt \
     --disable-dependency-tracking --enable-lib64="$([[ $libdir == lib64 ]] && echo yes || echo no)" \
     --enable-lib32="$([[ $libdir == lib32 ]] && echo yes || echo no)" \
     --enable-libarm64="$([[ $libdir == libarm64 ]] && echo yes || echo no)" \
     --enable-libarm32="$([[ $libdir == libarm32 ]] && echo yes || echo no)" \
     >configure.log 2>&1 && make -s -j"$NPROC" >build.log 2>&1 && make -s install >>build.log 2>&1) \
     || { grep -m10 -iE 'error' "$bc/build.log" >&2; die "[$arch] crt failed ($bc)"; }

  mkdir -p "$dst/include/$arch" "$dst/def/$arch" "$dst/crt/$arch"
  rsync -a "$ins/include/" "$dst/include/$arch/"
  # preprocessed defs: the build turns lib-common/*.def.in into <libdir>/*.def
  find "$bc" -name '*.def' -path "*/$libdir/*" -exec cp {} "$dst/def/$arch/" \;
  find "$src/mingw-w64-crt/$libdir" -name '*.def' -exec cp -n {} "$dst/def/$arch/" \;
  # crt pieces: every installed lib minus pure import libs of shipped defs
  for f in "$ins/lib"/*.a "$ins/lib"/*.o; do
    n=$(basename "$f")
    if [[ "$n" == lib*.a && -f "$dst/def/$arch/${n#lib}" ]]; then continue; fi   # lib<x>.a <-> <x>.def? no: strip .a
    if [[ "$n" == lib*.a ]]; then d="${n#lib}"; d="${d%.a}.def"; [[ -f "$dst/def/$arch/$d" ]] && continue; fi
    cp "$f" "$dst/crt/$arch/"
  done
  for need_f in crt2.o crtbegin.o crtend.o libmingw32.a libmingwex.a libmoldname.a; do
    test -f "$dst/crt/$arch/$need_f" || die "[$arch] missing $need_f in crt set"
  done
  test -f "$dst/def/$arch/kernel32.def" || die "[$arch] no kernel32.def"
  test -f "$dst/include/$arch/windows.h" || die "[$arch] no windows.h"
  log "[$arch] -> include/def/crt ($(ls "$dst/def/$arch" | wc -l) defs)"
done
stamp "$dst" mingw-w64
