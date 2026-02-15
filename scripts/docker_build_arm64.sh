#!/bin/bash
# Build Matter SDK for linux-arm64 using Docker (native build on Apple Silicon)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MATTERLIX_ROOT="$(dirname "$SCRIPT_DIR")"
MATTER_SDK="$MATTERLIX_ROOT/deps/connectedhomeip"

echo "=== Docker Build: Matter SDK for linux-arm64 ==="
echo "Matter SDK: $MATTER_SDK"

# Verify Matter SDK exists
if [ ! -f "$MATTER_SDK/scripts/bootstrap.sh" ]; then
    echo "ERROR: Matter SDK not found at $MATTER_SDK"
    echo "Run 'mix deps.get' first"
    exit 1
fi

# Build the Docker image
echo "=== Building Docker image ==="
docker build \
    --platform linux/arm64 \
    -t matter-builder-arm64 \
    -f "$MATTERLIX_ROOT/docker/Dockerfile.arm64" \
    "$MATTERLIX_ROOT/docker/"

# Clean previous output
rm -rf "$MATTER_SDK/out/linux-arm64-light"

# Run the build with Matter SDK mounted
echo "=== Running build in Docker container ==="
docker run --rm \
    --platform linux/arm64 \
    -v "$MATTER_SDK:/matter/connectedhomeip" \
    matter-builder-arm64

echo ""
echo "=== Build artifacts ==="
if [ -f "$MATTER_SDK/out/linux-arm64-light/lib/libCHIP.a" ]; then
    ls -lh "$MATTER_SDK/out/linux-arm64-light/lib/libCHIP.a"
    echo "Generated headers: $MATTER_SDK/out/linux-arm64-light/gen/"
    echo "SUCCESS: Matter SDK built for linux-arm64"
else
    echo "ERROR: libCHIP.a not found. Check build output above."
    exit 1
fi
