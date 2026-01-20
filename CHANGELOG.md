# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `ErrorHandler.explain/1` returns human-readable error messages with fix suggestions (R018)
- `ZenWebsocket.LatencyStats` module for bounded circular buffer latency statistics (R017)
- `Client.get_latency_stats/1` returns p50/p99/last/count latency metrics (R017)
- Telemetry event `[:zen_websocket, :connection, :upgrade]` with `connect_time_ms` measurement (R017)
- Telemetry event `[:zen_websocket, :heartbeat, :pong]` with `rtt_ms` measurement (R017)
- Telemetry event `[:zen_websocket, :rate_limiter, :pressure]` for backpressure signaling (R021)
- Config option `latency_buffer_size` (default: 100) for latency stats circular buffer (R017)
- `RateLimiter.status/1` now returns `pressure_level` and `suggested_delay_ms` fields (R021)
- `ZenWebsocket.HeartbeatManager` module for heartbeat lifecycle management (R001)
- `ZenWebsocket.SubscriptionManager` module for subscription tracking and restoration (R002)
- `ZenWebsocket.RequestCorrelator` module for JSON-RPC request/response correlation (R003)
- Telemetry events for SubscriptionManager: `:add`, `:remove`, `:restore` (R002)
- Telemetry events for RequestCorrelator: `:track`, `:resolve`, `:timeout` (R003)
- `RateLimiter.shutdown/1` for proper ETS table cleanup (R005)
- Configurable `max_queue_size` option for RateLimiter (default: 100) (R005)
- Telemetry events for rate limiter: `:consume`, `:queue`, `:queue_full`, `:refill` (R005)
- Memory characteristics documentation in RateLimiter @moduledoc (R005)
- Test tagging conventions documentation in test_helper.exs (R015)
- Test coverage exclusion config for non-production modules (T001)
- Test coverage roadmap documentation at `docs/test_roadmap.md`
- Frame edge case tests for direct frame format decoding (T002)
- Config boundary value tests for `new!/2` and `request_timeout` validation (T003)
- Reconnection extreme value tests for nil max_backoff and zero retries (T004)

### Changed
- RequestCorrelator now stores timestamps and emits `round_trip_ms` in resolve telemetry (R017)
- RateLimiter tracks pressure level and emits threshold-crossing events at 25%/50%/75% queue fill (R021)
- HeartbeatManager emits RTT telemetry on heartbeat responses (R017)
- Client tracks connection timing from connect start to WebSocket upgrade (R017)
- Test coverage metrics now exclude non-production modules (Examples, Test.Support, Mix.Tasks) - reported coverage ~38% → ~70% (T001)
- Frame module now at 100% test coverage (T002)
- Config module now at 100% test coverage (T003)
- Extracted heartbeat logic from Client.ex to HeartbeatManager (789 lines from 870) (R001)
- Extracted subscription tracking from Client.ex to SubscriptionManager (R002)
- Extracted request/response correlation from Client.ex to RequestCorrelator (R003)
- Client.ex now fully delegates to extracted modules; removed dead `restore_subscriptions/4` from Reconnection (R004)
- Automatic subscription restoration on reconnect via `maybe_restore_subscriptions/1` (R002)
- Replaced magic numbers with named module attributes in Client, ClientSupervisor, and Reconnection modules (R008)
- Standardized `Debug.log/2` to accept only `Config.t()` struct, removed polymorphic state map interface (R009)
- BasicUsage example now uses Deribit testnet instead of echo.websocket.org
- MockWebSockServer handler registration improved in `websocket_init/1`
- Downgraded Elixir from 1.20.0-rc.1 to 1.19.5 (fixes Credo false positives)
- RateLimiter `handle_rate_limit/5` now accepts config parameter to avoid double ETS lookup (R005)

### Fixed
- Dialyzer warning on `Client.maybe_restore_subscriptions/1` - expanded `Client.state()` type to include all fields (R002)
- ConnectionRegistry monitor leaks: `cleanup_dead/1` and `shutdown/0` now properly demonitor before deletion (R006)
- Flaky tests: migrated from unreliable echo.websocket.org to local MockWebSockServer
- Race conditions in ErrorHandlingTest with proper `wait_for_connection/1` polling
- MockWebSockServer now raises clear error when TLS certificates unavailable
- Test tagging: 7 integration test files now properly tagged with `@moduletag :integration` (R015)
  - `mix test` now runs 141 unit tests (~5 seconds vs ~93 seconds for full suite)
  - Removed incorrect `@moduletag :integration` from `platform_adapter_template_test.exs` (pure unit tests)
  - Removed module-level tag from `rate_limiting_test.exs` (uses `@describetag` for integration blocks only)

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