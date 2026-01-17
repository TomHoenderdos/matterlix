# Makefile for building the Matter NIF
#
# Makefile targets:
# all - build the NIF
# clean - remove build artifacts
#
# Environment variables:
# CROSSCOMPILE - set to 1 for cross-compilation (Nerves target builds)
# ERL_EI_INCLUDE_DIR - include path for erl_nif.h
# ERL_EI_LIBDIR - library path for Erlang
# CC - C compiler
# CXX - C++ compiler
# MATTER_SDK_ENABLED - set to 1 to enable Matter SDK integration (default: 0)

# Configuration
NIF_NAME = matter_nif
PREFIX = $(MIX_APP_PATH)/priv
BUILD = $(MIX_APP_PATH)/obj

# Matter SDK integration (disabled by default for stub builds)
MATTER_SDK_ENABLED ?= 0

# AddressSanitizer for security/memory testing
ASAN ?= 0

# Erlang paths - detect automatically if not set
ERL_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop)

# Compiler settings
ifeq ($(CROSSCOMPILE),1)
	# Cross-compilation for Nerves target
	CC ?= $(CROSSCOMPILE_PREFIX)gcc
	CXX ?= $(CROSSCOMPILE_PREFIX)g++
else
	# Host compilation
	CC ?= cc
	CXX ?= c++
endif

# Base compiler flags
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
CFLAGS += -I$(ERL_INCLUDE_DIR) -I./c_src
CFLAGS += -fPIC

CXXFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
CXXFLAGS += -I$(ERL_INCLUDE_DIR) -I./c_src
CXXFLAGS += -fPIC -std=c++17

# Enable ASan if requested
ifeq ($(ASAN),1)
	CFLAGS += -fsanitize=address -g -fno-omit-frame-pointer
	CXXFLAGS += -fsanitize=address -g -fno-omit-frame-pointer
	LDFLAGS += -fsanitize=address
endif

# Platform-specific linker flags
# When cross-compiling, always use Linux flags regardless of host OS
ifeq ($(CROSSCOMPILE),1)
	LDFLAGS += -shared
	NIF_EXT = so
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Darwin)
		LDFLAGS += -undefined dynamic_lookup -dynamiclib
		NIF_EXT = so
	else
		LDFLAGS += -shared
		NIF_EXT = so
	endif
endif

# Include Matter SDK configuration if enabled
ifeq ($(MATTER_SDK_ENABLED),1)
    -include matter_sdk_includes.mk
    CXXFLAGS += $(MATTER_INCLUDES) -DMATTER_SDK_ENABLED=1
    LDFLAGS += $(MATTER_LIBS)
endif

# Source files
C_SOURCES = $(wildcard c_src/*.c)
CXX_SOURCES = $(wildcard c_src/*.cpp)

# Object files
C_OBJECTS = $(patsubst c_src/%.c,$(BUILD)/%.o,$(C_SOURCES))
CXX_OBJECTS = $(patsubst c_src/%.cpp,$(BUILD)/%.o,$(CXX_SOURCES))
OBJECTS = $(C_OBJECTS) $(CXX_OBJECTS)

# Target
NIF = $(PREFIX)/$(NIF_NAME).$(NIF_EXT)

# Rules
.PHONY: all clean matter-sdk-check

all: $(PREFIX) $(BUILD) $(NIF)

matter-sdk-check:
ifeq ($(MATTER_SDK_ENABLED),1)
	@if [ ! -f "$(MATTER_BUILD_DIR)/lib/libCHIP.a" ]; then \
		echo "Error: Matter SDK not built. Run the following first:"; \
		echo "  cd deps/connectedhomeip && source scripts/activate.sh"; \
		echo "  python3 scripts/build/build_examples.py --target darwin-arm64-light build"; \
		exit 1; \
	fi
endif

$(PREFIX):
	mkdir -p $@

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: c_src/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/%.o: c_src/%.cpp matter-sdk-check
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(NIF): $(OBJECTS)
ifeq ($(CXX_SOURCES),)
	$(CC) $(LDFLAGS) -o $@ $^
else
	$(CXX) $(LDFLAGS) -o $@ $^
endif

clean:
	rm -rf $(BUILD) $(NIF)
