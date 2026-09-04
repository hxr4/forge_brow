#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Release}"
APP="$ROOT/build/Build/Products/$CONFIG/Forge Browser.app"
pkill -f "Forge Browser.app/Contents/MacOS/Forge Browser" 2>/dev/null || true
sleep 1
open "$APP"
echo "launched $APP"
