#!/bin/bash
# Cross-compile Matter SDK for linux-arm64 (Nerves RPi Zero 2 W)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MATTERLIX_ROOT="$(dirname "$SCRIPT_DIR")"
MATTER_SDK="$MATTERLIX_ROOT/deps/connectedhomeip"
OUTPUT_DIR="$MATTER_SDK/out/linux-arm64-light"

# Nerves toolchain (auto-detect or use env vars)
TOOLCHAIN_BIN="${NERVES_TOOLCHAIN:-$HOME/.nerves/artifacts/nerves_toolchain_aarch64_nerves_linux_gnu-darwin_arm-13.2.0}/bin"
SYSROOT="${NERVES_SDK_SYSROOT:-$HOME/.nerves/artifacts/custom_system_rpi0_2-portable-1.33.0/staging}"

echo "=== Matter SDK Cross-Compilation for linux-arm64 ==="
echo "Toolchain: $TOOLCHAIN_BIN"
echo "Sysroot:   $SYSROOT"
echo "Output:    $OUTPUT_DIR"

# Verify toolchain exists
if [ ! -f "$TOOLCHAIN_BIN/aarch64-nerves-linux-gnu-gcc" ]; then
    echo "ERROR: Nerves toolchain not found at $TOOLCHAIN_BIN"
    echo "Set NERVES_TOOLCHAIN to the toolchain bin directory"
    exit 1
fi

# Verify sysroot exists
if [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Sysroot not found at $SYSROOT"
    echo "Set NERVES_SDK_SYSROOT to the Nerves system staging directory"
    exit 1
fi

# Set up Matter SDK build environment
cd "$MATTER_SDK"

# Set Pigweed environment variables manually to avoid activate.sh path mismatch issues
# (activate.sh fails if the checkout was moved from its original path)
export _PW_ACTUAL_ENVIRONMENT_ROOT="$MATTER_SDK/.environment"
export PW_PROJECT_ROOT="$MATTER_SDK"
export PW_ROOT="$MATTER_SDK/third_party/pigweed/repo"
export PW_PACKAGE_ROOT="$MATTER_SDK/.environment/packages"
export PATH="$MATTER_SDK/.environment/cipd/packages/pigweed:$MATTER_SDK/.environment/cipd/packages/pigweed/bin:$MATTER_SDK/.environment/cipd:$MATTER_SDK/.environment/pigweed-venv/bin:$PATH"

# Verify tools are available
if ! command -v gn &>/dev/null; then
    echo "ERROR: gn not found at $MATTER_SDK/.environment/cipd/packages/pigweed/"
    echo "Run 'cd $MATTER_SDK && source scripts/bootstrap.sh' first"
    exit 1
fi
echo "GN: $(which gn)"
echo "Ninja: $(which ninja)"

# Unset JAVA_HOME to prevent macOS JDK headers from being used in cross-compilation
unset JAVA_HOME

# Generate build with Nerves cross-compiler
gn gen "$OUTPUT_DIR" --root=examples/lighting-app/linux --args="
  target_cpu=\"arm64\"
  target_os=\"linux\"
  treat_warnings_as_errors=false
  sysroot=\"$SYSROOT\"
  target_cc=\"$TOOLCHAIN_BIN/aarch64-nerves-linux-gnu-gcc\"
  target_cxx=\"$TOOLCHAIN_BIN/aarch64-nerves-linux-gnu-g++\"
  target_ar=\"$TOOLCHAIN_BIN/aarch64-nerves-linux-gnu-ar\"
  custom_toolchain=\"//third_party/connectedhomeip/build/toolchain/custom\"
  is_debug=false
"

# Build (produces lib/libCHIP.a + gen/ headers)
echo "=== Building Matter SDK (this may take a while) ==="
ninja -C "$OUTPUT_DIR"

echo "=== Build complete ==="
echo "libCHIP.a: $OUTPUT_DIR/lib/libCHIP.a"
