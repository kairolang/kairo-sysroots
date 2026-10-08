#!/usr/bin/env bash
# Pull Ubuntu 20.04 (focal) glibc + kernel headers for the 5 linux-gnu arches
# and unpack each into extract/<name>/ as a pristine Ubuntu root (usr/, lib/).
#
# Why focal / glibc 2.31: it is the oldest release that ships all five arches.
# bionic (2.27) has no riscv64, and Debian had no official riscv64 port before
# trixie. libc++ itself supports glibc >= 2.24, so 2.31 is the floor that
# works for every target. A binary linked against these stubs runs on any
# glibc >= 2.31 (Ubuntu 20.04, Debian 11, RHEL 9, Fedora 32 and later).
#
# Packages per arch: libc6 (the .so.6 the link resolves against, ld.so),
# libc6-dev (headers, crt*.o, libc_nonshared.a, the libc.so script),
# linux-libc-dev (kernel UAPI headers). The newest focal-updates build is
# taken; symbol versions are fixed at 2.31 across focal updates.
#
# Re-runnable: skips a .deb that is already present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PULL="$ROOT/ubuntu-pull"
EXTRACT="$ROOT/extract"
SUITE=focal

# name | ubuntu arch | mirror
rows=(
  "x86_64-linux-gnu-glibc2.31|amd64|http://archive.ubuntu.com/ubuntu"
  "i686-linux-gnu-glibc2.31|i386|http://archive.ubuntu.com/ubuntu"
  "aarch64-linux-gnu-glibc2.31|arm64|http://ports.ubuntu.com/ubuntu-ports"
  "armv7-linux-gnueabihf-glibc2.31|armhf|http://ports.ubuntu.com/ubuntu-ports"
  "riscv64-linux-gnu-glibc2.31|riscv64|http://ports.ubuntu.com/ubuntu-ports"
)
PKGS=(libc6 libc6-dev linux-libc-dev)

# Filename: of the newest version of $3 in a Packages index on stdin.
pick() {
  awk -v want="$1" '
    /^Package: /  { p = $2 }
    /^Version: /  { v = $2 }
    /^Filename: / { if (p == want) print v "\t" $2 }
  ' | sort -V | tail -1 | cut -f2
}

for row in "${rows[@]}"; do
  IFS='|' read -r name arch mirror <<<"$row"
  dir="$PULL/$name"
  mkdir -p "$dir"

  idx="$dir/Packages"
  if [[ ! -s "$idx" ]]; then
    : >"$idx"
    # updates first: pick() takes the highest version across both indexes.
    for s in "$SUITE-updates" "$SUITE"; do
      curl -fsSL --retry 3 "$mirror/dists/$s/main/binary-$arch/Packages.xz" | xz -dc >>"$idx"
    done
  fi

  out="$EXTRACT/$name"
  rm -rf "$out"
  mkdir -p "$out"
  for pkg in "${PKGS[@]}"; do
    rel=$(pick "$pkg" <"$idx")
    [[ -n "$rel" ]] || { echo "!! [$name] $pkg not in $SUITE/$arch" >&2; exit 1; }
    deb="$dir/$(basename "$rel")"
    if [[ ! -f "$deb" ]]; then
      echo ">> [$name] downloading $(basename "$rel")"
      curl -fsSL --retry 3 -o "$deb" "$mirror/$rel"
    fi
    echo "$mirror/$rel" >>"$dir/urls.txt"
    dpkg-deb -x "$deb" "$out"
  done
  sort -u -o "$dir/urls.txt" "$dir/urls.txt"

  test -f "$out/usr/include/stdio.h" || { echo "!! [$name] no stdio.h" >&2; exit 1; }
  echo ">> [$name] extracted -> $out"
done
