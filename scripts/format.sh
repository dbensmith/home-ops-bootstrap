#!/bin/bash
set -euo pipefail

# Format all files using super-linter in fix mode (same as CI, local via docker/podman).
# Mirrors desktop-environment's bin/Invoke-SuperLinter.ps1 -Fix.
#
# Usage: ./scripts/format.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ghcr.io/super-linter/super-linter:v8.6.0"

# Detect container runtime
RUNTIME=""
if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "Error: neither podman nor docker found in PATH." >&2
    echo "Install podman or docker to run super-linter locally." >&2
    exit 1
fi

echo "Pulling $IMAGE..."
"$RUNTIME" pull "$IMAGE"

echo "Running super-linter in fix mode..."
"$RUNTIME" run --rm \
    --env-file "$REPO_ROOT/.github/super-linter.env" \
    -e RUN_LOCAL=true \
    -e FIX_JSON_PRETTIER=true \
    -e FIX_JSONC_PRETTIER=true \
    -e FIX_MARKDOWN=true \
    -e FIX_MARKDOWN_PRETTIER=true \
    -e FIX_YAML_PRETTIER=true \
    -v "$REPO_ROOT:/tmp/lint:rw" \
    "$IMAGE"
