# Contributing to Matterlix

Thank you for your interest in contributing to Matterlix! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
- C++ compiler with C++17 support
- For full Matter SDK integration: CMake, Ninja, Python 3.8+

### Development Setup

```bash
# Clone the repository
git clone https://github.com/tomHoenderdos/matterlix.git
cd matterlix

# Install dependencies
mix deps.get

# Compile (stub mode, no Matter SDK required)
mix compile

# Run tests
mix test
```

### Building with Matter SDK

See the [README](README.md#setup-matter-sdk-optional) for full Matter SDK setup instructions.

## How to Contribute

### Reporting Issues

Before creating an issue, please:

1. Search existing issues to avoid duplicates
2. Use a clear, descriptive title
3. Include:
   - Elixir/OTP version (`elixir --version`)
   - Operating system and version
   - Steps to reproduce the problem
   - Expected vs actual behavior
   - Relevant logs or error messages

### Submitting Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following the code style guidelines below
3. **Add tests** for new functionality
4. **Run the test suite** to ensure nothing is broken
5. **Update documentation** if you're changing public APIs
6. **Submit a pull request** with a clear description of the changes

#### PR Checklist

- [ ] Code compiles without warnings (`mix compile --warnings-as-errors`)
- [ ] All tests pass (`mix test`)
- [ ] Code is formatted (`mix format`)
- [ ] New features have tests
- [ ] Documentation is updated if needed

## Code Style

### Elixir

- Run `mix format` before committing
- Follow standard Elixir naming conventions
- Add `@doc` and `@spec` for public functions
- Keep functions small and focused

### C++ (NIF code)

- Use C++17 features where appropriate
- Follow the existing code style in `c_src/`
- Document any Matter SDK interactions
- Be mindful of NIF restrictions (don't block the scheduler)

### Commit Messages

- Use clear, descriptive commit messages
- Start with a verb in present tense ("Add feature" not "Added feature")
- Keep the first line under 72 characters
- Reference issues when relevant ("Fix #123")

## Testing

### Running Tests

```bash
# Standard tests
mix test

# With AddressSanitizer (memory safety checks)
ASAN=1 mix test

# Full CI suite in Docker
docker build -f Dockerfile.ci -t matterlix-ci .
docker run --rm matterlix-ci
```

### Writing Tests

- Place tests in `test/`
- Test both success and error cases
- For NIF functions, consider memory safety implications

## Architecture Notes

Understanding the codebase structure helps when contributing:

```
lib/
├── matterlix.ex              # Main application module
└── matterlix/
    ├── application.ex        # OTP Application
    ├── matter.ex             # GenServer API (high-level)
    └── matter/
        └── nif.ex            # NIF bindings (low-level)

c_src/
└── matter_nif.cpp            # C++ NIF implementation
```

- **NIF layer** (`nif.ex` + `matter_nif.cpp`): Direct bindings to Matter SDK
- **GenServer layer** (`matter.ex`): Stateful wrapper with callbacks and lifecycle management

## Questions?

If you have questions about contributing, feel free to open an issue with the "question" label.
