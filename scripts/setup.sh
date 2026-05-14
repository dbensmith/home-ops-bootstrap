#!/bin/bash
set -euo pipefail

# Cross-platform setup: installs shellcheck + shfmt binaries (no apt).
# npm dependencies installed via package.json.
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

# --- 1. npm dependencies ---
echo "=== Installing npm dependencies ==="
npm install

# --- 2. shellcheck ---
SHELLCHECK_VERSION="0.10.0"

if ! command -v shellcheck &>/dev/null; then
    echo ""
    echo "=== Installing shellcheck v${SHELLCHECK_VERSION} ==="

    case "$OS" in
        Linux)
            URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${ARCH}.tar.xz"
            curl -sSfL "$URL" | tar -xJ -C /tmp
            sudo install -m 755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/
            rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
            ;;
        Darwin)
            URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.darwin.${ARCH}.tar.xz"
            curl -sSfL "$URL" | tar -xJ -C /tmp
            sudo install -m 755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/
            rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
            ;;
        *)
            echo "Unsupported OS: $OS. Install shellcheck manually: https://github.com/koalaman/shellcheck"
            ;;
    esac
else
    echo "  shellcheck already installed: $(command -v shellcheck)"
fi

# --- 3. shfmt ---
SHFMT_VERSION="3.10.0"

if ! command -v shfmt &>/dev/null; then
    echo ""
    echo "=== Installing shfmt v${SHFMT_VERSION} ==="

    case "$OS" in
        Linux)
            URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${ARCH}"
            sudo curl -sSfL "$URL" -o /usr/local/bin/shfmt
            sudo chmod +x /usr/local/bin/shfmt
            ;;
        Darwin)
            URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_darwin_${ARCH}"
            sudo curl -sSfL "$URL" -o /usr/local/bin/shfmt
            sudo chmod +x /usr/local/bin/shfmt
            ;;
        *)
            echo "Unsupported OS: $OS. Install shfmt manually: go install mvdan.cc/sh/v3/cmd/shfmt@latest"
            ;;
    esac
else
    echo "  shfmt already installed: $(command -v shfmt)"
fi

echo ""
echo "Setup complete. Run: npm run lint"
