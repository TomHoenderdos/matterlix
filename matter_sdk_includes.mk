# Matter SDK Include Paths
# Supports both host and cross-compilation builds
# To regenerate: Run Matter SDK build and extract includes from compile_commands.json

MATTER_SDK_ROOT = $(shell pwd)/deps/connectedhomeip

# Detect target platform dynamically
ifeq ($(CROSSCOMPILE),1)
    # Cross-compilation: determine target from Nerves environment
    ifeq ($(findstring aarch64,$(TARGET_ARCH)),aarch64)
        MATTER_TARGET = linux-arm64-light
    else ifeq ($(findstring arm,$(TARGET_ARCH)),arm)
        MATTER_TARGET = linux-arm-light
    else
        MATTER_TARGET = linux-x64-light
    endif
else
    # Host compilation: detect from uname
    UNAME_S := $(shell uname -s)
    UNAME_M := $(shell uname -m)

    ifeq ($(UNAME_S),Darwin)
        ifeq ($(UNAME_M),arm64)
            MATTER_TARGET = darwin-arm64-light
        else
            MATTER_TARGET = darwin-x64-light
        endif
    else ifeq ($(UNAME_S),Linux)
        ifeq ($(UNAME_M),aarch64)
            MATTER_TARGET = linux-arm64-light
        else ifeq ($(UNAME_M),armv7l)
            MATTER_TARGET = linux-arm-light
        else
            MATTER_TARGET = linux-x64-light
        endif
    else
        # Fallback
        MATTER_TARGET = linux-x64-light
    endif
endif

MATTER_BUILD_DIR = $(MATTER_SDK_ROOT)/out/$(MATTER_TARGET)

# Core Matter SDK includes
MATTER_INCLUDES = \
    -I$(MATTER_SDK_ROOT)/src \
    -I$(MATTER_SDK_ROOT)/src/include \
    -I$(MATTER_SDK_ROOT)/config/standalone \
    -I$(MATTER_SDK_ROOT)/examples \
    -I$(MATTER_SDK_ROOT)/examples/platform/linux \
    -I$(MATTER_SDK_ROOT)/examples/providers \
    -I$(MATTER_SDK_ROOT)/examples/lighting-app/lighting-common/include \
    -I$(MATTER_SDK_ROOT)/examples/lighting-app/linux/include \
    -I$(MATTER_SDK_ROOT)/examples/common/tracing

# Third-party includes
MATTER_INCLUDES += \
    -I$(MATTER_SDK_ROOT)/third_party/nlassert/repo/include \
    -I$(MATTER_SDK_ROOT)/third_party/nlio/repo/include \
    -I$(MATTER_SDK_ROOT)/third_party/nlfaultinjection/include \
    -I$(MATTER_SDK_ROOT)/third_party/jsoncpp/repo/include \
    -I$(MATTER_SDK_ROOT)/third_party/boringssl/repo/src/include

# Pigweed includes (Matter uses Pigweed for various utilities)
PIGWEED_ROOT = $(MATTER_SDK_ROOT)/third_party/pigweed/repo
MATTER_INCLUDES += \
    -I$(PIGWEED_ROOT)/pw_assert/public \
    -I$(PIGWEED_ROOT)/pw_assert/assert_compatibility_public_overrides \
    -I$(PIGWEED_ROOT)/pw_base64/public \
    -I$(PIGWEED_ROOT)/pw_bytes/public \
    -I$(PIGWEED_ROOT)/pw_containers/public \
    -I$(PIGWEED_ROOT)/pw_function/public \
    -I$(PIGWEED_ROOT)/pw_log/public \
    -I$(PIGWEED_ROOT)/pw_metric/public \
    -I$(PIGWEED_ROOT)/pw_numeric/public \
    -I$(PIGWEED_ROOT)/pw_polyfill/public \
    -I$(PIGWEED_ROOT)/pw_preprocessor/public \
    -I$(PIGWEED_ROOT)/pw_result/public \
    -I$(PIGWEED_ROOT)/pw_span/public \
    -I$(PIGWEED_ROOT)/pw_status/public \
    -I$(PIGWEED_ROOT)/pw_string/public \
    -I$(PIGWEED_ROOT)/pw_tokenizer/public \
    -I$(PIGWEED_ROOT)/pw_toolchain/public \
    -I$(PIGWEED_ROOT)/pw_varint/public \
    -I$(PIGWEED_ROOT)/third_party/fuchsia/repo/sdk/lib/stdcompat/include

# Generated includes from build
MATTER_INCLUDES += \
    -I$(MATTER_BUILD_DIR)/gen/include \
    -I$(MATTER_BUILD_DIR)/gen

# Matter SDK library
MATTER_LIBS = -L$(MATTER_BUILD_DIR)/lib -lCHIP

# Platform-specific libraries
ifeq ($(shell uname -s),Darwin)
    ifeq ($(CROSSCOMPILE),1)
        # Cross-compiling from Darwin to Linux
        MATTER_LIBS += -lpthread -ldl -lrt
    else
        # Native Darwin build
        MATTER_LIBS += -framework CoreFoundation -framework CoreBluetooth -framework IOKit -framework Security
    endif
else
    # Linux host or target
    MATTER_LIBS += -lpthread -ldl -lrt
endif
