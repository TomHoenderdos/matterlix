# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-02-15

### Added
- `Matterlix.Handler` behaviour for dispatching Matter events to consuming projects
- `Matterlix.Handler.Default` no-op handler (used when no handler is configured)
- `Matterlix.DeviceProfiles` with 6 profiles: light, contact_sensor, lock, thermostat, air_quality_sensor, all_clusters
- `mix matterlix.build_sdk` Mix task for Docker-based Matter SDK builds
- `Matterlix.update_attribute/4` and `Matterlix.get_attribute/3` convenience API
- `auto_supervise` application config to control automatic GenServer startup
- Default GenServer name registration (`Matterlix.Matter`)
- `MATTER_DEBUG` flag for debug logging, signal handlers, and verbose crash messages
- `REQUIRE_SDK_INITIALIZED` guard macro in NIF for safer SDK calls
- `server_started` tracking in NIF singleton
- Docker build infrastructure (`docker/Dockerfile.arm64`, `docker/build.sh`)
- Build scripts (`scripts/gen_matter_includes.sh`, `scripts/build_matter_sdk_arm64.sh`)

### Changed
- **Library cleanup**: Stripped all Nerves firmware deps (nerves_system_*, shoehorn, ring_logger, etc.)
- Library now only depends on `elixir_make` and `ex_doc`
- Consuming firmware projects provide their own Nerves deps and cross-compilation config
- NIF `nif_start_server` now performs full Matter SDK initialization (CommissionableDataProvider, DeviceAttestationCredentials, PosixConfig, data model provider)
- `emberAfWriteAttribute`/`emberAfReadAttribute` updated for current Matter SDK API (metadata lookup, Status return type)
- `ScanNetworks`/`ConnectNetwork` return void instead of CHIP_ERROR (Matter SDK API change)
- `AddOrUpdateNetwork`/`RemoveNetwork`/`ReorderNetwork` return `Status` instead of `CHIP_ERROR`
- `GetManualCode` renamed to `GetManualPairingCode`
- `NetworkCommissioning::Instance` moved to `chip::app::Clusters::NetworkCommissioning::Instance`
- `GetNetworks()` now returns `NetworkIterator*` instead of `const Network*`
- NIF uses `Logger.error` instead of `IO.warn` for load failures
- `matter_sdk_includes.mk` now includes ~111 extra .o files and 43 static .a libs required for linking
- CI no longer installs `nerves_bootstrap` or `libmnl-dev`

### Breaking
- Removed `set_attribute_change_callback_fn/2` — use `Matterlix.Handler` behaviour instead
- Removed all Nerves system deps from library — firmware projects must add their own
- Removed `config/target.exs`, `rel/vm.args.eex`, `rootfs_overlay/`

## [0.2.0] - 2025-02-04

### Added
- Support for 8/16/32-bit signed and unsigned integers in attribute handling
- Input validation for VID, PID, timeout, and serial number parameters
- Thread synchronization in `register_callback/1`
- Complete example application (`example/`) with Matter light, GPIO button, and status LED
- Example documentation in README with quick start guide

### Fixed
- **Critical**: Race condition in `get_listener_info()` - lock now acquired before reading singleton
- **Critical**: Race condition in `get_global_mutex()` - now uses Meyer's singleton pattern
- **Critical**: Race condition in `nif_unload()` - lock held when clearing singleton
- **Critical**: NULL pointer dereference on OOM in `enif_make_new_binary` calls
- **Critical**: Buffer overflow in `get_setup_payload()` - increased buffer sizes and explicit null termination
- Silent truncation in `set_attribute()` - now auto-selects appropriate integer size
- Missing initialization check in `nif_stop_server()`
- Invalid timeout values accepted in `open_commissioning_window()`
- Invalid serial number length silently ignored in `set_device_info()`

## [0.1.0] - 2025-01-17

### Added
- Initial public release
- NIF bindings for Matter SDK
- GenServer API (`Matterlix.Matter`)
- Commissioning support (QR code, commissioning window)
- Attribute get/set with callbacks
- Network commissioning (WiFi credential handling)
- Factory reset support
- Device info configuration
- AddressSanitizer CI testing
- Stub mode for development without Matter SDK

[Unreleased]: https://github.com/tomHoenderdos/matterlix/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/tomHoenderdos/matterlix/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tomHoenderdos/matterlix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tomHoenderdos/matterlix/releases/tag/v0.1.0
