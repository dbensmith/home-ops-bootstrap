#!/bin/bash
set -euo pipefail

# Cross-platform setup: installs shellcheck + shfmt binaries into .bin/ (no sudo).
#
# Usage: ./scripts/setup.sh
#        npm run setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

OS="$(uname -s)"
ARCH="$(uname -m)"

# Normalize arch
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

# --- 1. Create .bin directory ---
mkdir -p .bin

# --- 2. npm dependencies ---
echo "=== Installing npm dependencies ==="
npm install

# --- 3. shellcheck ---
SHELLCHECK_VERSION="0.10.0"

if ! command -v .bin/shellcheck &>/dev/null; then
    echo ""
    echo "=== Installing shellcheck v${SHELLCHECK_VERSION} into .bin/ ==="
    case "$OS" in
        Linux)
            URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${ARCH}.tar.xz"
            curl -sSfL "$URL" | tar -xJ -C /tmp
            install -m 755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" .bin/
            rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
            ;;
        Darwin)
            URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.darwin.${ARCH}.tar.xz"
            curl -sSfL "$URL" | tar -xJ -C /tmp
            install -m 755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" .bin/
            rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
            ;;
        *)
            echo "Unsupported OS: $OS. Install shellcheck manually: https://github.com/koalaman/shellcheck" >&2
            exit 1
            ;;
    esac
else
    echo "  shellcheck already installed: .bin/shellcheck"
fi

# --- 4. shfmt ---
SHFMT_VERSION="3.10.0"

if ! command -v .bin/shfmt &>/dev/null; then
    echo ""
    echo "=== Installing shfmt v${SHFMT_VERSION} into .bin/ ==="
    case "$OS" in
        Linux)
            URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${ARCH}"
            curl -sSfL "$URL" -o .bin/shfmt
            chmod +x .bin/shfmt
            ;;
        Darwin)
            URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_darwin_${ARCH}"
            curl -sSfL "$URL" -o .bin/shfmt
            chmod +x .bin/shfmt
            ;;
        *)
            echo "Unsupported OS: $OS. Install shfmt manually: go install mvdan.cc/sh/v3/cmd/shfmt@latest" >&2
            exit 1
            ;;
    esac
else
    echo "  shfmt already installed: .bin/shfmt"
fi

echo ""
echo "Setup complete. Run: npm run lint"
