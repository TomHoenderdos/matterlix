#!/bin/bash
# Build Matter SDK inside Docker container
# Uses a separate temp environment dir to avoid touching the host's .environment
#
# Environment variables:
#   MATTER_GN_ROOT      - GN root path (default: examples/lighting-app/linux)
#   MATTER_OUTPUT_NAME   - Output directory suffix (default: light)
#   MATTER_EXECUTABLE    - Executable name (default: chip-lighting-app)
set -e

MATTER_SDK="/matter/connectedhomeip"
MATTER_GN_ROOT="${MATTER_GN_ROOT:-examples/lighting-app/linux}"
MATTER_OUTPUT_NAME="${MATTER_OUTPUT_NAME:-light}"
MATTER_EXECUTABLE="${MATTER_EXECUTABLE:-chip-lighting-app}"
OUTPUT_DIR="$MATTER_SDK/out/linux-arm64-${MATTER_OUTPUT_NAME}"
# Use a temp dir for the environment - NEVER touch the host's .environment
ENV_DIR="/tmp/matter-env"

echo "=== Building Matter SDK for linux-arm64 (native) ==="
echo "Profile: $MATTER_OUTPUT_NAME"
echo "GN root: $MATTER_GN_ROOT"
echo "Executable: $MATTER_EXECUTABLE"

cd "$MATTER_SDK"

# Unset JAVA_HOME to avoid JNI compilation issues
unset JAVA_HOME

# Create minimal .environment structure in a temp dir (not on the volume mount)
echo "=== Setting up minimal build environment ==="
mkdir -p "$ENV_DIR/cipd/packages/pigweed"
mkdir -p "$ENV_DIR/cipd/packages/zap"
mkdir -p "$ENV_DIR/cipd/packages/arm"
mkdir -p "$ENV_DIR/packages"
mkdir -p "$ENV_DIR/pigweed-venv"
mkdir -p "$ENV_DIR/build_overrides"

# Generate the pigweed_environment.gni that GN requires
cat > "$ENV_DIR/build_overrides/pigweed_environment.gni" << 'GNIEOF'
declare_args() {
  pw_env_setup_CIPD_ARM = get_path_info("../cipd/packages/arm", "abspath")
  pw_env_setup_CIPD_PIGWEED = get_path_info("../cipd/packages/pigweed", "abspath")
  pw_env_setup_CIPD_ZAP = get_path_info("../cipd/packages/zap", "abspath")
  pw_env_setup_PACKAGE_ROOT = get_path_info("../packages", "abspath")
  pw_env_setup_VIRTUAL_ENV = get_path_info("../pigweed-venv", "abspath")
}
GNIEOF

# Install Python dependencies needed by Matter SDK build scripts
echo "=== Installing Python build dependencies ==="
pip install --break-system-packages python_path click coloredlogs lark jinja2 lxml

# Download ZAP code generator for linux-arm64
ZAP_VERSION="v2025.10.23-nightly"
ZAP_DIR="/tmp/zap"
echo "=== Downloading ZAP $ZAP_VERSION for linux-arm64 ==="
mkdir -p "$ZAP_DIR"
wget -q "https://github.com/project-chip/zap/releases/download/$ZAP_VERSION/zap-linux-arm64.zip" -O /tmp/zap.zip
unzip -q -o /tmp/zap.zip -d "$ZAP_DIR"
chmod +x "$ZAP_DIR/zap-cli" 2>/dev/null || true
rm /tmp/zap.zip
export ZAP_INSTALL_PATH="$ZAP_DIR"
echo "ZAP installed at: $ZAP_DIR"
echo "zap-cli: $(ls -la $ZAP_DIR/zap-cli 2>/dev/null || echo 'not found')"

# Point GN to our temp environment instead of the host's .environment
export _PW_ACTUAL_ENVIRONMENT_ROOT="$ENV_DIR"
export PW_PROJECT_ROOT="$MATTER_SDK"
export PW_ROOT="$MATTER_SDK/third_party/pigweed/repo"

echo "GN: $(which gn)"
echo "Ninja: $(which ninja)"

echo "=== Running GN gen ==="
gn gen "$OUTPUT_DIR" --root="$MATTER_GN_ROOT" --args='
  target_cpu="arm64"
  target_os="linux"
  treat_warnings_as_errors=false
  is_debug=false
  chip_config_network_layer_ble=true
  chip_enable_ble=true
  is_clang=false
'

echo "=== Building with Ninja (this may take a while) ==="
ninja -C "$OUTPUT_DIR"

echo "=== Generating build manifests ==="
# Extract linked .o and .a files from the ninja build graph
# These manifests are used by scripts/gen_matter_includes.sh to generate matter_sdk_includes.mk
NINJA_FILE="$OUTPUT_DIR/obj/${MATTER_EXECUTABLE}.ninja"
if [ ! -f "$NINJA_FILE" ]; then
    # Some executables use a different ninja file name pattern
    NINJA_FILE=$(find "$OUTPUT_DIR/obj" -name "*.ninja" -exec grep -l "build ./${MATTER_EXECUTABLE}" {} \; | head -1)
fi

if [ -f "$NINJA_FILE" ]; then
    grep "build ./${MATTER_EXECUTABLE}" "$NINJA_FILE" | tr ' ' '\n' | grep -E '\.o$' | sort > "$OUTPUT_DIR/linked_objects.txt"
    grep "build ./${MATTER_EXECUTABLE}" "$NINJA_FILE" | tr ' ' '\n' | grep -E '\.a$' | sort > "$OUTPUT_DIR/linked_libs.txt"
    echo "Manifest: $(wc -l < "$OUTPUT_DIR/linked_objects.txt") object files, $(wc -l < "$OUTPUT_DIR/linked_libs.txt") libraries"
else
    echo "WARNING: Could not find ninja file for $MATTER_EXECUTABLE"
fi

echo "=== Build complete ==="
echo "Output directory: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR/lib/" 2>/dev/null || echo "No lib/ directory found"
ls -lh "$OUTPUT_DIR/$MATTER_EXECUTABLE" 2>/dev/null || echo "No executable found"
echo "=== Done ==="
