# Matterlix

[![CI](https://github.com/tomHoenderdos/matterlix/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tomHoenderdos/matterlix/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/matterlix.svg)](https://hex.pm/packages/matterlix)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/matterlix)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Elixir NIF bindings for the [Matter](https://csa-iot.org/all-solutions/matter/) (CHIP) smart home protocol. Build Matter-compatible devices on embedded Linux with Nerves.

**Matter + Elixir = Matterlix**

## Overview

Matterlix is a reusable Elixir library that bridges the Matter C++ SDK with Elixir using NIFs. Your firmware project depends on matterlix and implements a Handler behaviour to react to Matter events.

```
┌─────────────────────────────────────────────────────┐
│                   Your Firmware                     │
│  ┌───────────────┐    ┌──────────────────────────┐  │
│  │   Your App    │───▶│ Matterlix.Handler        │  │
│  │  (Nerves)     │    │ (Your callbacks)         │  │
│  └───────────────┘    └──────────────────────────┘  │
│                              │                      │
│                              ▼                      │
│  ┌──────────────────────────────────────────────┐   │
│  │             Matterlix (library)              │   │
│  │  Matterlix.Matter (GenServer)                │   │
│  │  Matterlix.Matter.NIF (NIF bindings)         │   │
│  │  c_src/matter_nif.cpp (C++ NIF)              │   │
│  └──────────────────────────────────────────────┘   │
│                              │                      │
│                              ▼                      │
│  ┌──────────────────────────────────────────────┐   │
│  │            Matter SDK (libCHIP.a)            │   │
│  │  DeviceLayer │ Server │ Data Model (Clusters)│   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Features

- **Reusable library** - Add to any Nerves firmware project as a dependency
- **Handler behaviour** - Implement `Matterlix.Handler` to react to Matter events
- **Device profiles** - Build for lights, sensors, locks, thermostats, and more
- **Convenience API** - `Matterlix.update_attribute/4` for pushing sensor data
- **Stub mode** - Develop and test without Matter SDK dependency
- **Commissioning** - QR Code generation, BLE/WiFi commissioning
- **Network Commissioning** - WiFi credential passing to Elixir (VintageNet integration)
- **Cross-compilation** - Docker-based arm64 SDK build for Raspberry Pi

## Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
- C++ compiler with C++17 support
- For Matter SDK builds: Docker (arm64 native or emulated)

## Quick Start

### 1. Add Dependency

```elixir
# In your firmware project's mix.exs
def deps do
  [{:matterlix, "~> 0.3"}]
end
```

### 2. Implement a Handler

```elixir
defmodule MyApp.MatterHandler do
  @behaviour Matterlix.Handler

  @impl true
  def handle_attribute_change(1, 0x0006, 0x0000, _type, value) do
    # React to On/Off toggle from a Matter controller
    MyApp.LED.set(value)
    :ok
  end

  def handle_attribute_change(_ep, _cluster, _attr, _type, _value), do: :ok
end
```

### 3. Configure

```elixir
# config/config.exs
config :matterlix,
  handler: MyApp.MatterHandler,
  device_profile: :light,
  setup_pin: 20202021,
  discriminator: 3840
```

### 4. Push Data to Matter

```elixir
# Push a sensor reading — controllers get notified automatically
Matterlix.update_attribute(1, 0x0402, 0x0000, 2350)

# Toggle a light
Matterlix.update_attribute(1, 0x0006, 0x0000, true)
```

## Building the Matter SDK

The library compiles in **stub mode** by default (no Matter SDK needed). For actual Matter functionality, build the SDK:

### 1. Clone Matter SDK

```bash
mkdir -p deps
git clone --depth 1 https://github.com/project-chip/connectedhomeip.git deps/connectedhomeip
cd deps/connectedhomeip
python3 scripts/checkout_submodules.py --shallow --platform linux
```

### 2. Build for a Device Profile

```bash
# List available profiles
mix matterlix.build_sdk --list

# Build for the default profile (light)
mix matterlix.build_sdk

# Build for a specific profile
mix matterlix.build_sdk --profile contact_sensor
```

This builds the Matter SDK in an arm64 Docker container and generates `matter_sdk_includes.mk` with the correct object files and libraries.

> First build takes ~20-30 minutes.

### 3. Compile with Matter SDK

```bash
MATTER_SDK_ENABLED=1 mix compile
```

## Device Profiles

Each profile maps to a Matter SDK example app with pre-configured clusters:

| Profile | Clusters | Use Case |
|---------|----------|----------|
| `light` (default) | OnOff, LevelControl, ColorControl | Dimmable color light |
| `contact_sensor` | BooleanState | Door/window sensor |
| `lock` | DoorLock | Smart lock |
| `thermostat` | Thermostat | HVAC control |
| `air_quality_sensor` | AirQuality, Temperature, Humidity | Environmental sensing |
| `all_clusters` | All standard clusters | Development/testing |

## System Requirements for Commissioning

Matter BLE commissioning requires BlueZ and D-Bus on Linux. Stock Nerves systems do **not** include Bluetooth support. You need a custom Nerves system with:

- **Kernel**: `CONFIG_BT`, `CONFIG_BT_HCIUART`, `CONFIG_BT_HCIUART_BCM`
- **Buildroot**: `BR2_PACKAGE_DBUS`, `BR2_PACKAGE_BLUEZ5_UTILS`
- **Runtime**: `dbus-daemon` + `bluetoothd`

See the `example/` directory for a working firmware project.

## Testing

```bash
# Run tests (stub mode, no SDK needed)
mix test

# With AddressSanitizer (memory safety)
ASAN=1 mix test

# CI suite in Docker
docker build -f Dockerfile.ci -t matterlix-ci .
docker run --rm matterlix-ci
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

See `example/README.md` for detailed documentation.

## Configuration

| Key | Description | Default |
|-----|-------------|---------|
| `handler` | Module implementing `Matterlix.Handler` | `Matterlix.Handler.Default` |
| `device_profile` | Matter device type | `:light` |
| `auto_supervise` | Auto-start GenServer in supervision tree | `true` |
| `setup_pin` | Commissioning PIN code (1-99999998) | SDK default |
| `discriminator` | 12-bit discriminator (0-4095) | SDK default |
| `debug` | Enable debug logging | `false` |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MATTER_SDK_ENABLED` | Enable Matter SDK integration | `0` |
| `MATTER_DEBUG` | Enable debug instrumentation in NIF | `0` |
| `ASAN` | Enable AddressSanitizer | `0` |
| `CROSSCOMPILE` | Enable cross-compilation | auto |

## Verified Hardware

- Raspberry Pi Zero 2 W (linux-arm64) - Full commissioning working (BLE, mDNS, PASE, CASE, OnOff)
- macOS Apple Silicon (darwin-arm64) - Stub mode development

## Resources

- [Matter SDK (connectedhomeip)](https://github.com/project-chip/connectedhomeip)
- [Nerves Project](https://nerves-project.org/)
- [Matter Specification](https://csa-iot.org/developer-resource/specifications-download-request/)
- [Elixir NIF Guide](https://www.erlang.org/doc/tutorial/nif.html)

## License

See LICENSE file.
