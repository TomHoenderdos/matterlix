# Matterlix Project Context

## Project Overview

**Matterlix** is a Nerves-based Elixir application designed to integrate the **Matter** (Connected Home over IP) smart home protocol. It enables embedded Linux devices (like Raspberry Pi) to function as Matter nodes using Elixir.

The project bridges the C++ Matter SDK (`connectedhomeip`) with Elixir using **Native Implemented Functions (NIFs)**.

## Architecture

The system uses a layered architecture:

1.  **Elixir Layer (`lib/`)**:
    *   `Matterlix.Matter` (GenServer): High-level API for application logic.
    *   `Matterlix.Matter.NIF`: Low-level bindings to the C++ code.
2.  **NIF Layer (`c_src/`)**:
    *   `matter_nif.cpp`: C++ code that translates Elixir calls into Matter SDK C++ API calls.
3.  **Matter SDK (`deps/connectedhomeip`)**:
    *   The official open-source Matter implementation (C++).

## Building and Running

### Prerequisites

*   Elixir 1.14+ / Erlang OTP 25+
*   C++17 compiler
*   **For Matter SDK**: CMake 3.16+, Ninja, Python 3.8+

### 1. Stub Mode (Fast / Development)

By default, the project builds in "Stub Mode". This compiles the NIF skeleton without linking the heavy Matter SDK. Useful for working on the Elixir logic or NIF interface without the full compilation cost.

```bash
mix deps.get
mix compile
mix test
```

### 2. Matter SDK Mode (Full Functionality)

To link against the real Matter SDK:

1.  **Setup SDK**:
    ```bash
    mkdir -p deps
    git clone --depth 1 https://github.com/project-chip/connectedhomeip.git deps/connectedhomeip
    cd deps/connectedhomeip
    python3 scripts/checkout_submodules.py --shallow --platform linux
    source scripts/bootstrap.sh -p linux
    # Build SDK for host (example for macOS ARM64)
    python3 scripts/build/build_examples.py --target darwin-arm64-light build
    ```

2.  **Compile Elixir with SDK**:
    ```bash
    export MATTER_SDK_ENABLED=1
    mix compile
    ```

### 3. Nerves Firmware (Target)

To build firmware for a device (e.g., Raspberry Pi 4):

```bash
export MIX_TARGET=rpi4
mix deps.get
mix firmware
# mix burn # to write to SD card
```

## Key Files & Directories

*   **`mix.exs`**: Project configuration, dependencies, and Nerves system definitions.
*   **`Makefile`**: Controls the compilation of the C++ NIF. Handles both host and cross-compilation flags.
*   **`c_src/matter_nif.cpp`**: The core C++ file implementing the NIFs.
*   **`lib/matterlix/matter/nif.ex`**: The Elixir module defining the NIF function signatures (stubs).
*   **`matter_sdk_includes.mk`**: Helper makefile to locate Matter SDK headers and libraries (not always present, generated or manually managed).

## Conventions

*   **NIF Safety**: Long-running NIF operations should be avoided or use dirty schedulers (though current implementation seems synchronous).
*   **Environment Variables**:
    *   `MATTER_SDK_ENABLED`: Set to `1` to link real C++ SDK.
    *   `CROSSCOMPILE`: Used by Nerves to signal target builds.
*   **Testing**: `mix test` runs Elixir unit tests. NIF functionality is mocked or stubbed in tests unless running in a full integration environment.
