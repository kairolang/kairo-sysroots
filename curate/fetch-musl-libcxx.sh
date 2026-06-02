#!/usr/bin/env bash
# Pull libc++-dev (headers) for each musl arch and graft the c++/v1 headers into
# the already-extracted musl trees. The libc++-static apk we already had shipped
# only archives (no headers) -> this fixes that blocker.
#
# Re-runnable: skips download if the apk is already present, re-extracts headers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="22.1.3-r0"
BASE="https://dl-cdn.alpinelinux.org/alpine/edge/main"

# triple -> alpine arch dir name
declare -A ARCH=(
  [x86_64-linux-musl]=x86_64
  [aarch64-linux-musl]=aarch64
  [armv7-linux-musl]=armv7
  [i686-linux-musl]=x86
  [riscv64-linux-musl]=riscv64
)

for triple in "${!ARCH[@]}"; do
  arch="${ARCH[$triple]}"
  apk="libc++-dev-${VER}.apk"
  dest="$ROOT/alpine-pull/$triple/$apk"
  tree="$ROOT/extract/$triple"

  if [[ ! -f "$dest" ]]; then
    echo ">> [$triple] downloading $apk"
    curl -fsSL --retry 3 -o "$dest" "$BASE/$arch/$apk"
  else
    echo ">> [$triple] $apk already present, skipping download"
  fi

  # Extract ONLY the c++ headers. The apk also carries usr/lib/libc++.so and
  # libc++abi.so, but those are GNU ld INPUT() scripts that pull the *shared*
  # libs; musl targets are static, and we already have libc++.a/.a archives, so
  # we deliberately drop them.
  echo ">> [$triple] extracting headers into usr/include/c++"
  rm -rf "$tree/usr/include/c++"
  # apk is a gzip'd tar with PAX 'APK-TOOLS.checksum.SHA1' keywords GNU tar warns
  # about; filter that noise but keep real errors.
  tar -xz -C "$tree" -f "$dest" usr/include/c++ 2>&1 \
    | grep -v 'APK-TOOLS.checksum' || true

  # Verify
  for h in vector string stdexcept; do
    test -f "$tree/usr/include/c++/v1/$h" \
      || { echo "!! [$triple] MISSING header $h" >&2; exit 1; }
  done
  echo ">> [$triple] OK: c++/v1/{vector,string,stdexcept} present"
done

echo "All 5 musl arches now have libc++ headers."
