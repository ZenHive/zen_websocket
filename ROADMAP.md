# ZenWebsocket Refactor Roadmap

**Created:** January 2026
**Library Version:** 0.1.5 (published on hex.pm)
**Next Version:** 0.2.0 (after refactoring)
**Status:** Production-ready, architectural improvements recommended

---

## Executive Summary

ZenWebsocket is a mature, production-grade WebSocket client library with excellent reliability and real-API testing. After a deep audit, the main architectural issue is the **oversized Client module** which violates the project's stated principles. The library is functional but would benefit from modularization to improve maintainability.

---

## 🎯 Current Focus

**Published:** ✅ v0.1.5 on hex.pm (Jan 2026)

**Next:** v0.2.0 — User Experience Features

> **Philosophy reminder:** Maximum 5 functions per module, 15 lines per function, direct Gun API usage, real API testing only.

### v0.2.0 Priority Queue

| Task | Priority | What It Does |
|------|----------|--------------|
| ~~**R018**: Error Explanations~~ | ✅ Done | Human-readable error messages with fix suggestions |
| **R017**: Latency Telemetry | 🎯 2.7 | Round-trip timing, connection metrics, p50/p99 stats |
| **R021**: Backpressure Signaling | 🎯 2.0 | Proactive notifications before rate limits hit |
| R012: Building Adapters Guide | 🚀 1.7 | Documentation for creating platform adapters |

All v0.2.0 tasks are parallelizable `[P]` — can work multiple simultaneously.

### Quick Commands
```bash
mix check                    # All quality checks
mix test.json --quiet --summary-only  # Test health
mix dialyzer                 # Type checking
mix credo --strict           # Static analysis
mix hex.publish --dry-run    # Verify before publishing
```

Test tagging completed (R015) - integration tests excluded by default for fast iteration.

---

## Phase 1: Pre-Refactor ✅ COMPLETE

> Original TaskList work is done.

| Task | Status | Notes |
|------|--------|-------|
| WNX0026: Hex.pm Publishing | ✅ Complete | v0.1.4 published Nov 2025 |
| WNX0028: Business Logic Separation | ✅ Complete | Guidelines documented |

**Ready to start refactoring work.**

---

## Phase 2: Critical Refactoring [D:7/B:9 → Priority:1.3] 📋

> Break apart the monolithic Client module to match project principles.

### Task R001: Extract HeartbeatManager ✅ COMPLETE

**[D:4/B:8 → Priority:2.0]** 🎯 — January 2026

Extract heartbeat logic from Client.ex into dedicated module. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R002: Extract SubscriptionManager ✅ COMPLETE

**[D:4/B:7 → Priority:1.75]** 🚀 — January 2026

Extract subscription tracking from Client.ex into dedicated module. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R003: Extract RequestCorrelator ✅ COMPLETE

**[D:5/B:7 → Priority:1.4]** 🚀 — January 2026

Extract JSON-RPC request/response correlation from Client.ex. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R004: Slim Down Client.ex ✅ COMPLETE

**[D:6/B:9 → Priority:1.5]** 🚀 — January 2026

After extracting R001-R003, refactor Client.ex to delegate to new modules. See [CHANGELOG.md](CHANGELOG.md).

---

## Phase 3: Memory Safety [D:4/B:8 → Priority:2.0] 🎯

> Fix potential resource leaks.

### Task R005: RateLimiter ETS Cleanup ✅ COMPLETE

**[D:3/B:8 → Priority:2.7]** 🎯 — January 2026

Add proper ETS table cleanup to prevent memory leaks. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R006: ConnectionRegistry Monitor Cleanup ✅ COMPLETE

**[D:2/B:6 → Priority:3.0]** 🎯 — January 2026

Ensure monitors are always cleaned up properly. See [CHANGELOG.md](CHANGELOG.md).

---

## Phase 4: Code Quality [D:3/B:5 → Priority:1.7] 🚀

> Address Credo warnings and improve consistency.

### Task R007: Fix Credo Warnings ✅ COMPLETE

**[D:2/B:5 → Priority:2.5]** 🎯 — January 2026

Credo warnings resolved during refactoring. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R008: Replace Magic Numbers ✅ COMPLETE

**[D:2/B:4 → Priority:2.0]** 🎯 — January 2026

Replace hardcoded constants with named module attributes. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R009: Standardize Debug Logging ✅ COMPLETE

**[D:2/B:3 → Priority:1.5]** 🚀 — January 2026

Remove polymorphic debug interface confusion. See [CHANGELOG.md](CHANGELOG.md).

---

## Phase 5: Testing Enhancements [D:5/B:6 → Priority:1.2] 📋

> Improve test coverage and use installed but unused dependencies.

### Task R010: Property-Based Testing

**[D:5/B:6 → Priority:1.2]** 📋

Implement property-based tests using stream_data (already installed but unused).

**Target areas:**
- Frame encoding/decoding (round-trip properties)
- Config validation (valid configs always pass, invalid always fail)
- Message routing (pattern matching completeness)

**Success criteria:**
- [ ] Property tests for Frame module
- [ ] Property tests for Config validation
- [ ] At least 3 property-based test files
- [ ] Document property testing patterns

---

### Task R011: Error Scenario Testing

**[D:4/B:5 → Priority:1.25]** 📋

Add tests for edge cases and error scenarios.

**Target areas:**
- Gun error types not currently tested
- Frame corruption handling
- Correlation timeout cleanup
- Rate limit recovery

**Success criteria:**
- [ ] Each error category has explicit test
- [ ] Recovery paths verified
- [ ] Error messages are clear and actionable

---

### Task R015: Test Tagging Audit ✅ COMPLETE

**[D:2/B:5 → Priority:2.5]** 🎯 — January 2026

Audit test files and properly tag integration tests. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R016: Unit Test Coverage `[P]`

**[D:4/B:6 → Priority:1.5]** 🚀

After R015 tagging audit, identify and create missing unit tests for pure functions.

**Target modules for unit test coverage:**
- `Config` - validation logic, defaults, merging
- `Frame` - encoding/decoding without network
- `JsonRpc` - message formatting, ID generation
- `ErrorHandler` - error categorization logic
- `Reconnection` - backoff calculation, retry logic

**Success criteria:**
- [ ] Each core module has dedicated unit test file
- [ ] Unit tests cover edge cases (nil, empty, invalid inputs)
- [ ] Unit tests run without MockWebSockServer or network
- [ ] `mix test` (unit only) completes quickly

**Depends on:** R015 (tagging audit identifies gaps)

---

## Phase 6: Documentation Polish [D:3/B:4 → Priority:1.3] 📋

> Complete deferred documentation.

### Task R012: Building Adapters Guide

**[D:3/B:5 → Priority:1.7]** 🚀

Complete the stub guide for building platform adapters.

**Current:** `docs/guides/building_adapters.md` exists but incomplete.

**Success criteria:**
- [ ] Step-by-step guide for creating new platform adapter
- [ ] Example using non-Deribit platform
- [ ] Document heartbeat handler interface
- [ ] Document authentication patterns

---

### Task R013: Performance Tuning Guide

**[D:2/B:4 → Priority:2.0]** 🎯

Document performance characteristics and tuning options.

**Success criteria:**
- [ ] Document memory usage per connection
- [ ] Document optimal timeout configurations
- [ ] Document rate limiter tuning
- [ ] Benchmark results included

---

## Phase 7: Business Logic Migration [D:4/B:6 → Priority:1.5] 🚀

> Execute migration plan from WNX0028.

### Task R014: Migrate Deribit Examples to market_maker

**[D:4/B:6 → Priority:1.5]** 🚀

Move Deribit-specific business logic to market_maker project (per WNX0028 analysis).

**Files to migrate:**
- `deribit_adapter.ex` → `market_maker/lib/market_maker/deribit/`
- `deribit_genserver_adapter.ex` → `market_maker/lib/market_maker/deribit/`
- `deribit_rpc.ex` → `market_maker/lib/market_maker/deribit/`
- `batch_subscription_manager.ex` → `market_maker/lib/market_maker/`

**Success criteria:**
- [ ] All Deribit business logic moved
- [ ] Tests migrated with code
- [ ] zen_websocket examples remain framework-only
- [ ] No broken imports or dependencies

**Depends on:** market_maker project exists and is ready

---

## Phase 8: User Experience [D:4/B:7 → Priority:1.75] 🚀

> Features that make the library easier to use, debug, and monitor. Built on existing infrastructure.

### Task R017: Latency Telemetry

**[D:3/B:8 → Priority:2.7]** 🎯

Add latency tracking to existing telemetry infrastructure.

**Builds on:** RequestCorrelator already tracks request start time via `track/4`.

**Success criteria:**
- [ ] `[:zen_websocket, :request_correlator, :resolve]` includes `round_trip_ms` measurement
- [ ] `[:zen_websocket, :connection, :upgrade]` emits with `connect_time_ms`
- [ ] `[:zen_websocket, :heartbeat, :pong]` emits with `rtt_ms`
- [ ] `Client.get_latency_stats/1` returns p50/p99/last values
- [ ] Latency history kept in bounded circular buffer (configurable size)
- [ ] Tests verify telemetry events include timing data

---

### Task R018: Error Explanations ✅ COMPLETE

**[D:2/B:7 → Priority:3.5]** 🎯 — January 2026

Add human-readable error explanations to existing ErrorHandler. See [CHANGELOG.md](CHANGELOG.md).

---

### Task R019: Session Recording

**[D:5/B:7 → Priority:1.4]** 🚀

Add optional message recording for debugging and testing.

**Builds on:** Client already routes all messages through `route_data_frame/2`.

**Success criteria:**
- [ ] Config option `record_to: path` enables recording
- [ ] Records: timestamps, direction (in/out), raw frames, parsed messages
- [ ] JSONL format (one JSON object per line) for streaming writes
- [ ] `ZenWebsocket.Recorder.replay/2` plays back to a handler module
- [ ] Recording has minimal performance impact (<1ms overhead per message)
- [ ] Integration test with real connection recording/replay

---

### Task R020: Test Helpers Module

**[D:4/B:6 → Priority:1.5]** 🚀

Create consumer-facing test utilities building on MockWebSockServer.

**Builds on:** MockWebSockServer exists in `test/support/` but isn't exposed to consumers.

**Success criteria:**
- [ ] `ZenWebsocket.Testing` module with public helpers
- [ ] `start_mock_server/1` - simplified server startup
- [ ] `simulate_disconnect/2` - trigger disconnect scenarios
- [ ] `assert_message_sent/3` - verify client sent expected message
- [ ] `inject_message/2` - send message from server to client
- [ ] Helpers work with ExUnit (setup/on_exit integration)
- [ ] Documentation with usage examples

---

### Task R021: Backpressure Signaling

**[D:3/B:6 → Priority:2.0]** 🎯

Add proactive backpressure notifications to consumers.

**Builds on:** RateLimiter already tracks queue depth and tokens via ETS.

**Success criteria:**
- [ ] New telemetry event `[:zen_websocket, :rate_limiter, :pressure]` with `level: :low | :medium | :high`
- [ ] Emitted when queue crosses configurable thresholds (default: 25%, 50%, 75%)
- [ ] `RateLimiter.status/1` enhanced with `suggested_delay_ms` field
- [ ] Optional callback `handle_backpressure/2` in client handler behavior
- [ ] Config option `backpressure_thresholds: [low: 0.25, medium: 0.5, high: 0.75]`
- [ ] Tests verify threshold crossing emits correct events

---

### Task R022: Connection Pool Load Balancing

**[D:6/B:6 → Priority:1.0]** 📋

Add load balancing to existing ClientSupervisor infrastructure.

**Builds on:** ClientSupervisor + ConnectionRegistry already manage multiple clients.

**Success criteria:**
- [ ] `ClientSupervisor.send_balanced/2` routes to healthiest connection
- [ ] Health score based on: pending requests, latency, error rate
- [ ] Round-robin fallback when all connections have equal health
- [ ] Automatic failover when connection dies
- [ ] Telemetry for pool utilization metrics
- [ ] Integration tests with multiple connections

**Depends on:** R017 (latency metrics needed for health scoring)

---

## Phase 9: Test Coverage Infrastructure [D:3/B:7 → Priority:2.3] 🎯

> Fix misleading coverage metrics and add targeted tests for real gaps.

### Task T001: Configure Coverage Exclusions ✅ COMPLETE

**[D:1/B:8 → Priority:8.0]** 🎯 — January 2026

Exclude non-production modules from coverage metrics:
- `ZenWebsocket.Test.Support.*` - Test infrastructure
- `ZenWebsocket.Examples.*` - Documentation examples
- `Mix.Tasks.*` - CLI utilities

**Result:** Coverage jumped from ~38% to ~70% by measuring only production code.

---

### Task T002: Frame Edge Case Tests ✅ COMPLETE

**[D:2/B:5 → Priority:2.5]** 🎯 — January 2026

Added tests for direct frame format decoding and close frame variants.

---

### Task T003: Config Boundary Value Tests ✅ COMPLETE

**[D:2/B:4 → Priority:2.0]** 🎯 — January 2026

Added tests for `new!/2`, `request_timeout` validation, and edge cases.

---

### Task T004: Reconnection Extreme Value Tests ✅ COMPLETE

**[D:2/B:4 → Priority:2.0]** 🎯 — January 2026

Added tests for nil max_backoff, very large attempts, and zero retries.

---

### Task T005: Property-Based Tests

**[D:4/B:6 → Priority:1.5]** 🚀

See R010 in Phase 5. Uses stream_data for:
- Frame encoding/decoding round-trips
- Config validation invariants

---

See [docs/test_roadmap.md](docs/test_roadmap.md) for detailed test coverage analysis.

---

## Priority Summary

### Immediate (Before v0.2.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| T001: Coverage Exclusions | 🎯 8.0 | D:1 | ✅ Complete |
| R006: Monitor Cleanup | 🎯 3.0 | D:2 | ✅ Complete |
| R005: RateLimiter ETS Cleanup | 🎯 2.7 | D:3 | ✅ Complete |
| T002: Frame Edge Case Tests | 🎯 2.5 | D:2 | ✅ Complete |
| R015: Test Tagging Audit | 🎯 2.5 | D:2 | ✅ Complete |
| R007: Fix Credo Warnings | 🎯 2.5 | D:2 | ✅ Complete |
| T003: Config Boundary Tests | 🎯 2.0 | D:2 | ✅ Complete |
| T004: Reconnection Extreme Tests | 🎯 2.0 | D:2 | ✅ Complete |
| R008: Replace Magic Numbers | 🎯 2.0 | D:2 | ✅ Complete |
| R001: Extract HeartbeatManager | 🎯 2.0 | D:4 | ✅ Complete |
| R002: Extract SubscriptionManager | 🚀 1.75 | D:4 | ✅ Complete |
| R003: Extract RequestCorrelator | 🚀 1.4 | D:5 | ✅ Complete |

### Short-term (v0.2.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| R018: Error Explanations | 🎯 3.5 | D:2 | ✅ Complete |
| R017: Latency Telemetry | 🎯 2.7 | D:3 | ⬜ Pending |
| R021: Backpressure Signaling | 🎯 2.0 | D:3 | ⬜ Pending |
| R012: Building Adapters Guide | 🚀 1.7 | D:3 | ⬜ Pending |
| R004: Slim Down Client.ex | 🚀 1.5 | D:6 | ✅ Complete |
| R009: Standardize Debug Logging | 🚀 1.5 | D:2 | ✅ Complete |

### Medium-term (v0.3.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| R013: Performance Tuning Guide | 🎯 2.0 | D:2 | ⬜ Pending |
| R016: Unit Test Coverage | 🚀 1.5 | D:4 | ⬜ Pending |
| R020: Test Helpers Module | 🚀 1.5 | D:4 | ⬜ Pending |
| R014: Migrate Deribit Examples | 🚀 1.5 | D:4 | ⬜ Blocked |
| R019: Session Recording | 🚀 1.4 | D:5 | ⬜ Pending |
| R011: Error Scenario Testing | 📋 1.25 | D:4 | ⬜ Pending |
| R010: Property-Based Testing | 📋 1.2 | D:5 | ⬜ Pending |

### Long-term (v0.4.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| R022: Connection Pool Load Balancing | 📋 1.0 | D:6 | ⬜ Pending |

---

## Parallel Work Opportunities

These tasks can be worked on simultaneously:

```
v0.2.0 Parallelizable:
R017 [P] - Latency Telemetry (RequestCorrelator)
R018 ✅  - Error Explanations (COMPLETE)
R021 [P] - Backpressure Signaling (RateLimiter)
R012 [P] - Building Adapters Guide (docs)

v0.3.0 Parallelizable:
R013 [P] - Performance Tuning Guide (docs)
R016 [P] - Unit Test Coverage (tests)
R019 [P] - Session Recording (Client)
R020 [P] - Test Helpers Module (test support)
```

**Coordination rule:** Update status to 🔄 with branch name before starting.

**Dependency note:** R022 (Connection Pool) depends on R017 (Latency Telemetry) for health scoring.

---

## Quality Gates

Quality gates that must pass before each release:

```bash
mix test.json --quiet --summary-only  # All tests pass
mix dialyzer                          # No new warnings
mix credo --strict                    # Score ≥8.0
mix doctor                            # 100% moduledoc coverage
```

---

## Architectural Decisions

### Why Split Client.ex?

The Client module handles too many concerns:
1. Connection lifecycle (connect, close, reconnect)
2. Message sending and routing
3. Heartbeat management
4. Subscription tracking
5. Request/response correlation
6. State management

This violates:
- "Maximum 5 functions per module" principle
- "Maximum 15 lines per function" principle
- Single Responsibility Principle

Splitting improves:
- **Testability** - Each concern tested independently
- **Maintainability** - Changes isolated to relevant module
- **Readability** - Smaller, focused modules
- **Extensibility** - Easy to swap implementations

### Why Keep Some Large Examples?

Example files like `deribit_rpc.ex` are:
- Example/documentation code, not core library
- Scheduled for migration to market_maker
- Acceptable complexity for demonstration purposes

---

## Changelog Template

When completing tasks, update CHANGELOG.md:

```markdown
## [Unreleased]

### Changed
- Extracted HeartbeatManager from Client module (R001)
- Extracted SubscriptionManager from Client module (R002)

### Fixed
- RateLimiter ETS tables now properly cleaned up on termination (R005)
- Credo warnings resolved in test files (R007)

### Added
- Property-based tests for Frame encoding/decoding (R010)
- Performance tuning documentation (R013)
```

---

## Notes for Future Claude Instances

This roadmap was created after a deep audit of the zen_websocket library. Key context:

1. **The library works well** - This is improvement, not emergency repair
2. **Phase 2-4 complete** - Client.ex refactored, memory safety fixed, code quality improved
3. **Phase 8 is the new focus** - User experience features that build on existing infrastructure
4. **Business logic migration depends on market_maker** - External dependency (R014 blocked)
5. **Real API testing is non-negotiable** - Project principle, don't add mocks

**Phase 8 builds on existing code:**
- R017 (Latency) → extends RequestCorrelator telemetry
- R018 (Errors) → extends ErrorHandler with explanations
- R019 (Recording) → hooks into Client.route_data_frame/2
- R020 (Test Helpers) → exposes MockWebSockServer to consumers
- R021 (Backpressure) → extends RateLimiter telemetry
- R022 (Pool) → extends ClientSupervisor with load balancing

The project has excellent documentation. Read:
- `CLAUDE.md` for project principles
- `docs/TaskList.md` for existing task tracking
- `docs/Architecture.md` for system design
