#!/bin/bash
set -euo pipefail

# Verify linting prerequisites. Mirrors desktop-environment's bin/Invoke-LintDoctor.ps1 pattern.
#
# Usage: ./scripts/lint-doctor.sh
#        npm run lint:doctor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

FAILURES=0

check_cmd() {
    local name="$1"
    local install_hint="$2"
    if ! command -v "$name" &>/dev/null; then
        echo "FAIL: $name not found. Install: $install_hint"
        FAILURES=$((FAILURES + 1))
    else
        printf "  OK: %-18s %s\n" "$name" "$(command -v "$name")"
    fi
}

check_npm_dep() {
    local name="$1"
    if [ -f "node_modules/.bin/$name" ]; then
        local version
        version=$(node_modules/.bin/"$name" --version 2>/dev/null || echo "?")
        printf "  OK: %-18s %s\n" "$name" "$version"
    else
        echo "FAIL: $name not installed. Run: npm install"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "=== Lint Doctor ==="
echo ""

check_cmd "node"     "https://nodejs.org/ (>=20)"
check_cmd "npm"      "bundled with Node.js"

echo ""

check_cmd "shellcheck" "npm run setup (or https://github.com/koalaman/shellcheck)"
check_cmd "shfmt"       "npm run setup (or go install mvdan.cc/sh/v3/cmd/shfmt@latest)"

echo ""

if [ -d "node_modules/.bin" ]; then
    check_npm_dep "markdownlint-cli2"
    check_npm_dep "prettier"
else
    echo "FAIL: node_modules not found. Run: npm install"
    FAILURES=$((FAILURES + 1))
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "Found $FAILURES problem(s). Run 'npm run setup' to fix." >&2
    exit 1
fi

echo "All checks passed."
