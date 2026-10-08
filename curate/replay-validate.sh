#!/usr/bin/env bash
# Prove a curated sysroot works by replaying ONLY its SYSROOT.toml.
# Parses the TOML, reconstructs the clang invocation, compiles+links a real C++
# program, and (when host==target) runs it.
#
# Usage: replay-validate.sh <root-dir-containing-SYSROOT.toml> [clang]
set -euo pipefail

ROOT="$1"
CLANG="${2:-clang}"
shift $(( $# >= 2 ? 2 : 1 ))
EXTRA=("$@")   # optional passthrough clang flags (e.g. -resource-dir=... for cross builtins)
TOML="$ROOT/SYSROOT.toml"
test -f "$TOML" || { echo "no SYSROOT.toml in $ROOT" >&2; exit 1; }

# minimal TOML reader for the flat keys / string-arrays we emit
# tolerant of missing keys (no match -> empty, exit 0) under set -e/pipefail
val()  { { grep -E "^$1[[:space:]]*=" "$TOML" || true; } | head -1 | sed -E 's/^[^=]+=[[:space:]]*//; s/^"//; s/"$//'; }
arr()  { { grep -E "^$1[[:space:]]*=" "$TOML" || true; } | head -1 | sed -E 's/^[^=]+=[[:space:]]*\[//; s/\]$//; s/"//g; s/,/ /g'; }

triple=$(val triple)
has_libcxx=$(val has_libcxx)
static=$(val static)
rtlib=$(val rtlib)
unwindlib=$(val unwindlib)
linker=$(val linker)

family=$(val family)
inc_flags=()
for d in $(arr include_dirs); do
  # windows-msvc: the CRT/SDK dirs go after clang's resource headers, as Kairo
  # and clang-cl (-imsvc) order them; the UCRT's stddef.h would hide clang's.
  if [[ "$family" == "windows-msvc" && "$d" != */c++/* ]]; then inc_flags+=(-idirafter "$ROOT/$d")
  else inc_flags+=(-isystem "$ROOT/$d"); fi
done
for d in $(arr cc_defines); do inc_flags+=(-D"$d"); done
lib_flags=();  for d in $(arr lib_dirs);     do lib_flags+=(-L"$ROOT/$d"); done
iso_flags=();  for f in $(arr cc_isolation); do iso_flags+=("$f"); done
xcflags=();    for f in $(arr extra_cflags); do xcflags+=("$f"); done
# windows-msvc lists lld-link inputs (libc++.lib); the clang driver spells
# those -llibc++, which it turns back into libc++.lib on the search path.
lnk() { if [[ "$1" == *.lib ]]; then echo "-l${1%.lib}"; else echo "$1"; fi; }
cxx_libs=();   for l in $(arr libcxx_link);  do cxx_libs+=("$(lnk "$l")"); done
c_libs=();     for l in $(arr libc_link);    do c_libs+=("$(lnk "$l")"); done

cmd=("$CLANG" --target="$triple" --sysroot="$ROOT")
if [[ "$family" == "windows-msvc" ]]; then
  # static means the static CRT (libcmt); the clang MSVC driver has no -static.
  # C++ exceptions are off by default on this target.
  [[ "$static" == "true" ]] && cmd+=(-fms-runtime-lib=static)
  cmd+=(-fexceptions -fcxx-exceptions)
  # Builtins come from the sysroot's resource_dir, as Kairo's COFF flavor
  # finds them; the driver's -rtlib would look in the compiler's instead.
  rd=$(val resource_dir)
  for a in "$ROOT/$rd"/lib/windows/clang_rt.builtins-*.lib "$ROOT/$rd"/lib/*-windows-msvc/clang_rt.builtins.lib; do
    [[ -f "$a" ]] && EXTRA+=(-Wl,"$a")
  done
  rtlib=""
else
  [[ "$static" == "true" ]] && cmd+=(-static)
fi
[[ -n "$rtlib"     ]] && cmd+=(-rtlib="$rtlib")
[[ -n "$unwindlib" ]] && cmd+=(-unwindlib="$unwindlib")
[[ -n "$linker"    ]] && cmd+=(-fuse-ld="$linker")
cmd+=("${iso_flags[@]}" "${xcflags[@]}" "${inc_flags[@]}" "${EXTRA[@]}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out="$tmp/a.out"

if [[ "$has_libcxx" == "true" ]]; then
  cat >"$tmp/t.cpp" <<'CPP'
#include <string>
#include <vector>
#include <stdexcept>
int main(){
  try{
    std::vector<std::string> v;
    v.push_back("hello-libcxx");
    throw std::runtime_error(v[0]);
  }catch(const std::exception&e){
    return (int)std::string(e.what()).size();
  }
  return -1;
}
CPP
  src="$tmp/t.cpp"; expect=12; libs=("${cxx_libs[@]}")
else
  cat >"$tmp/t.c" <<'C'
#include <stdio.h>
#include <string.h>
int main(){ char b[16]; strcpy(b,"hello-c"); return (int)strlen(b); }
C
  src="$tmp/t.c"; expect=7; libs=("${c_libs[@]}")
fi

echo ">> [$triple] building from SYSROOT.toml with: $CLANG"
"${cmd[@]}" "$src" -o "$out" "${lib_flags[@]}" "${libs[@]}"
echo ">> [$triple] link OK"
file "$out" | sed 's/^/   /'

# run native linux binaries whose arch matches the host; run wasi via node.
host_arch=$(uname -m)
tri_arch="${triple%%-*}"
runnable=0
[[ "$family" == "linux-musl" && "$tri_arch" == "$host_arch" ]] && runnable=1

run_wasi=0
if [[ "$family" == "wasi" ]] && command -v node >/dev/null 2>&1; then run_wasi=1; fi

if [[ "$runnable" == 1 ]]; then
  set +e; "$out"; rc=$?; set -e
  if [[ "$rc" == "$expect" ]]; then
    echo ">> [$triple] RAN OK (exit=$rc == expected $expect)"
  else
    echo "!! [$triple] RAN but exit=$rc != expected $expect" >&2; exit 1
  fi
elif [[ "$run_wasi" == 1 ]]; then
  cat >"$tmp/run.mjs" <<'MJS'
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
const wasi = new WASI({ version: 'preview1', args: process.argv.slice(2) });
const bytes = await readFile(process.argv[2]);
const mod = await WebAssembly.compile(bytes);
const inst = await WebAssembly.instantiate(mod, wasi.getImportObject());
process.exit(wasi.start(inst));
MJS
  set +e; node --experimental-wasm-exnref "$tmp/run.mjs" "$out"; rc=$?; set -e
  if [[ "$rc" == "$expect" ]]; then
    echo ">> [$triple] RAN OK via node (exit=$rc == expected $expect)"
  else
    echo "!! [$triple] RAN via node but exit=$rc != expected $expect" >&2; exit 1
  fi
else
  echo ">> [$triple] link-only (cross-arch, not run on $host_arch host)"
fi
