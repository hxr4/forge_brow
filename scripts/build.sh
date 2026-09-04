#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"
cd "$ROOT"

CONFIG="${1:-Release}"

bash scripts/build-adblock.sh
echo "Clearing embedded framework so Xcode's validation step does not see it..."
rm -rf "$ROOT/build/Build/Products/$CONFIG/Forge Browser.app/Contents/Frameworks/Chromium Embedded Framework.framework"

echo "Generating Xcode project..."
xcodegen generate --spec project.yml --quiet

echo "Building ForgeBrowser ($CONFIG)..."
set -o pipefail
xcodebuild \
  -project ForgeBrowser.xcodeproj \
  -scheme ForgeBrowser \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  ONLY_ACTIVE_ARCH=YES \
  VALIDATE_PRODUCT=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$ROOT/build/Build/Products/$CONFIG/Forge Browser.app"

echo "Assembling CEF bundle..."
export BUILT_PRODUCTS_DIR="$ROOT/build/Build/Products/$CONFIG"
export FULL_PRODUCT_NAME="Forge Browser.app"
export SRCROOT="$ROOT"
bash "$ROOT/scripts/assemble-bundle.sh"

echo "--- built ---"
ls -d "$APP"
