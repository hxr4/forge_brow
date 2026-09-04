#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
cd "$ROOT/rust/forge-adblock"
echo "Building forge_adblock staticlib (release, arm64)..."
cargo build --release --target aarch64-apple-darwin
ls -lh target/aarch64-apple-darwin/release/libforge_adblock.a
