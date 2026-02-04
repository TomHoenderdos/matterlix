# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/tomHoenderdos/matterlix/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/tomHoenderdos/matterlix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tomHoenderdos/matterlix/releases/tag/v0.1.0
