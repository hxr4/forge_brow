#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Release}"
APP="$ROOT/build/Build/Products/$CONFIG/Forge Browser.app"
pkill -f "Forge Browser.app/Contents/MacOS/Forge Browser" 2>/dev/null || true
for _ in $(seq 40); do
  pgrep -f "Forge Browser.app/Contents/MacOS/Forge Browser" >/dev/null 2>&1 || break
  sleep 0.25
done
open "$APP"
echo "launched $APP"
