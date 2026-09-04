#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Forge Browser bootstrap ==="

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools missing. Run: xcode-select --install" >&2
  exit 1
fi
echo "xcode:  $(xcode-select -p)"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew missing. Install from https://brew.sh then re-run." >&2
  exit 1
fi

for pkg in cmake ninja xcodegen; do
  if command -v "$pkg" >/dev/null 2>&1; then
    echo "$pkg: present"
  else
    echo "installing $pkg ..."
    brew install "$pkg"
  fi
done

if command -v cargo >/dev/null 2>&1; then
  echo "cargo:  $(cargo --version)"
else
  echo "installing rust ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  export PATH="$HOME/.cargo/bin:$PATH"
fi
"$HOME/.cargo/bin/rustup" target add aarch64-apple-darwin >/dev/null 2>&1 || true

bash "$ROOT/scripts/fetch-filters.sh"
bash "$ROOT/scripts/fetch-cef.sh"
bash "$ROOT/scripts/build-adblock.sh"

echo "=== bootstrap complete ==="
