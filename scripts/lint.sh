#!/bin/bash
set -euo pipefail

# Run all linters and formatters. Aggregates results — runs everything
# even if earlier steps fail, exits non-zero if any failed.
#
# Mirrors desktop-environment's bin/Invoke-Linters.ps1 pattern.
#
# Usage: ./scripts/lint.sh         # Check mode
#        ./scripts/lint.sh --fix   # Auto-fix mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Prepend node_modules/.bin to PATH so npm-installed tools are found
if [ -d "node_modules/.bin" ]; then
    export PATH="$REPO_ROOT/node_modules/.bin:$PATH"
fi

FIX_MODE=false
if [ "${1:-}" = "--fix" ]; then
    FIX_MODE=true
fi

# Find shell scripts
mapfile -t SH_FILES < <(find . -type f -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' | sort)

FAILURES=()

run_check() {
    local name="$1"
    shift
    echo ""
    echo "--- $name ---"
    if ! "$@"; then
        FAILURES+=("$name")
    fi
}

# --- Bash: shellcheck ---
if [ ${#SH_FILES[@]} -gt 0 ]; then
    run_check "shellcheck" shellcheck --external-sources "${SH_FILES[@]}"

    if $FIX_MODE; then
        run_check "shfmt (format)" shfmt -w -i 4 -ci -bn "${SH_FILES[@]}"
    else
        run_check "shfmt (check)" shfmt -d -i 4 -ci -bn "${SH_FILES[@]}"
    fi
fi

# --- Markdown: markdownlint ---
if $FIX_MODE; then
    run_check "markdownlint" markdownlint-cli2 --fix "**/*.md" "#node_modules" "#.git"
else
    run_check "markdownlint" markdownlint-cli2 "**/*.md" "#node_modules" "#.git"
fi

# --- Formatting: prettier ---
if $FIX_MODE; then
    run_check "prettier" prettier --write --ignore-unknown .
else
    run_check "prettier" prettier --check --ignore-unknown .
fi

# --- Summary ---
echo ""
echo "--- Summary ---"
if [ ${#FAILURES[@]} -gt 0 ]; then
    echo "Failed: ${FAILURES[*]}" >&2
    exit 1
fi
echo "All checks passed."
