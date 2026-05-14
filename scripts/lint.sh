#!/bin/bash
set -euo pipefail

# Lint all bash and markdown files in the repo.
# Requires: shellcheck, shfmt, markdownlint-cli2 (or npx)
#
# Usage: ./scripts/lint.sh
#
# To auto-fix formatting:
#   ./scripts/lint.sh --fix

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

FIX_MODE=false
if [ "${1:-}" = "--fix" ]; then
    FIX_MODE=true
fi

# --- Tool availability ---
missing_tools=()

if ! command -v shellcheck &>/dev/null; then
    missing_tools+=("shellcheck (apt-get install shellcheck)")
fi

if ! command -v shfmt &>/dev/null; then
    missing_tools+=("shfmt (apt-get install shfmt or go install mvdan.cc/sh/v3/cmd/shfmt@latest)")
fi

# Determine markdownlint command
MARKDOWNLINT=""
if command -v markdownlint-cli2 &>/dev/null; then
    MARKDOWNLINT="markdownlint-cli2"
elif command -v npx &>/dev/null; then
    MARKDOWNLINT="npx --yes markdownlint-cli2"
else
    missing_tools+=("markdownlint-cli2 (npm install -g markdownlint-cli2)")
fi

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "Missing tools:" >&2
    for tool in "${missing_tools[@]}"; do
        echo "  - $tool" >&2
    done
    echo "" >&2
    echo "Install missing tools before running lint." >&2
    exit 1
fi

# --- Find files ---
mapfile -t SH_FILES < <(find . -type f -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' | sort)

FAILED=false

# --- Bash: shellcheck ---
echo "=== Bash: shellcheck ==="
if [ ${#SH_FILES[@]} -gt 0 ]; then
    shellcheck --external-sources "${SH_FILES[@]}" || FAILED=true
else
    echo "  No .sh files found."
fi

# --- Bash: shfmt ---
echo ""
echo "=== Bash: shfmt ==="
if [ ${#SH_FILES[@]} -gt 0 ]; then
    if $FIX_MODE; then
        shfmt -w -i 4 -ci -bn "${SH_FILES[@]}"
        echo "  Formatted."
    else
        shfmt -d -i 4 -ci -bn "${SH_FILES[@]}" || FAILED=true
    fi
else
    echo "  No .sh files found."
fi

# --- Markdown: markdownlint ---
echo ""
echo "=== Markdown: markdownlint ==="
if $FIX_MODE; then
    $MARKDOWNLINT --fix "**/*.md" "#node_modules" "#.git" || FAILED=true
else
    $MARKDOWNLINT "**/*.md" "#node_modules" "#.git" || FAILED=true
fi

# --- Result ---
echo ""
if $FAILED; then
    echo "Linting failed." >&2
    exit 1
else
    echo "All checks passed."
fi
