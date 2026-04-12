# Contributing to ZenWebsocket

Thank you for your interest in contributing to ZenWebsocket! This document provides guidelines for contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by the [Hex.pm Code of Conduct](https://hex.pm/policies/codeofconduct).

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR-USERNAME/zen_websocket.git`
3. Create a feature branch: `git checkout -b my-feature`
4. Make your changes
5. Run tests: `mix test.json --quiet --summary-only`
6. Run quality checks (see Development Commands below)
7. Commit your changes
8. Push to your fork and submit a pull request

## Development Setup

```bash
# Install dependencies
mix deps.get

# Run tests
mix test.json --quiet --summary-only

# Quality checks
mix dialyzer.json --quiet              # Type checking
mix credo --strict --format json       # Static analysis
mix security                           # Sobelow security scan

# Generate documentation
mix docs
```

## Documentation

When your change affects user guidance, update the relevant docs in the same pull request:

- `README.md` for top-level discovery and guide links
- `AGENTS.md` for contributor and AI-agent workflow guidance
- `CHANGELOG.md` under `Unreleased`
- `docs/guides/` for task-specific guides such as:
  - `building_adapters.md`
  - `performance_tuning.md`
  - `troubleshooting_reconnection.md`
  - `deployment_considerations.md`

## Testing Policy

**IMPORTANT**: This project uses real API testing exclusively. We do not use mocks.

- All tests must run against real WebSocket endpoints
- Use `test.deribit.com` for Deribit-specific tests
- For general WebSocket tests, use publicly available echo servers
- If credentials are required, they must be provided via environment variables

## Code Style

- Follow the existing code style
- Run `mix format` before committing
- Ensure `mix credo --strict` passes
- All public functions must have `@spec` annotations
- All modules must have `@moduledoc` documentation

## Simplicity Guidelines

This project values simplicity:

- Maximum 5 functions per module
- Maximum 15 lines per function
- No unnecessary abstractions
- Direct Gun API usage (no wrapper layers)
- Use GenServers only when state management is needed

## Pull Request Process

1. Ensure all tests pass
2. Update documentation as needed
3. Add an entry to CHANGELOG.md under "Unreleased"
4. Ensure your code follows the simplicity guidelines
5. Submit your pull request with a clear description

## Reporting Issues

- Use the GitHub issue tracker
- Provide a clear description of the issue
- Include steps to reproduce
- Include your Elixir and Erlang/OTP versions
- If possible, provide a minimal code example

## Questions?

If you have questions about contributing, please open an issue with the "question" label.
