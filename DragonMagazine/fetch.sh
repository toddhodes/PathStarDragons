#!/usr/bin/env bash
# Mirror http://pied.nu/dragon/files/ into the files/ subdirectory next to this script.
#
# Usage: ./fetch.sh [ext ...]     e.g. ./fetch.sh pdf     (default: all files)
#   PARALLEL=4 ./fetch.sh         number of concurrent downloads (default 4)
#
# Note: the site's HTTPS cert is for a different host (www.quaero.ca), so plain HTTP is used.
# Already-downloaded files are skipped; partial downloads go to *.part and are resumed.

set -euo pipefail

BASE_URL="http://pied.nu/dragon/files/"
DEST="$(cd "$(dirname "$0")" && pwd)/files"
PARALLEL="${PARALLEL:-4}"

mkdir -p "$DEST"
cd "$DEST"

# Pull the Apache index and extract plain file links (skip sort links "?N=D" and the parent dir).
files=$(curl -fsSL --max-time 60 "$BASE_URL" \
  | grep -o 'HREF="[^"?/][^"]*"' \
  | sed 's/^HREF="//; s/"$//')

# Optional extension filter.
if [ $# -gt 0 ]; then
  pattern="\\.($(IFS='|'; echo "$*"))\$"
  files=$(printf '%s\n' "$files" | grep -Ei "$pattern" || true)
fi

total=$(printf '%s\n' "$files" | grep -c . || true)
echo "Found $total files at $BASE_URL -> $DEST"
[ "$total" -eq 0 ] && exit 0

fetch_one() {
  local name="$1"
  if [ -s "$name" ]; then
    return 0
  fi
  if curl -fsSL --retry 3 --retry-delay 2 --max-time 600 -C - -o "$name.part" "$BASE_URL$name"; then
    mv "$name.part" "$name"
    echo "ok   $name"
  else
    echo "FAIL $name" >&2
    return 1
  fi
}
export -f fetch_one
export BASE_URL

printf '%s\n' "$files" | grep . | xargs -P "$PARALLEL" -I{} bash -c 'fetch_one "$1"' _ {}

echo "Done."
