# Matterlix

A Nerves-based Elixir application that integrates the [Matter](https://csa-iot.org/all-solutions/matter/) (formerly Project CHIP) smart home protocol, enabling Raspberry Pi devices to participate in Matter networks.

**Matter + Elixir = Matterlix**

## Overview

This project bridges the Matter C++ SDK with Elixir/Nerves using Native Implemented Functions (NIFs), allowing you to build Matter-compatible smart home devices running on embedded Linux.

```
┌─────────────────────────────────────────────────────┐
│                   Elixir Application                │
│  ┌───────────────┐    ┌──────────────────────────┐  │
│  │   Matterlix   │───▶│ Matterlix.Matter      │  │
│  │  (Your App)   │    │ (GenServer API)          │  │
│  └───────────────┘    └──────────────────────────┘  │
│                              │                      │
│                              ▼                      │
│                       ┌──────────────────────────┐  │
│                       │ Matterlix.Matter.NIF  │  │
│                       │ (Elixir NIF Bindings)    │  │
│                       └──────────────────────────┘  │
└───────────────────────────────┬─────────────────────┘
                                │ NIF calls
                                ▼
┌─────────────────────────────────────────────────────┐
│                  C++ NIF Layer                      │
│              (c_src/matter_nif.cpp)                 │
└───────────────────────────────┬─────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────┐
│                   Matter SDK                        │
│              (libCHIP.a / connectedhomeip)          │
│  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐   │
│  │ DeviceLayer │ │   Server    │ │  Data Model  │   │
│  │ PlatformMgr │ │  Instance   │ │  (Clusters)  │   │
│  └─────────────┘ └─────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Features

- **NIF-based integration** - Direct binding to Matter SDK for performance
- **Elixir GenServer API** - Idiomatic Elixir interface for Matter operations
- **Cross-compilation ready** - Build for Raspberry Pi targets with Nerves
- **Stub mode** - Develop and test without Matter SDK dependency

## Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- C++ compiler with C++17 support
- For Matter SDK integration:
  - CMake 3.16+
  - Ninja build system
  - Python 3.8+

### macOS

```bash
brew install cmake ninja
```

### Linux (Debian/Ubuntu)

```bash
sudo apt-get install cmake ninja-build python3 python3-venv
```

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url> matterlix
cd matterlix
mix deps.get
```

### 2. Build (Stub Mode)

Without the Matter SDK, you can build and test the NIF skeleton:

```bash
mix compile
mix run -e '{:ok, ctx} = Matterlix.Matter.NIF.nif_init(); IO.inspect(Matterlix.Matter.NIF.nif_get_info(ctx))'
```

### 3. Setup Matter SDK (Optional)

To enable full Matter functionality:

```bash
# Clone Matter SDK
mkdir -p deps
git clone --depth 1 https://github.com/project-chip/connectedhomeip.git deps/connectedhomeip
cd deps/connectedhomeip

# Initialize submodules (Linux platform only, saves space)
python3 scripts/checkout_submodules.py --shallow --platform linux

# Bootstrap build environment
source scripts/bootstrap.sh -p linux

# Build for your platform
# macOS ARM64:
python3 scripts/build/build_examples.py --target darwin-arm64-light build

# Linux x64:
# python3 scripts/build/build_examples.py --target linux-x64-light build
```

### 4. Build with Matter SDK

```bash
cd /path/to/matterlix
MATTER_SDK_ENABLED=1 mix compile
```

## Building for Raspberry Pi

```bash
export MIX_TARGET=rpi4  # or rpi3
mix deps.get
mix firmware
mix burn  # Insert SD card
```

## Project Structure

```
matterlix/
├── c_src/
│   └── matter_nif.cpp          # C++ NIF implementation
├── lib/
│   └── matterlix/
│       ├── application.ex      # OTP Application
│       ├── matter.ex           # GenServer API
│       └── matter/
│           └── nif.ex          # NIF bindings
├── deps/
│   └── connectedhomeip/        # Matter SDK (not committed)
├── Makefile                    # NIF build configuration
├── matter_sdk_includes.mk      # Matter SDK paths
└── mix.exs                     # Elixir project config
```

## API

### Initialize Matter

```elixir
{:ok, pid} = Matterlix.Matter.start_link([])
```

### Start Matter Server

```elixir
:ok = Matterlix.Matter.start_server(pid)
```

### Get/Set Attributes

```elixir
# Read an attribute (endpoint 1, On/Off cluster, OnOff attribute)
{:ok, value} = Matterlix.Matter.get_attribute(pid, 1, 0x0006, 0x0000)

# Set an attribute
:ok = Matterlix.Matter.set_attribute(pid, 1, 0x0006, 0x0000, true)
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MATTER_SDK_ENABLED` | Enable Matter SDK integration | `0` |
| `MIX_TARGET` | Nerves target (rpi3, rpi4, host) | `host` |
| `CROSSCOMPILE` | Enable cross-compilation | auto |

## Current Status

- [x] Nerves project structure
- [x] NIF skeleton with elixir_make
- [x] Matter SDK build integration
- [x] Host compilation (macOS/Linux)
- [ ] Matter SDK function implementations
- [ ] Device attestation & commissioning
- [ ] Cross-compilation for ARM
- [ ] Tested on Raspberry Pi hardware

## Resources

- [Matter SDK (connectedhomeip)](https://github.com/project-chip/connectedhomeip)
- [Nerves Project](https://nerves-project.org/)
- [Matter Specification](https://csa-iot.org/developer-resource/specifications-download-request/)
- [Elixir NIF Guide](https://www.erlang.org/doc/tutorial/nif.html)

## License

See LICENSE file.
