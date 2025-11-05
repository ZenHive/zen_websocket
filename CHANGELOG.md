# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2025-11-05

### Changed
- **Breaking**: DeribitRpc functions now return `{:ok, map()}` tuples instead of bare maps for consistency with library conventions
- Updated Erlang from 27.3.4 to 28.1.1
- Updated Elixir from 1.18.4 to 1.19.1-otp-28

### Improved
- DeribitAdapter and DeribitGenServerAdapter updated to use `with` statements for better error handling
- Correlation test improved with MockWebSockServer usage
- Test helper configuration cleaned up for better readability

## [0.1.3] - 2025-08-11

### Fixed
- Compilation error in mix zen_websocket.validate_usage task (regex in module attributes)

## [0.1.2] - 2025-08-11

### Added
- USAGE_RULES.md for AI agents and developer guidance
- Mix task `zen_websocket.usage` to export usage rules
- Mix task `zen_websocket.validate_usage` to validate code patterns
- Integration with usage_rules library ecosystem
- JSON export format for usage rules
- Automated code validation for common anti-patterns

### Improved
- Documentation with clear usage patterns and examples
- Package metadata for Hex.pm publishing

## [0.1.1] - 2025-05-24

### Added
- Initial release of ZenWebsocket
- Core WebSocket client implementation with Gun transport
- Automatic reconnection with exponential backoff
- Comprehensive error handling and categorization
- JSON-RPC 2.0 protocol support
- Request/response correlation manager
- Configurable token bucket rate limiter
- Integrated heartbeat/keepalive functionality
- Fault-tolerant adapter architecture
- Production-ready Deribit exchange integration
- Connection registry for multi-connection management
- Message handler with routing capabilities
- WebSocket frame encoding/decoding
- Telemetry events for monitoring
- Comprehensive test suite using real APIs (no mocks)
- Full documentation with examples

### Features
- Simple 5-function public API
- Financial-grade reliability for trading systems
- Platform-agnostic design with adapter pattern
- Real-world tested against live WebSocket endpoints
- Strict code quality standards (max 5 functions per module, 15 lines per function)

[Unreleased]: https://github.com/ZenHive/zen_websocket/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/ZenHive/zen_websocket/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ZenHive/zen_websocket/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ZenHive/zen_websocket/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ZenHive/zen_websocket/releases/tag/v0.1.1