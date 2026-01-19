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

Ready for refactoring work → **v0.2.0**

> **Philosophy reminder:** Maximum 5 functions per module, 15 lines per function, direct Gun API usage, real API testing only.

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

**[D:4/B:8 → Priority:2.0]** 🎯

**Completed:** January 2026

Extract heartbeat logic from Client.ex into dedicated module.

**Success criteria:**
- [x] New `ZenWebsocket.HeartbeatManager` module created
- [x] Handles platform-specific heartbeat sending (Deribit, generic, ping_pong)
- [x] Tracks heartbeat state (last_sent, interval, type)
- [x] Client delegates heartbeat operations to new module
- [x] All existing heartbeat tests pass

**What was done:**
- Created `lib/zen_websocket/heartbeat_manager.ex` with 5 public functions:
  - `start_timer/1` - Start heartbeat timer on connection upgrade
  - `cancel_timer/1` - Cancel timer on disconnect/error
  - `handle_message/2` - Route incoming heartbeat messages
  - `send_heartbeat/1` - Send platform-specific heartbeat
  - `get_health/1` - Return health metrics map
- Created `test/zen_websocket/heartbeat_manager_test.exs` with unit tests
- Client.ex reduced, private heartbeat functions removed
- All tests pass, Dialyzer passes, Credo passes

---

### Task R002: Extract SubscriptionManager ✅ COMPLETE

**[D:4/B:7 → Priority:1.75]** 🚀

**Completed:** January 2026

Extract subscription tracking from Client.ex into dedicated module.

**Success criteria:**
- [x] New `ZenWebsocket.SubscriptionManager` module created
- [x] Tracks active subscriptions per client
- [x] Handles subscription restoration after reconnect
- [x] Clean API: `add/2`, `remove/2`, `list/1`, `build_restore_message/1`, `handle_message/2`
- [x] All existing subscription tests pass

**What was done:**
- Created `lib/zen_websocket/subscription_manager.ex` with 5 public functions:
  - `add/2` - Add channel to tracked set (on confirmation)
  - `remove/2` - Remove channel from tracked set
  - `list/1` - List all tracked subscriptions
  - `build_restore_message/1` - Build JSON restore message for reconnection
  - `handle_message/2` - Handle incoming subscription confirmation messages
- Created `test/zen_websocket/subscription_manager_test.exs` with comprehensive unit tests
- Client.ex updated to delegate subscription handling to SubscriptionManager
- Automatic subscription restoration on reconnect (respects `restore_subscriptions` config)
- Deleted private `handle_subscription_message/2` from Client.ex

**Fixed:** Dialyzer warning on `maybe_restore_subscriptions/1` resolved by expanding `Client.state()` type to include all required fields.

---

### Task R003: Extract RequestCorrelator ✅ COMPLETE

**[D:5/B:7 → Priority:1.4]** 🚀

**Completed:** January 2026

Extract JSON-RPC request/response correlation from Client.ex.

**Success criteria:**
- [x] New `ZenWebsocket.RequestCorrelator` module created
- [x] Tracks pending requests with timeouts
- [x] Matches responses to requests by ID
- [x] Cleans up timed-out requests properly
- [x] API: `extract_id/1`, `track/4`, `resolve/2`, `timeout/2`, `pending_count/1`
- [x] All JSON-RPC correlation tests pass

**What was done:**
- Created `lib/zen_websocket/request_correlator.ex` with 5 public functions:
  - `extract_id/1` - Extract request ID from JSON message
  - `track/4` - Track pending request with timeout timer
  - `resolve/2` - Match response to pending request, cancel timer
  - `timeout/2` - Handle timeout for pending request
  - `pending_count/1` - Return count of pending requests
- Created `test/zen_websocket/request_correlator_test.exs` with 28 unit tests
- Added telemetry events: `:track`, `:resolve`, `:timeout`
- Client.ex updated to delegate correlation to RequestCorrelator
- Pure functional design - state ownership stays with Client GenServer

---

### Task R004: Slim Down Client.ex ✅ COMPLETE

**[D:6/B:9 → Priority:1.5]** 🚀

**Completed:** January 2026

After extracting R001-R003, refactor Client.ex to delegate to new modules.

**Success criteria:**
- [x] Client.ex significantly reduced
- [x] Client focuses only on: connection lifecycle, message routing, public API
- [x] All extracted concerns delegated to specialized modules
- [x] No functionality changes - all tests pass
- [x] Maintains backward-compatible public API

**Depends on:** R001, R002, R003 (all complete)

**What was done:**
- Delegation was completed by R001-R003: Client.ex now delegates to HeartbeatManager, SubscriptionManager, and RequestCorrelator
- Removed dead `restore_subscriptions/4` from Reconnection module (superseded by `SubscriptionManager.build_restore_message/1`)
- Client.ex (802 lines) focuses on: connection lifecycle, message routing, GenServer callbacks, public API (10 functions)
- Line count "violations" are justified: `init/1` initializes 13-field state map, `handle_continue(:connect/:reconnect)` include ~10-12 lines of debug logging each

**Remaining private functions in Client are GenServer-specific concerns:**
- `route_data_frame/2` - message dispatch (orchestration role)
- `handle_rpc_response/2` - GenServer reply semantics
- `handle_connection_error/2` - reconnect vs stop decision
- `build_client_struct/2` - API adaptation layer
- `maybe_restore_subscriptions/1` - Gun operation wrapper

---

## Phase 3: Memory Safety [D:4/B:8 → Priority:2.0] 🎯

> Fix potential resource leaks.

### Task R005: RateLimiter ETS Cleanup ✅ COMPLETE

**[D:3/B:8 → Priority:2.7]** 🎯

Add proper ETS table cleanup to prevent memory leaks.

**Success criteria:**
- [x] Implement `shutdown/1` function for ETS cleanup
- [x] Add configurable `max_queue_size` option (default: 100)
- [x] Add telemetry for rate limiting events (consume, queue, queue_full, refill)
- [x] Test cleanup behavior (idempotent shutdown)
- [x] Document memory characteristics in @moduledoc

**Completed:** January 2026

**What was done:**
- Added `shutdown/1` function that safely deletes ETS table (check-first pattern, idempotent)
- Added `max_queue_size` config option with `@default_max_queue_size 100` module attribute
- Added 4 telemetry events: `:consume`, `:queue`, `:queue_full`, `:refill` with measurements
- Added comprehensive tests for shutdown, configurable queue size, and telemetry events
- Updated @moduledoc with memory characteristics and cleanup instructions
- Optimized `handle_rate_limit/5` to accept config as parameter (avoids double ETS lookup)
- Added `on_exit` cleanup to test setup for proper ETS cleanup

---

### Task R006: ConnectionRegistry Monitor Cleanup ✅ COMPLETE

**[D:2/B:6 → Priority:3.0]** 🎯

Ensure monitors are always cleaned up properly.

**Success criteria:**
- [x] Verify monitor dereference on all exit paths
- [x] Add cleanup in terminate callback
- [x] Test registry behavior under process crashes
- [x] No monitor leaks in long-running scenarios

**Completed:** January 2026

**What was done:**
- Fixed `cleanup_dead/1` to use `match_object` + iterate + demonitor before delete (was using `match_delete` which skipped demonitor)
- Fixed `shutdown/0` to call new `demonitor_all/0` helper before table deletion
- Added `demonitor_all/0` private helper that iterates all entries and demonitors each
- Added 3 new tests verifying monitor cleanup behavior

---

## Phase 4: Code Quality [D:3/B:5 → Priority:1.7] 🚀

> Address Credo warnings and improve consistency.

### Task R007: Fix Credo Warnings ✅ COMPLETE

**[D:2/B:5 → Priority:2.5]** 🎯

**Completed:** January 2026

The `length/1` warnings no longer appear - likely fixed during other refactoring work or Credo configuration updates.

**Current state:** 1 TODO comment in test file (acceptable, not a warning)

---

### Task R008: Replace Magic Numbers ✅ COMPLETE

**[D:2/B:4 → Priority:2.0]** 🎯

**Completed:** January 2026

Replace hardcoded constants with named module attributes.

**Success criteria:**
- [x] All timeout adjustments use named constants
- [x] Each constant has documentation comment
- [x] No unexplained numeric literals in core modules

**What was done:**
- Added `@genserver_call_buffer_ms` and `@minimum_connection_timeout_ms` to Client.ex
- Added `@max_restarts`, `@restart_window_seconds`, `@supervision_buffer_ms` to ClientSupervisor.ex
- Added `@default_max_backoff_ms` to Reconnection.ex
- Removed redundant fallbacks that duplicated Config defaults (e.g., `Map.get(state.config, :request_timeout, 30_000)` → `state.config.request_timeout`)
- Heartbeat intervals now fall back to `state.config.heartbeat_interval` instead of hardcoded values

---

### Task R009: Standardize Debug Logging

**[D:2/B:3 → Priority:1.5]** 🚀

Remove polymorphic debug interface confusion.

**Current issue:** Debug.log accepts both Config structs and state maps.

**Success criteria:**
- [ ] Single consistent interface for Debug.log
- [ ] All callers updated to use consistent pattern
- [ ] No ambiguity in debug function signatures

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

**[D:2/B:5 → Priority:2.5]** 🎯

**Completed:** January 2026

Audit test files and properly tag integration tests that depend on external services.

**Success criteria:**
- [x] All tests audited for proper tagging
- [x] Unit tests (pure logic, no I/O) run without `:integration` tag
- [x] `mix test` completes quickly (unit tests only)
- [x] `mix test --include integration` runs full suite
- [x] Document tagging conventions in test_helper.exs

**What was done:**
- Added `@moduletag :integration` to test files using MockWebSockServer or external APIs
- `rate_limiting_test.exs` uses `@describetag :integration` only on network-dependent describe blocks
- `platform_adapter_template_test.exs` left as unit test (pure function tests, no network)
- Added tagging convention documentation to `test/test_helper.exs`

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

## Priority Summary

### Immediate (Before v0.2.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| R006: Monitor Cleanup | 🎯 3.0 | D:2 | ✅ Complete |
| R005: RateLimiter ETS Cleanup | 🎯 2.7 | D:3 | ✅ Complete |
| R015: Test Tagging Audit | 🎯 2.5 | D:2 | ✅ Complete |
| R007: Fix Credo Warnings | 🎯 2.5 | D:2 | ✅ Complete |
| R008: Replace Magic Numbers | 🎯 2.0 | D:2 | ✅ Complete |
| R001: Extract HeartbeatManager | 🎯 2.0 | D:4 | ✅ Complete |
| R002: Extract SubscriptionManager | 🚀 1.75 | D:4 | ✅ Complete |
| R003: Extract RequestCorrelator | 🚀 1.4 | D:5 | ✅ Complete |

### Short-term (v0.2.0)

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| R012: Building Adapters Guide | 🚀 1.7 | D:3 | ⬜ Pending |
| R004: Slim Down Client.ex | 🚀 1.5 | D:6 | ✅ Complete |
| R009: Standardize Debug Logging | 🚀 1.5 | D:2 | ⬜ Pending |

### Medium-term (v0.3.0)

| Task | Priority | Effort |
|------|----------|--------|
| R014: Migrate Deribit Examples | 🚀 1.5 | D:4 |
| R013: Performance Tuning Guide | 🎯 2.0 | D:2 |
| R010: Property-Based Testing | 📋 1.2 | D:5 |
| R011: Error Scenario Testing | 📋 1.25 | D:4 |

---

## Parallel Work Opportunities

These tasks can be worked on simultaneously:

```
R009 [P] - Standardize Debug Logging (independent)
R012, R013 [P] - Documentation (independent)
R016 [P] - Unit Test Coverage (depends on R015, complete)
```

**Coordination rule:** Update status to 🔄 with branch name before starting.

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
2. **Client.ex is the main target** - Too many concerns in one module
3. **WNX0026 (hex.pm) should complete first** - Don't refactor during publish prep
4. **Business logic migration depends on market_maker** - External dependency
5. **Real API testing is non-negotiable** - Project principle, don't add mocks

The project has excellent documentation. Read:
- `CLAUDE.md` for project principles
- `docs/TaskList.md` for existing task tracking
- `docs/Architecture.md` for system design
