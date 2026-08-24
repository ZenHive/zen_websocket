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

# Fast local pre-commit loop (skips cold dialyzer PLT and full deps audit)
mix precommit

# Comprehensive gate — run before pushing or creating a PR
mix precommit.full
# This is aliased as 'mix ci' and runs, in order:
#   - compile --warnings-as-errors
#   - format --check-formatted
#   - credo --strict
#   - doctor --raise
#   - ex_dna --max-clones 0 (zero-clone duplication budget)
#   - reach.check --arch --smells (architecture policy)
#   - sobelow --skip (security scanning)
#   - deps.audit.gated (advisory freshness + audit)
#   - test.json --cover --cover-threshold 90 (90% minimum coverage)
#   - dialyzer (type checking)
#   - agents.check (AGENTS.md freshness)
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

Tests pin behavior at the narrowest real boundary that proves it:

- Pure logic uses unit tests without network access.
- WebSocket integration tests use the local `MockWebSockServer`, which runs a
  real Cowboy/WebSock stack, and carry `:integration` plus `:local_network`.
- Provider semantics use opt-in `:external_network` tests against endpoints
  such as `test.deribit.com`; credentialed tests fail with setup instructions
  when their environment variables are absent.
- Do not stub API responses, authentication, or exchange behavior. The two
  narrow test-double exceptions are documented in `AGENTS.md`.

## Code Style

- Follow the existing code style
- Run `mix format` before committing
- Ensure `mix credo --strict` passes
- All public functions must have `@spec` annotations
- All modules must have `@moduledoc` documentation

## Simplicity Guidelines

This project values simplicity:

- New modules have a maximum of 5 functions
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
