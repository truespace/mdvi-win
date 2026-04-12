#!/usr/bin/env bash
# Install mdvi to a directory on PATH.
#
# By default installs to /usr/local/bin (may require sudo).
# If that directory is not writable, falls back to ~/.local/bin.
#
# Usage:
#   ./scripts/install.sh                  # build from source and install
#   ./scripts/install.sh --prefix ~/.local # install to ~/.local/bin
#   ./scripts/install.sh --uninstall      # remove installed binary
#
# Environment variables:
#   PREFIX   override install prefix   (e.g. PREFIX=/opt/homebrew ./scripts/install.sh)
#   NO_BUILD skip cargo build, use existing target/release/mdvi

set -euo pipefail

# ── colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi

info()    { echo -e "${GREEN}•${RESET} $*"; }
warn()    { echo -e "${YELLOW}!${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }
heading() { echo -e "\n${BOLD}$*${RESET}"; }

# ── argument parsing ──────────────────────────────────────────────────────────
PREFIX="${PREFIX:-}"
UNINSTALL=false
NO_BUILD="${NO_BUILD:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --no-build) NO_BUILD=true; shift ;;
    *) error "unknown argument: $1" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY_NAME="mdvi"

# ── resolve install prefix ────────────────────────────────────────────────────
resolve_prefix() {
  if [[ -n "$PREFIX" ]]; then
    echo "$PREFIX"
    return
  fi
  if [[ -w "/usr/local/bin" ]] || sudo -n true 2>/dev/null; then
    echo "/usr/local"
  else
    echo "$HOME/.local"
  fi
}

PREFIX="$(resolve_prefix)"
BIN_DIR="${PREFIX}/bin"

# ── uninstall ─────────────────────────────────────────────────────────────────
if $UNINSTALL; then
  heading "Uninstalling ${BINARY_NAME}"
  TARGET_BIN="${BIN_DIR}/${BINARY_NAME}"
  if [[ ! -f "$TARGET_BIN" ]]; then
    warn "${BINARY_NAME} not found at ${TARGET_BIN}"
    exit 0
  fi
  if [[ -w "$BIN_DIR" ]]; then
    rm -f "$TARGET_BIN"
  else
    sudo rm -f "$TARGET_BIN"
  fi
  info "Removed ${TARGET_BIN}"
  exit 0
fi

# ── preflight ─────────────────────────────────────────────────────────────────
heading "Installing ${BINARY_NAME}"

OS="$(uname -s)"
ARCH="$(uname -m)"
info "Platform: ${OS} / ${ARCH}"

if ! command -v cargo &>/dev/null && [[ -f "$HOME/.cargo/bin/cargo" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# ── build ─────────────────────────────────────────────────────────────────────
RELEASE_BIN="${REPO_ROOT}/target/release/${BINARY_NAME}"

if [[ "$NO_BUILD" == "true" ]]; then
  info "Skipping build (--no-build)"
  [[ -f "$RELEASE_BIN" ]] || error "No binary at ${RELEASE_BIN}. Run without --no-build first."
else
  if ! command -v cargo &>/dev/null; then
    error "cargo not found. Install Rust from https://rustup.rs then re-run."
  fi
  info "Building release binary (this takes a moment on first run)..."
  cargo build --release --manifest-path "${REPO_ROOT}/Cargo.toml" --quiet
  info "Build complete."
fi

# ── install ───────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"

install_binary() {
  if [[ -w "$BIN_DIR" ]]; then
    install -m 755 "$RELEASE_BIN" "${BIN_DIR}/${BINARY_NAME}"
  else
    info "Writing to ${BIN_DIR} requires sudo..."
    sudo install -m 755 "$RELEASE_BIN" "${BIN_DIR}/${BINARY_NAME}"
  fi
}

install_binary
INSTALLED="${BIN_DIR}/${BINARY_NAME}"
VERSION="$("$INSTALLED" --version 2>/dev/null || echo "(unknown)")"

info "Installed → ${INSTALLED}"
info "Version   : ${VERSION}"

# ── PATH hint ─────────────────────────────────────────────────────────────────
if ! echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
  echo ""
  warn "${BIN_DIR} is not in your PATH. Add this to your shell config:"
  echo ""
  echo "    export PATH=\"${BIN_DIR}:\$PATH\""
  echo ""
  SHELL_RC=""
  case "${SHELL:-}" in
    */zsh)  SHELL_RC="~/.zshrc" ;;
    */bash) SHELL_RC="~/.bashrc" ;;
  esac
  [[ -n "$SHELL_RC" ]] && warn "Then run: source ${SHELL_RC}"
fi

echo ""
echo -e "${GREEN}${BOLD}Done!${RESET} Run: ${BOLD}mdvi <file.md>${RESET}"
