# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Testing policy now permits opaque Gun transport message-shape fixtures** — The "NO MOCKS ALLOWED" rule in CLAUDE.md and AGENTS.md is amended with a narrow, fenced exception: test doubles may construct the four Gun transport tuples (`:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`) using real pids (from `self()` / `spawn`) and real refs (from `make_ref/0`), because Gun's `pid` and `stream_ref` are opaque BEAM primitives with no public contract — there is no behavior for a fixture to drift against. Business-logic mocking (API response fixtures, auth-flow simulation, exchange-behavior simulation) remains explicitly prohibited; `MockWebSockServer` and real-API tests remain the source of truth for all `Client` / reconnection / subscription / exchange tests. AGENTS.md carries the "what is permitted" pointer; CLAUDE.md holds the full rationale and the "what is NOT newly allowed" list. Unblocks R045 (`GunStub` test helper) and R046 (`MessageHandler` property tests) (R044)

### Fixed
- **Duplicate live request IDs no longer silently overwrite the first caller** — `RequestCorrelator.track/4` used `Map.put/3` on `state.pending_requests`, so tracking a second request whose ID matched an already-pending entry silently replaced the first caller's `from` and timer. The first caller then blocked on `GenServer.call` until its per-call `request_timeout` fired, and its timeout timer became orphaned against an ID now owned by the second caller. `track/4` now returns `{:ok, new_state}` on success and `{:error, :duplicate_id, state}` on collision, leaving the first caller's pending entry (and its timer) intact. At the `Client.handle_call({:send_message, _}, …)` call site, the second caller receives `{:error, :duplicate_request_id}` immediately and no WebSocket frame is sent. No `:track` telemetry is emitted on the duplicate path, keeping event counts honest. Covered by unit tests in `request_correlator_test.exs` (`describe "track/4 duplicate ID"`) and an integration test in `client_test.exs` (`describe "duplicate request ID (R043)"`) that fires two `send_message` calls with the same JSON-RPC id back-to-back and asserts the second returns the error while the first still resolves when the server replies (R043)
- **Blocked callers no longer hang or inherit stale timeouts on automatic disconnect** — On the automatic Gun disconnect/reconnect path, `state.pending_requests` was never drained, so callers blocked on `GenServer.call` for a correlated response waited until their per-call `request_timeout` fired even though the socket was gone. `handle_connection_error/2` now calls `RequestCorrelator.fail_all/2`, which replies `{:error, :disconnected}` to every pending caller and emits `[:zen_websocket, :request_correlator, :fail_all]` telemetry. Correlation timers now use unique timer refs in their mailbox messages, so a stale timeout from a disconnected or already-resolved request cannot incorrectly time out a new request that reuses the same ID after reconnect (R042)
- **retry_count not reset after successful reconnect** — After a disconnect-reconnect cycle, `retry_count` accumulated instead of resetting to 0. This silently degraded reconnection capability over the lifetime of a long-running process — each successive disconnect cycle had fewer retry attempts available. Now reset to 0 on successful WebSocket upgrade (R030)
- **Explicit reconnect now preserves the original connection contract** — `Client.reconnect/1` no longer falls back to URL-only reconnects. Client structs returned by `connect/2` or `ClientSupervisor.start_client/2` now retain their validated config plus runtime callbacks such as `handler`, `heartbeat_config`, `on_connect`, and `on_disconnect`, so explicit reconnects keep the same headers, timeouts, retry settings, callback behavior, and supervision mode (R030)
- **Config inspection now redacts header values** — `inspect(config)` (and `inspect(client)` output containing `client.config`) redacts header values via a custom `Inspect` impl, preventing bearer tokens or API keys from leaking through struct inspection. Debug-mode log line that directly logged `config.headers` during WebSocket upgrade has been removed (R030)

### Added
- **Property-based test coverage** — Added property tests using `stream_data` for three pure, deterministic modules (R010):
  - `Frame`: Gun-format and direct-format decode round-trips, constructor round-trips, close-frame normalization (integer code discarded), totality on arbitrary unknown shapes
  - `Config`: valid-input totality across all positive-int fields, URL scheme/host validation, per-field non-positive rejection, `max_backoff < retry_delay` ordering constraint, `new!/2` consistency with `new/2`
  - `JsonRpc`: `build_request/2` shape invariants, unique ID generation across N calls, `match_response/1` coverage for result, error, and notification cases
  - Deferred: `MessageHandler` property tests require Gun transport shape fixtures, which are blocked by the current "NO MOCKS" policy — tracked as R044 (policy amendment), R045 (`GunStub` helper), R046 (MessageHandler properties)
- **Error scenario test coverage** — Added explicit coverage for previously-untested error paths (R011):
  - Gun error variants in `error_handler_test.exs`: `{:gun_error, ..., :closed}`, `{:gun_error, ..., :timeout}`, `{:gun_down, ..., :tls_error, []}`, `{:gun_down, ..., :protocol_error, [refs]}`, and explain/1 unwrapping for both shapes
  - Frame corruption in `frame_test.exs`: unknown atom frame types, non-tuple input, empty tuple, arity-mismatched `:ws` frames, unknown inner `:ws` type, empty and 1MB payloads, deeply nested inner type, map input — all return `{:error, _}` rather than crashing
  - Concurrent correlation timeout cleanup in `request_correlator_test.exs`: N concurrent tracks timing out clear `pending_requests` and emit N telemetry events; timeout on an already-resolved request is a no-op
  - Rate limit recovery in `rate_limiter_test.exs`: queue drain via refill after `:queue_full`, mixed-cost bucket-capacity cap behavior, refill token cap verification, and concurrent consume calls not losing tokens
  - **Follow-up:** The gap R011 surfaced (pending requests not drained on Gun disconnect) is addressed by R042 above.
- **Deployment considerations guide** — New `docs/guides/deployment_considerations.md` covering latency sensitivity by strategy type, geographic proximity to exchange matching engines, connection architecture trade-offs (single vs pool vs per-account), production monitoring signals, and cancel-on-disconnect interactions. Framed as "questions to ask yourself" rather than prescriptive rules — the right answer depends on the operator's strategy and constraints. Cross-linked from README guide table and registered in `mix.exs` ExDoc `Guides` group (R025)
- **Reconnection behavior documentation** — USAGE_RULES.md now distinguishes automatic reconnect from explicit `Client.reconnect/1`, documenting what is preserved, reset, or carried across each path (R030)
- **Config preservation regression tests** — Mock-server regression tests now run in the default test suite and verify: retry_count resets after successful automatic reconnect, handler callbacks survive reconnect, Config structs remain identical across reconnects, supervised reconnect reruns lifecycle callbacks under `ClientSupervisor`, and explicit reconnect preserves the stored connection contract even after the original client is closed (R030)

## [0.4.0] - 2026-04-12

### Added
- **Self-describing API via Descripex** — All 17 library modules annotated with `use Descripex` and `api()` macro declarations. Root `ZenWebsocket` module uses `Descripex.Discoverable` for three-level progressive disclosure: `describe/0` (library overview), `describe/1` (module functions), `describe/2` (full function detail). Existing `@doc` strings preserved — `api()` writes machine-readable hints (BEAM slot 5) while `@doc` retains human prose (slot 4). Enables MCP tool discovery and JSON Schema generation. Tests cover all three describe levels and module registration completeness (R040)
- **Custom client discovery hooks** — `send_balanced/2` accepts optional `:client_discovery` function for plugging in custom registries (pg, Horde, :global) instead of local-only discovery. `start_client/2` accepts `:on_connect` and `:on_disconnect` lifecycle callbacks for external registry integration. Default behavior (local discovery via `list_clients/0`) unchanged. Documentation with pg and Horde examples in USAGE_RULES.md (R024)

### Fixed
- **Stale client PIDs no longer crash callers** — `send_message/2`, `get_state/1`, `get_heartbeat_health/1`, `get_state_metrics/1`, and `get_latency_stats/1` now check `Process.alive?` before `GenServer.call`. Dead PIDs return appropriate fallbacks (error tuple, `:disconnected`, or `nil`) instead of raising `:exit`. `send_balanced/2` benefits automatically via existing failover logic. Best-effort guard — callers needing race-proof delivery should use `send_balanced/2` with `:client_discovery` (R024) (R029)
- **Subscription messages not reaching user handler** — `route_data_frame/2` sent `"method" => "subscription"` messages only to `SubscriptionManager`, never forwarding to the user handler callback. Now updates tracker state and forwards to handler (R038)
- **Protocol errors not reaching user handler** — `handle_frame_error/2` stopped the GenServer on protocol errors without notifying the user handler first. Now calls `handler.({:protocol_error, reason})` before stopping, matching the `create_handler/1` contract (R039)
- **Double callback delivery bug** — `MessageHandler.handle_message/2` called user handler, then `route_data_frame` called it again for every data frame. Added `decode_and_handle_control/1` to MessageHandler for decode + control frame handling without handler invocation; Client GenServer uses this instead. Malformed frames are still classified as fatal protocol errors via ErrorHandler (R035)
- Skipped reconnection TODO replaced with real integration test — verifies Client GenServer survives MockWebSockServer disconnect and enters reconnection mode (R033)
- WebSocket upgrade now preserves query parameters from the connection URL — previously `wss://host/path?token=abc` would upgrade as just `/path`, dropping the query string (R031)
- `DeribitAdapter.subscribe/2`, `unsubscribe/2`, `authenticate/1`, and `send_request/3` now return `{:error, :not_connected}` when client is nil instead of raising `FunctionClauseError` (R027)
- `BatchSubscriptionManager` now handles subscribe failures: marks request as failed with error reason and stops processing instead of silently ignoring the return value (R028)
- `DeribitGenServerAdapter` `@doc` corrected from "handler module" to "handler function" (R028)
- **ErrorHandling example missing `handle_info` clause** — `{:websocket_error, reason}` messages caused `FunctionClauseError` in `examples/docs/error_handling.ex`. Added catch-all error handler clause (R041)
- **`subscribe/2` return type documented incorrectly** — USAGE_RULES.md showed `{:ok, subscription_id}` but actual spec returns `:ok | {:error, term()}` (R041)
- **`send_message/2` examples passed maps instead of binaries** — README.md and USAGE_RULES.md examples used `%{action: "ping"}` but spec requires `binary()`. Fixed to use `Jason.encode!/1` (R041)
- **Non-existent telemetry event documented** — `[:zen_websocket, :client, :message_received]` in USAGE_RULES.md replaced with accurate event list (R041)
- **Stale telemetry events in performance_tuning.md** — Events table listed `[:zen_websocket, :request, :start/complete/timeout]` and `[:zen_websocket, :subscription, :add/remove]` which use wrong namespaces. Replaced with actual 16 events from codebase across 6 namespaces (R041)
- **`get_state/1` misused in performance_tuning.md** — Examples showed `Client.get_state/1` returning full state map. Fixed to use `get_latency_stats/1`, `get_heartbeat_health/1`, `get_state_metrics/1` (R041)
- **Monitoring return shapes wrong in docs** — `get_heartbeat_health` documented as `%{failures: ..., last_at: ...}` but returns `%{failure_count: ..., last_heartbeat_at: ...}`. `get_state_metrics` documented as `%{pending_requests: ..., subscriptions: ..., memory_bytes: ...}` but returns `%{pending_requests_size: ..., subscriptions_size: ..., state_memory: ...}`. Latency stats documented as floats but returns integers. Fixed in USAGE_RULES.md and performance_tuning.md (R041)
- **`reconnect/1` missing limitation note** — Documented without noting it drops custom opts (headers, timeouts, etc.) on reconnect. Added note referencing R030 (R041)
- **ErrorHandling example `send_message` @doc claimed JSON encoding** — `@doc` said "will be JSON encoded" but `Client.send_message/2` requires binary. Fixed doc and spec (R041)
- **Architecture.md claimed "Gun HTTP/2"** — Library actually forces HTTP/1.1 ALPN for WSS upgrades. Also claimed "5 functions per module" without qualifying existing modules. Fixed both (R041)
- **`last_heartbeat_at` documented as DateTime** — Docs showed `~U[...]` but actual value is `System.monotonic_time(:millisecond)` (monotonic integer). Fixed in USAGE_RULES.md and performance_tuning.md (R041)
- **ErrorHandling example understated error surface** — `send_message/1` doc/spec claimed only `:ok | {:error, :not_connected}` but delegates to `Client.send_message/2` which returns `:ok | {:ok, map()} | {:error, term()}` including `{:error, {:not_connected, reason}}` variants. Fixed spec and doc (R041)

### Improved
- Reconnection test now restarts mock server and verifies post-reconnect frame delivery — previously only proved GenServer survived disconnect (R036)
- Subscribe test now captures server-received frame and validates JSON-RPC payload structure (method, channels) — previously only checked `:ok` return (R037)

- **Example files updated for handler contract change** — `ErrorHandling` example now handles `{:websocket_protocol_error, ...}` and `{:websocket_frame_error, ...}` instead of non-existent `{:websocket_error, ...}`; `JsonRpcClient.handle_message/1` now accepts pre-decoded maps instead of assuming raw JSON strings (codex review)
- **AGENTS.md module overview corrected** — Fixed stale function names across 9 modules (Frame, ErrorHandler, JsonRpc, Reconnection, MessageHandler, HeartbeatManager, SubscriptionManager, RequestCorrelator, RateLimiter). Added missing LatencyStats entry. Fixed test code example using non-existent `Frame.encode/1` (codex review)

### Changed
- **Quality workflow updated** — Removed `mix lint`, `mix typecheck`, `mix coverage`, `mix check`, `mix rebuild` aliases from mix.exs. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly for AI-friendly structured output. `mix security` remains as the Sobelow alias and now includes `--skip` so `.sobelow-skips` is honored for the known low-confidence Recorder findings.
- **CLAUDE.md imports updated** — Added `cli-aliases.md` and `agent-economy.md` includes; reordered to match Elixir Library template
- **Roadmap reformatted** — Migrated to `[D:X/B:Y/U:Z → Eff:W]` priority format; archived completed task details to CHANGELOG; added doc-update requirement to all pending tasks
- **Added `descripex ~> 0.6`** dependency for self-describing APIs
- **All docs updated** — README, AGENTS.md, CONTRIBUTING.md, USAGE_RULES.md updated to reference JSON output commands instead of removed aliases
- **Handler callback contract** — valid JSON text frames are now delivered as decoded maps (`%{"key" => "value"}`) instead of raw binary strings. Non-JSON text frames remain as binary. If your handler pattern-matches on `{:websocket_message, msg} when is_binary(msg)` and calls `Jason.decode/1`, update to match on `{:websocket_message, %{} = msg}` for JSON and `{:websocket_message, msg} when is_binary(msg)` for non-JSON text (R035)
- Root `ZenWebsocket` moduledoc rewritten to document current API — replaces legacy references to `Connection`, `Platform`, `Behaviors`, and `Defaults` with actual `Client`, `ClientSupervisor`, and module index (R034)
- **AGENTS.md module overview and file tree updated** — Corrected function names/arities for all modules, added missing ConnectionRegistry/Debug entries, updated file organization tree to all 19 modules, removed stale "separate mix project" guidance for examples (R041)
- **docs/Architecture.md updated** — Added 9 missing modules (LatencyStats, RecorderServer, Testing, ClientSupervisor, PoolRouter, Debug, HeartbeatManager, SubscriptionManager, RequestCorrelator), updated data flow diagram (R041)
- **"5 functions" framing updated** — USAGE_RULES.md, README.md, and AGENTS.md now describe "5 essential/core functions" with note about additional monitoring and management functions (R041)
- Version bump to 0.4.0

### Reverted
- R026 (Deribit example as separate mix project) — ergonomic cost outweighed benefit: broken Tidewave access, broken `.iex.exs`, 13+ stale doc references. Examples stay in `lib/zen_websocket/examples/`

## [0.3.1] - 2026-01-21

### Changed
- Update ex_doc to ~> 0.40 for llms.txt support (AI-friendly documentation)

## [0.3.0] - 2026-01-21

### Added
- `ZenWebsocket.PoolRouter` module for health-based connection routing (R022)
  - `select_connection/1` - select healthiest connection from pool
  - `calculate_health/1` - score (0-100) based on pending requests, latency, errors, pressure
  - `record_error/1` / `clear_errors/1` - error tracking with 60s decay
  - `pool_health/1` - get health snapshot for all connections
  - Round-robin fallback when connections have equal health
- `ClientSupervisor.send_balanced/2` for load-balanced message routing (R022)
  - Routes to healthiest connection using PoolRouter scoring
  - Automatic failover on send failure (configurable max_attempts)
  - Records errors and emits telemetry on failover
- Telemetry events for pool routing (R022)
  - `[:zen_websocket, :pool, :route]` - connection selected with health score
  - `[:zen_websocket, :pool, :health]` - pool health snapshot
  - `[:zen_websocket, :pool, :failover]` - failover attempt with reason
- `AGENTS.md` guide for AI coding agents contributing to the project (R023)
  - Module overview with key functions
  - Project constraints (5 functions, 15 lines, real API testing)
  - Testing strategy and common patterns
  - Debugging guide (recording, state inspection)
- `ZenWebsocket.Testing` module with consumer-facing test utilities (R020)
  - `start_mock_server/1` - simplified mock server startup with URL generation
  - `stop_server/1` - cleanup server and resources
  - `simulate_disconnect/2` - trigger disconnect scenarios (`:normal`, `:going_away`, `{:code, n}`)
  - `inject_message/2` - send message from server to connected clients
  - `assert_message_sent/3` - verify client sent expected message (string, regex, map, or function matcher)
  - Helpers integrate with ExUnit setup/on_exit patterns
- `ZenWebsocket.Recorder` module for session recording (R019)
  - `format_entry/3` - format frames as JSONL entries
  - `parse_entry/1` - parse JSONL entries back to structs
  - `replay/3` - stream recorded sessions to handler function
  - `metadata/1` - get session statistics (count, duration, timestamps)
- `ZenWebsocket.RecorderServer` async GenServer for file I/O (R019)
  - Buffered writes with periodic flush (1s interval or 100 entries)
  - Non-blocking `record/3` via send (not call)
  - `stats/1` returns entries count and bytes written
- Config option `record_to: path` enables session recording (R019)
  - Records inbound and outbound frames with microsecond timestamps
  - JSONL format (one JSON object per line) for streaming writes
  - Binary frames encoded as base64
  - Close frames include code and reason

### Changed
- `PoolRouter.calculate_health/1` uses `div/2` for cleaner integer arithmetic
- `ClientSupervisor` restart policy documented in `@moduledoc` (moved from comment)
- Private functions consistently use `@doc false` with explanatory comments
- `USAGE_RULES.md` expanded with v0.2.0+ features (R023)
  - Testing module documentation (replaced MockWebSockServer references)
  - Session recording section with Recorder API
  - Expanded monitoring/observability section (latency, heartbeat, metrics)
  - ErrorHandler.explain/1 usage example
  - New config options (record_to, latency_buffer_size)
  - Telemetry events reference table
  - Updated test count (93 → 395)

### Removed
- Stale documentation files superseded by ROADMAP.md and AGENTS.md
  - `docs/TaskList.md`, `docs/deferred_tasks.md`
  - `docs/JsonRPCElixir_MigrationTasks.md`, `docs/json_rpc_elixir.md`
  - `docs/WNX0019_learnings.md`, `docs/test_roadmap.md`

## [0.2.0] - 2026-01-20

### Added
- Building Adapters Guide enhanced at `docs/guides/building_adapters.md` (R012)
  - Adapter decision tree (plain client vs struct vs GenServer)
  - Heartbeat interface documentation (`:deribit`, `:ping_pong`, `:binance`, custom)
  - Authentication patterns (API key+secret, HMAC signature, OAuth token flow)
  - Binance Spot adapter example (non-JSON-RPC pattern)
- Performance Tuning Guide at `docs/guides/performance_tuning.md` (R013)
  - Configuration parameter tuning (timeouts, reconnection, latency buffer)
  - Rate limiter tuning with exchange-specific cost functions
  - Telemetry events reference table
  - Memory characteristics documentation
  - Common tuning scenarios (HFT, market data, resource-constrained)
- JsonRpc edge case tests for nil/empty params, empty methods, malformed responses (R016)
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

[Unreleased]: https://github.com/ZenHive/zen_websocket/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/ZenHive/zen_websocket/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/ZenHive/zen_websocket/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ZenHive/zen_websocket/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ZenHive/zen_websocket/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/ZenHive/zen_websocket/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/ZenHive/zen_websocket/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ZenHive/zen_websocket/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ZenHive/zen_websocket/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ZenHive/zen_websocket/releases/tag/v0.1.1
