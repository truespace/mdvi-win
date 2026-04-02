#!/usr/bin/env bash
# Cross-compile mdvi for Windows (x86_64-pc-windows-gnu) from macOS or Linux.
#
# Requirements (macOS):
#   brew install mingw-w64
#   rustup target add x86_64-pc-windows-gnu
#
# Requirements (Linux/Debian):
#   apt install gcc-mingw-w64-x86-64
#   rustup target add x86_64-pc-windows-gnu
#
# Usage:
#   ./scripts/build-win.sh           # debug build
#   ./scripts/build-win.sh --release # release build

set -euo pipefail

# Ensure cargo/rustup are on PATH (common install location)
export PATH="$HOME/.cargo/bin:$PATH"

TARGET="x86_64-pc-windows-gnu"
DIST_DIR="dist/windows"

# ── argument parsing ──────────────────────────────────────────────────────────
RELEASE=false
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=true ;;
    *) echo "unknown argument: $arg"; exit 1 ;;
  esac
done

# ── preflight checks ──────────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
  echo "error: cargo not found. Install Rust: https://rustup.rs"
  exit 1
fi

if ! rustup target list --installed | grep -q "$TARGET"; then
  echo "Adding Rust target $TARGET ..."
  rustup target add "$TARGET"
fi

if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
  echo "error: mingw-w64 not found."
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "  → brew install mingw-w64"
  else
    echo "  → apt install gcc-mingw-w64-x86-64"
  fi
  exit 1
fi

# ── build ─────────────────────────────────────────────────────────────────────
BUILD_ARGS=(--target "$TARGET")
if $RELEASE; then
  BUILD_ARGS+=(--release)
  PROFILE_DIR="release"
else
  PROFILE_DIR="debug"
fi

echo "Building mdvi for $TARGET (${PROFILE_DIR}) ..."
cargo build "${BUILD_ARGS[@]}"

# ── collect output ────────────────────────────────────────────────────────────
mkdir -p "$DIST_DIR"
cp "target/$TARGET/$PROFILE_DIR/mdvi.exe" "$DIST_DIR/mdvi.exe"

echo ""
echo "Done. Binary: $DIST_DIR/mdvi.exe"
