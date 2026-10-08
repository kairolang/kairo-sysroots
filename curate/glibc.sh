#!/usr/bin/env bash
# Curate the 5 linux-gnu sysroots (glibc 2.31, libc++) into canonical
# staging/<name>/{include,lib,compiler-rt} and write SYSROOT.toml. Inputs:
# extract/<name> from fetch-glibc.sh, runtimes-out/<name> from
# build-glibc-runtimes.sh. Tarballs are produced by tar-dist.sh, not here.
#
# Canonical mapping:
#   usr/include/*                    -> include/     (multiarch subdir kept:
#                                                     include/<multiarch>/)
#   lib/<ma>/*, usr/lib/<ma>/*       -> lib/         (flat; files only)
#   runtimes include/c++/v1          -> include/c++/v1
#   runtimes libc++/abi/unwind .a    -> lib/
#   runtimes builtins + crtbegin/end -> compiler-rt/lib/<triple>/
#
# glibc is linked dynamically: the .so.6 files here are what the link
# resolves symbol versions against, and the target machine supplies the real
# ones. libc++ is static, so the binary needs nothing else.
#
# Ubuntu's libc.so / libm.so linker scripts and its dev symlinks name
# absolute paths (/lib/<ma>/libc.so.6). lld re-roots those under --sysroot,
# which this flat layout does not have, so both are rewritten to bare names;
# lld finds a bare name in a script through the -L search path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/staging"
GLIBC=2.31

triple_of() { echo "${1%-glibc*}"; }

emit_toml() {
  local triple="$1" ma="$2" out="$3"
  cat >"$out" <<EOF
triple        = "$triple"
llvm_version  = "22.1.0"
family        = "linux-gnu"
glibc_version = "$GLIBC"
sysroot       = "."
include_dirs  = ["include/c++/v1", "include/$ma", "include"]
lib_dirs      = ["lib"]
has_libcxx    = true
static        = false
crt_startup   = ["crt1.o", "crti.o"]
crt_end       = ["crtn.o"]
libc_link     = ["-lm", "-lpthread", "-ldl", "-lc"]
libcxx_link   = ["-lc++", "-lc++abi", "-lunwind"]
rtlib         = "compiler-rt"
unwindlib     = "libunwind"
linker        = "lld"
resource_dir  = "compiler-rt"
cc_isolation  = ["-nostdlibinc", "-nostdinc++"]
EOF
}

names=("$@")
[[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(cd "$ROOT/extract" && ls -d *-glibc*/ | tr -d /)

for name in "${names[@]}"; do
  src="$ROOT/extract/$name"
  rt="$ROOT/runtimes-out/$name"
  dst="$STAGE/$name"
  triple=$(triple_of "$name")
  test -f "$rt/lib/libc++.a" || { echo "!! [$name] no runtimes; run build-glibc-runtimes.sh" >&2; exit 1; }

  # The multiarch dir is the one holding crt1.o (arm-linux-gnueabihf for
  # armv7, i386-linux-gnu for i686).
  ma=$(cd "$src/usr/lib" && dirname */crt1.o)
  echo ">> [$name] staging (multiarch $ma)"

  rm -rf "$dst"
  mkdir -p "$dst/include" "$dst/lib" "$dst/compiler-rt/lib/$triple"

  cp -a "$src/usr/include/." "$dst/include/"
  cp -a "$rt/include/c++" "$dst/include/"

  # Files and links only: gconv/, audit/ and friends are runtime data, not
  # link inputs.
  for d in "$src/lib/$ma" "$src/usr/lib/$ma"; do
    find "$d" -maxdepth 1 \( -type f -o -type l \) -exec cp -a {} "$dst/lib/" \;
  done
  cp -a "$rt/lib/libc++.a" "$rt/lib/libc++abi.a" "$rt/lib/libunwind.a" "$rt/lib/libc++experimental.a" "$dst/lib/"
  cp -a "$rt/rt/." "$dst/compiler-rt/lib/$triple/"

  # Absolute symlinks -> bare names in the same flat dir.
  while IFS= read -r -d '' l; do
    t=$(readlink "$l")
    [[ "$t" == /* ]] || continue
    b=$(basename "$t")
    test -e "$dst/lib/$b" || { echo "!! [$name] $(basename "$l") -> $t: no $b" >&2; exit 1; }
    ln -sfn "$b" "$l"
  done < <(find "$dst/lib" -type l -print0)

  # Linker scripts: every absolute path -> its basename.
  for s in "$dst"/lib/*.so; do
    [[ -f "$s" && ! -L "$s" ]] || continue
    grep -q "^GROUP\|^INPUT\|OUTPUT_FORMAT" "$s" 2>/dev/null || continue
    # Paths only: a slash then a name, so the /* ... */ comments survive.
    sed -i -E 's#/[A-Za-z0-9_.+-]+(/[A-Za-z0-9_.+-]+)*/([A-Za-z0-9_.+-]+)#\2#g' "$s"
  done

  emit_toml "$triple" "$ma" "$dst/SYSROOT.toml"

  # sanity
  for f in include/c++/v1/vector include/stdio.h "include/$ma/bits/wordsize.h" \
           lib/crt1.o lib/crti.o lib/crtn.o lib/libc.so lib/libc.so.6 lib/libc_nonshared.a \
           lib/libc++.a "compiler-rt/lib/$triple/libclang_rt.builtins.a"; do
    test -e "$dst/$f" || { echo "!! [$name] missing $f" >&2; exit 1; }
  done
  if grep -hE "^(GROUP|INPUT).*/[A-Za-z]" "$dst"/lib/*.so 2>/dev/null | grep -q .; then
    echo "!! [$name] a linker script still names an absolute path" >&2; exit 1
  fi
  echo ">> [$name] staged -> $dst"
  grep GROUP "$dst/lib/libc.so"
done

echo "glibc staging complete."
