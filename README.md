# Matterlix

[![CI](https://github.com/tomHoenderdos/matterlix/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tomHoenderdos/matterlix/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/matterlix.svg)](https://hex.pm/packages/matterlix)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/matterlix)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A Nerves-based Elixir application that integrates the [Matter](https://csa-iot.org/all-solutions/matter/) (formerly Project CHIP) smart home protocol, enabling Raspberry Pi devices to participate in Matter networks.

**Matter + Elixir = Matterlix**

## Overview

This project bridges the Matter C++ SDK with Elixir/Nerves using Native Implemented Functions (NIFs), allowing you to build Matter-compatible smart home devices running on embedded Linux.

```
┌─────────────────────────────────────────────────────┐
│                   Elixir Application                │
│  ┌───────────────┐    ┌──────────────────────────┐  │
│  │   Matterlix   │───▶│ Matterlix.Matter         │  │
│  │  (Your App)   │    │ (GenServer API)          │  │
│  └───────────────┘    └──────────────────────────┘  │
│                              │                      │
│                              ▼                      │
│                       ┌──────────────────────────┐  │
│                       │ Matterlix.Matter.NIF     │  │
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
- **Commissioning Support** - QR Code generation, Commissioning Window management
- **Network Commissioning** - WiFi credential passing to Elixir (for VintageNet integration)
- **Attribute Callbacks** - Real-time Elixir events when attributes change
- **Device Management** - Factory Reset, Device Info configuration

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

## Testing & Security

### AddressSanitizer (ASan)

To test for memory safety issues in the C++ NIF:

```bash
ASAN=1 mix test
```

### Docker CI

To run the full test suite with ASan in a Linux environment (bypassing macOS SIP issues):

```bash
docker build -f Dockerfile.ci -t matterlix-ci .
docker run --rm matterlix-ci
```

## API Examples

### Initialize & Commission

```elixir
{:ok, ctx} = Matterlix.Matter.NIF.nif_init()
:ok = Matterlix.Matter.NIF.nif_register_callback(ctx)

# Get pairing info
{:ok, payload} = Matterlix.Matter.NIF.nif_get_setup_payload(ctx)
IO.puts "QR Code: #{payload.qr_code}"

# Allow pairing for 5 minutes
:ok = Matterlix.Matter.NIF.nif_open_commissioning_window(ctx, 300)

:ok = Matterlix.Matter.NIF.nif_start_server(ctx)
```

### Attributes

```elixir
# Read an attribute (endpoint 1, On/Off cluster, OnOff attribute)
{:ok, value} = Matterlix.Matter.NIF.nif_get_attribute(ctx, 1, 0x0006, 0x0000)

# Set an attribute
:ok = Matterlix.Matter.NIF.nif_set_attribute(ctx, 1, 0x0006, 0x0000, true)
```

## Complete Example

The `example/` directory contains a fully working Matter light device with physical controls:

```
example/
├── lib/
│   ├── example/
│   │   ├── matter_light.ex   # Matter device logic & attribute handling
│   │   ├── pairing_button.ex # GPIO button with short/long press detection
│   │   └── status_led.ex     # LED patterns for device state feedback
│   └── example.ex            # Application supervisor
└── config/
    └── target.exs            # Raspberry Pi GPIO & commissioning config
```

### Run on Host (No Hardware Required)

```bash
cd example
mix deps.get
iex -S mix

# Simulate button presses
iex> Example.PairingButton.simulate_short_press()  # Toggle light
iex> Example.PairingButton.simulate_long_press()   # Enter pairing mode

# Check LED status
iex> Example.StatusLed.set_mode(:pairing)  # Blink pattern
iex> Example.StatusLed.set_mode(:paired)   # Solid on
```

### Deploy to Raspberry Pi

```bash
cd example
export MIX_TARGET=rpi4
mix deps.get
mix firmware
mix burn
```

**Wiring (BCM pin numbers):**
- GPIO17 → Button (to GND, uses internal pull-up)
- GPIO27 → LED anode (with 330Ω resistor to GND)

### What It Demonstrates

- **GenServer integration** - Clean separation between Matter and device logic
- **Event handling** - React to attribute changes from Matter controllers
- **Hardware abstraction** - Same code runs on host (simulated) and Raspberry Pi
- **Commissioning flow** - Pairing button, status LED feedback, QR codes
- **Graceful degradation** - Falls back to simulation when GPIO unavailable

See `example/README.md` for detailed documentation.

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MATTER_SDK_ENABLED` | Enable Matter SDK integration | `0` |
| `ASAN` | Enable AddressSanitizer for memory safety | `0` |
| `MIX_TARGET` | Nerves target (rpi3, rpi4, host) | `host` |
| `CROSSCOMPILE` | Enable cross-compilation | auto |

## Current Status

- [x] Nerves project structure
- [x] NIF skeleton with elixir_make
- [x] Matter SDK build integration
- [x] Host compilation (macOS/Linux)
- [x] Matter SDK function implementations (Init, Start, Stop)
- [x] Device Commissioning (QR, Window)
- [x] Attribute Management (Get/Set/Callbacks)
- [x] Network Commissioning (WiFi)
- [x] Security Testing (ASan + CI)
- [ ] Cross-compilation for ARM (Verified on HW)

## Resources

- [Matter SDK (connectedhomeip)](https://github.com/project-chip/connectedhomeip)
- [Nerves Project](https://nerves-project.org/)
- [Matter Specification](https://csa-iot.org/developer-resource/specifications-download-request/)
- [Elixir NIF Guide](https://www.erlang.org/doc/tutorial/nif.html)

## License

See LICENSE file.