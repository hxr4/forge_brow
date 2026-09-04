#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD="$ROOT/third_party"
PLATFORM="macosarm64"
mkdir -p "$THIRD"

if [ -L "$THIRD/cef" ] && [ -d "$THIRD/cef/include" ]; then
  echo "CEF already present: $(readlink "$THIRD/cef")"
else
  echo "Fetching CEF build index..."
  curl -fsSL "https://cef-builds.spotifycdn.com/index.json" -o "$THIRD/cef_index.json"

  DIST_TYPE="${CEF_DIST_TYPE:-standard}"
  eval "$(python3 - "$THIRD/cef_index.json" "$PLATFORM" "$DIST_TYPE" <<'PY'
import json, sys
idx = json.load(open(sys.argv[1]))
plat = idx[sys.argv[2]]
want = sys.argv[3]
for v in plat["versions"]:
    if v.get("channel") != "stable":
        continue
    for f in v["files"]:
        if f["type"] == want:
            print('CEF_VERSION=%s' % v["cef_version"])
            print('CEF_FILE="%s"' % f["name"])
            print('CEF_SHA1=%s' % f["sha1"])
            print('CEF_CHROMIUM=%s' % v.get("chromium_version", "unknown"))
            sys.exit(0)
sys.exit("no stable %s build for %s" % (want, sys.argv[2]))
PY
)"

  echo "Selected CEF $CEF_VERSION (Chromium $CEF_CHROMIUM)"
  ARCHIVE="$THIRD/$CEF_FILE"
  if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading $CEF_FILE ..."
    ENC="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$CEF_FILE")"
    curl -fL --no-progress-meter "https://cef-builds.spotifycdn.com/$ENC" -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
  fi

  echo "Verifying sha1..."
  GOT="$(shasum -a 1 "$ARCHIVE" | awk '{print $1}')"
  if [ "$GOT" != "$CEF_SHA1" ]; then
    echo "sha1 mismatch: expected $CEF_SHA1 got $GOT" >&2
    exit 1
  fi

  echo "Extracting (this takes a minute)..."
  tar -xjf "$ARCHIVE" -C "$THIRD"
  DIR="$THIRD/$(basename "$CEF_FILE" .tar.bz2)"
  [ -d "$DIR" ] || { echo "extracted dir not found: $DIR" >&2; exit 1; }
  rm -f "$THIRD/cef"
  ln -s "$(basename "$DIR")" "$THIRD/cef"
  printf '%s' "$CEF_VERSION" > "$THIRD/cef_version.txt"
fi

if [ -d "$THIRD/cef/Debug" ]; then
  echo "Removing Debug binaries to reclaim disk..."
  rm -rf "$THIRD/cef/Debug"
fi

CEFDIR="$THIRD/cef"
WRAPPER="$(find "$CEFDIR/build" -name libcef_dll_wrapper.a 2>/dev/null | head -n1 || true)"
if [ -n "$WRAPPER" ]; then
  echo "libcef_dll_wrapper already built"
else
  echo "Configuring CEF cmake..."
  cmake -S "$CEFDIR" -B "$CEFDIR/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPROJECT_ARCH=arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64
  echo "Building libcef_dll_wrapper..."
  cmake --build "$CEFDIR/build" --target libcef_dll_wrapper
  WRAPPER="$(find "$CEFDIR/build" -name libcef_dll_wrapper.a | head -n1)"
fi

echo "--- CEF summary ---"
echo "version:   $(cat "$THIRD/cef_version.txt" 2>/dev/null || echo unknown)"
echo "framework: $([ -d "$CEFDIR/Release/Chromium Embedded Framework.framework" ] && echo present || echo MISSING)"
echo "sandbox:   provided by the framework (CefScopedSandboxContext, CEF 144+)"
echo "wrapper:   ${WRAPPER:-MISSING}"
