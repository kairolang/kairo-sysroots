#!/usr/bin/env bash
# The LLVM runtimes sources the user-side build compiles: compiler-rt builtins,
# libunwind, libc++abi, libc++, plus the cmake glue they import. Tests, docs
# and benchmarks are dropped. REVISION pins the fork commit; `kairo sysroot`
# refuses a tree whose REVISION differs from the compiler's.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
LLVM_SRC="${LLVM_SRC:-$ROOT/../kairo-lang/Lib/llvm-runtimes}"
test -f "$LLVM_SRC/runtimes/CMakeLists.txt" || die "no llvm-project at $LLVM_SRC"
dst="$SHARE/runtimes"; fresh "$dst"

copy() { rsync -a --exclude 'test/' --exclude 'tests/' --exclude 'docs/' \
         --exclude 'benchmarks/' --exclude 'utils/' --exclude '.git*' \
         "$LLVM_SRC/$1/" "$dst/$1/"; }

mkdir -p "$dst/compiler-rt/lib" "$dst/llvm"
rsync -a "$LLVM_SRC/compiler-rt/CMakeLists.txt" "$dst/compiler-rt/"
rsync -a "$LLVM_SRC/compiler-rt/cmake/"            "$dst/compiler-rt/cmake/"
rsync -a "$LLVM_SRC/compiler-rt/include/"          "$dst/compiler-rt/include/"
rsync -a "$LLVM_SRC/compiler-rt/lib/CMakeLists.txt" "$dst/compiler-rt/lib/"
rsync -a "$LLVM_SRC/compiler-rt/lib/builtins/"     "$dst/compiler-rt/lib/builtins/"
copy libunwind; copy libcxxabi; copy libcxx; copy runtimes
rsync -a "$LLVM_SRC/llvm/cmake/"  "$dst/llvm/cmake/"
rsync -a "$LLVM_SRC/cmake/"       "$dst/cmake/"

rev=$(git -C "$LLVM_SRC" rev-parse HEAD)
if ! git -C "$LLVM_SRC" diff --quiet HEAD -- compiler-rt libunwind libcxxabi libcxx runtimes llvm/cmake cmake; then
  rev="$rev+$(git -C "$LLVM_SRC" diff HEAD -- compiler-rt libunwind libcxxabi libcxx runtimes llvm/cmake cmake | sha256sum | cut -c1-12)"
fi
echo "$rev" >"$dst/REVISION"
# source lists the no-cmake builder (phase 2) will read; scraped now so they
# follow the fork rather than being copied by hand.
B="$dst/compiler-rt/lib/builtins/CMakeLists.txt"
{
  for set in GENERIC_SOURCES GENERIC_TF_SOURCES BF16_SOURCES; do
    printf '%s = [' "$set"
    sed -n "/^set($set/,/)/p" "$B" | grep -oE '[a-z0-9_/]+\.(c|S)' | sed 's/.*/"&"/' | paste -sd, -
    echo ']'
  done
} >"$dst/compiler-rt/lib/builtins/sources.toml"
test -f "$dst/libcxx/include/vector" || die "libcxx headers missing"
test -f "$dst/runtimes/CMakeLists.txt" || die "runtimes glue missing"
log "runtimes -> $dst (rev $rev)"
