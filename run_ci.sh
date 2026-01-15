#!/bin/bash
set -e

echo "Building CI Docker image..."
docker build -f Dockerfile.ci -t matterlix-ci .

echo "Running tests with AddressSanitizer (ASan)..."
# We run with --privileged or specific caps if needed, but usually default is fine for ASan.
# We might need --cap-add=SYS_PTRACE for some sanitizers, but ASan is usually okay.
docker run --rm matterlix-ci
