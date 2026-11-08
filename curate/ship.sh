#!/usr/bin/env bash
# Build share/kairo/sysroot/ -- the input tree a release ships so `kairo
# sysroot` can build any target offline. Runs every ship-*.sh, then the
# registry. The output is what build.py copies into the release tarball.
#
# Env: OUT       output dir (default: <repo>/share/kairo/sysroot)
#      LLVM_SRC  the fork checkout (default: ../kairo-lang/Lib/llvm-runtimes)
#      PIN=1     record missing sha256 pins in sources.toml
#      ONLY="musl glibc"   run a subset
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need curl tar xz sha256sum rsync make cmake ninja
steps=(runtimes musl uapi glibc mingw bsd wasi data registry)
[[ -n "${ONLY:-}" ]] && read -ra steps <<<"$ONLY"
mkdir -p "$SHARE"
for s in "${steps[@]}"; do
  log "=== $s"
  bash "$ROOT/curate/ship-$s.sh"
done
log "share tree complete: $SHARE ($(du -sh "$SHARE" | cut -f1))"
