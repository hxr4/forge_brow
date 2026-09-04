#!/usr/bin/env bash
set -euo pipefail

APP="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
FRAMEWORKS="$APP/Contents/Frameworks"
CEF_ROOT="$SRCROOT/third_party/cef"
HELPER_SRC="$BUILT_PRODUCTS_DIR/Forge Helper.app"

mkdir -p "$FRAMEWORKS"

echo "assemble: copying Chromium Embedded Framework"
rm -rf "$FRAMEWORKS/Chromium Embedded Framework.framework"
ditto "$CEF_ROOT/Release/Chromium Embedded Framework.framework" \
      "$FRAMEWORKS/Chromium Embedded Framework.framework"

if [ ! -d "$HELPER_SRC" ]; then
  echo "assemble: helper app not found at $HELPER_SRC" >&2
  exit 1
fi

make_helper() {
  local suffix="$1"
  local id_suffix="$2"
  local name="Forge Helper${suffix}"
  local dest="$FRAMEWORKS/${name}.app"

  echo "assemble: helper ${name}"
  rm -rf "$dest"
  ditto "$HELPER_SRC" "$dest"
  mv "$dest/Contents/MacOS/Forge Helper" "$dest/Contents/MacOS/${name}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${name}" "$dest/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName ${name}" "$dest/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.forge.browser.helper${id_suffix}" "$dest/Contents/Info.plist"
  codesign --force --sign - --timestamp=none "$dest" 2>/dev/null || true
}

make_helper ""            ""
make_helper " (GPU)"      ".gpu"
make_helper " (Plugin)"   ".plugin"
make_helper " (Renderer)" ".renderer"
make_helper " (Alerts)"   ".alerts"

echo "assemble: signing app"
codesign --force --sign - --timestamp=none \
  "$FRAMEWORKS/Chromium Embedded Framework.framework" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || true

echo "assemble: done"
