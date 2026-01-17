# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Matterlix, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email the maintainer directly at: info@tompc.nl

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Resolution target**: Depends on severity, typically 30-90 days

## Scope

This security policy applies to:
- The Matterlix Elixir library
- The C++ NIF code in `c_src/`

It does not cover:
- The Matter SDK itself (report to [connectedhomeip](https://github.com/project-chip/connectedhomeip/security))
- Nerves or other dependencies (report to their respective projects)

## Security Considerations

Matterlix involves:
- **Native code (NIFs)**: Memory safety issues could affect the BEAM VM
- **IoT/Smart home**: Devices may be network-accessible
- **Commissioning**: Involves cryptographic operations and credentials

We take these concerns seriously and appreciate responsible disclosure.
