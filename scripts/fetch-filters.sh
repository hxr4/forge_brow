#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/filters"
mkdir -p "$OUT"

fetch() {
  printf '  %-22s' "$2"
  if curl -fsSL --retry 3 --max-time 90 "$1" -o "$OUT/$2.part"; then
    mv "$OUT/$2.part" "$OUT/$2"
    printf '%s lines\n' "$(wc -l < "$OUT/$2" | tr -d ' ')"
  else
    rm -f "$OUT/$2.part"
    printf 'FAILED (keeping any existing copy)\n'
  fi
}

echo "Fetching filter lists..."
fetch "https://easylist.to/easylist/easylist.txt"                              easylist.txt
fetch "https://easylist.to/easylist/easyprivacy.txt"                           easyprivacy.txt
fetch "https://ublockorigin.github.io/uAssets/filters/filters.txt"             ublock-filters.txt
fetch "https://ublockorigin.github.io/uAssets/filters/privacy.txt"             ublock-privacy.txt
fetch "https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt"         ublock-quickfixes.txt
fetch "https://ublockorigin.github.io/uAssets/filters/annoyances-cookies.txt"  ublock-cookies.txt
fetch "https://ublockorigin.github.io/uAssets/filters/badware.txt"             ublock-badware.txt
fetch "https://secure.fanboy.co.nz/fanboy-annoyance.txt"                       fanboy-annoyance.txt

echo
echo "Fetching scriptlet resources..."
printf '  %-22s' "resources.json"
if curl -fsSL --retry 3 --max-time 90 "https://raw.githubusercontent.com/brave/adblock-resources/master/dist/resources.json" -o "$OUT/resources.json.part"; then
  mv "$OUT/resources.json.part" "$OUT/resources.json"
  printf '%s bytes\n' "$(wc -c < "$OUT/resources.json" | tr -d ' ')"
else
  rm -f "$OUT/resources.json.part"
  printf 'FAILED\n'
fi

echo
echo "total rules on disk:"
cat "$OUT"/*.txt 2>/dev/null | grep -vc '^!' || true
