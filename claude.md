# Matter Nerves Project

This project integrates the Matter (formerly Project CHIP) C++ SDK into a Nerves-based Elixir application using NIFs.

## Project Status

**Current State**: Matter SDK integrated, NIF compiles and links against libCHIP.a. Ready for implementing Matter SDK function calls.

### Completed
- [x] Nerves project structure created
- [x] NIF infrastructure with `elixir_make`
- [x] C++ NIF skeleton (`c_src/matter_nif.cpp`)
- [x] Elixir wrapper modules (`MatterNerves.Matter` and `MatterNerves.Matter.NIF`)
- [x] Basic NIF functions: init, start_server, stop_server, get_info, set/get_attribute
- [x] Build system with cross-compilation support
- [x] Matter SDK downloaded and built (`deps/connectedhomeip`)
- [x] Matter SDK include paths and library linking configured
- [x] NIF compiles with `MATTER_SDK_ENABLED=1`

### Next Steps
1. **Implement NIF functions** - Replace stubs with actual Matter SDK calls
2. **Configure device** - Set up device attestation, commissioning, and endpoint configuration
3. **Build for Raspberry Pi** - Configure cross-compilation for ARM target
4. **Test on Raspberry Pi** - Build firmware and deploy to hardware

## Project Structure

```
matter_nerves/
├── c_src/
│   └── matter_nif.cpp      # C++ NIF code (Matter SDK bindings)
├── lib/
│   └── matter_nerves/
│       ├── matter.ex       # High-level GenServer API
│       └── matter/
│           └── nif.ex      # Low-level NIF bindings
├── Makefile                # Build configuration for NIF
├── mix.exs                 # Elixir project config
└── config/
    ├── config.exs
    ├── host.exs
    └── target.exs
```

## Quick Start

```bash
# Compile and test (host) - stub build without Matter SDK
mix deps.get
mix compile

# Test NIF (stub)
mix run -e '{:ok, ctx} = MatterNerves.Matter.NIF.nif_init(); IO.inspect(MatterNerves.Matter.NIF.nif_get_info(ctx))'

# Build with Matter SDK enabled (requires Matter SDK to be built first)
MATTER_SDK_ENABLED=1 mix compile

# Build firmware for Raspberry Pi 4
export MIX_TARGET=rpi4
mix deps.get
mix firmware

# Burn to SD card
mix burn
```

## Building with Matter SDK

The Matter SDK is located in `deps/connectedhomeip`. To rebuild it:

```bash
# Activate the Matter SDK environment
cd deps/connectedhomeip
source scripts/activate.sh

# Build for macOS (darwin-arm64)
python3 scripts/build/build_examples.py --target darwin-arm64-light build

# The output will be in out/darwin-arm64-light/
# - lib/libCHIP.a - Main Matter library
# - gen/ - Generated headers
```

### Build Configuration Files

- `Makefile` - Main build configuration, uses `MATTER_SDK_ENABLED` env var
- `matter_sdk_includes.mk` - Matter SDK include paths and library configuration

## Matter SDK Integration Notes

### Key Matter SDK Components to Integrate
- `chip::DeviceLayer::PlatformMgr()` - Platform initialization
- `chip::Server::GetInstance()` - Main Matter server
- Data model (endpoints, clusters, attributes)
- Commissioning workflow (BLE, WiFi credentials)

### Challenges to Address
1. **Build complexity** - Matter SDK has many dependencies (OpenSSL, mbedTLS, etc.)
2. **Cross-compilation** - Must compile for ARM on Raspberry Pi
3. **Threading** - Matter uses its own event loop; need to integrate with BEAM
4. **Long operations** - Use dirty schedulers for blocking calls

### Architecture Options
1. **Direct NIF calls with dirty schedulers** - Current approach
2. **Separate process via Port** - More isolation, less risk to BEAM
3. **Custom Nerves system** - Include Matter as a Buildroot package

## Target Hardware

Primary target: **Raspberry Pi 4** (or 3B+)
- Good Nerves support
- WiFi/BLE for Matter commissioning
- Sufficient resources for Matter stack

## Useful Resources

- [Matter SDK (connectedhomeip)](https://github.com/project-chip/connectedhomeip)
- [Nerves Project](https://nerves-project.org/)
- [Elixir NIF Guide](https://www.erlang.org/doc/tutorial/nif.html)
- [elixir_make](https://github.com/elixir-lang/elixir_make)
