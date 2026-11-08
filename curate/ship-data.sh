#!/usr/bin/env bash
# The static data: family recipes, quirks, shims, validation programs. These
# are versioned in this repo under data/ and copied verbatim.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for d in families shims validate; do fresh "$SHARE/$d"; rsync -a "$ROOT/data/$d/" "$SHARE/$d/"; done
cp "$ROOT/data/quirks.toml" "$SHARE/"
KAIRO="${KAIRO:-$ROOT/../kairo-lang}"
for k in test.k floats.k tfbf.k; do
  f=$(find "$KAIRO/Tests" -name "$k" | head -1); [[ -n "$f" ]] || die "no $k under $KAIRO/Tests"
  cp "$f" "$SHARE/validate/"
done
log "data -> $SHARE/{families,quirks.toml,shims,validate}"
