# ZenWebsocket Refactor Roadmap

**Created:** January 2026
**Library Version:** 0.1.5 (published on hex.pm)
**Next Version:** 0.2.0 (after refactoring)
**Status:** Production-ready, architectural improvements recommended

---

## Executive Summary

ZenWebsocket is a mature, production-grade WebSocket client library with excellent reliability and real-API testing. After a deep audit, the main architectural issue is the **oversized Client module (862 lines)** which violates the project's stated principles. The library is functional but would benefit from modularization to improve maintainability.

**Overall Grade: A- (8.5/10)**

---

## 🎯 Current Focus

**Published:** ✅ v0.1.5 on hex.pm (Jan 2026)

Ready for refactoring work → **v0.2.0**

> **Philosophy reminder:** Maximum 5 functions per module, 15 lines per function, direct Gun API usage, real API testing only.

### Quick Commands
```bash
mix check                    # All quality checks
mix test.json --quiet --summary-only  # Test health
mix dialyzer                 # Type checking (14 skips, passes)
mix credo --strict           # 6 warnings, 33 readability issues
mix hex.publish --dry-run    # Verify before publishing
```

### ⚠️ Test Suite Alert

**Current status:** 205 tests, 32 failures (timeout-related)

The failures are `{:error, :timeout}` errors connecting to `echo.websocket.org`. This external service is unreliable. Consider:
- Using `test.deribit.com` as primary test target (project standard)
- Adding retry logic for flaky external services
- Running `mix test --only deribit` for reliable integration tests

---

## Audit Findings Summary

### Code Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Core LOC | 1,938 | ✅ Good |
| Test/Code Ratio | ~1.2:1 | ✅ Good |
| Module Count | 11 core | ✅ Good |
| Largest Module | 862 lines (Client) | ❌ Violates principles |
| Type Coverage | ~85% | ✅ Good |
| Documentation | ~95% | ✅ Excellent |
| Dialyzer | Passes (14 skips) | ✅ Good |
| Credo Strict | 6 warnings | ⚠️ Minor issues |

### Module Size Distribution

| Module | Lines | Status |
|--------|-------|--------|
| client.ex | 862 | ❌ 57x over 15-line function limit |
| deribit_rpc.ex | 237 | ⚠️ High but acceptable (examples) |
| deribit_genserver_adapter.ex | 231 | ⚠️ Business logic (migrate out) |
| reconnection.ex | 200 | ✅ Good |
| batch_subscription_manager.ex | 181 | ⚠️ Business logic (migrate out) |
| rate_limiter.ex | 170 | ✅ Acceptable |
| usage_patterns.ex | 150 | ✅ Good (examples) |
| config.ex | 132 | ✅ Good |
| message_handler.ex | 125 | ✅ Good |
| deribit_adapter.ex | 124 | ⚠️ Business logic (migrate out) |
| client_supervisor.ex | 122 | ✅ Good |
| connection_registry.ex | 84 | ✅ Good |
| json_rpc.ex | 81 | ✅ Excellent |
| error_handler.ex | 70 | ✅ Good |
| frame.ex | 61 | ✅ Excellent |
| debug.ex | 31 | ✅ Excellent |

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

### Task R001: Extract HeartbeatManager `[P]`

**[D:4/B:8 → Priority:2.0]** 🎯

Extract heartbeat logic from Client.ex into dedicated module.

**Current location:** `client.ex` lines ~450-550 (heartbeat handling)

**Success criteria:**
- [ ] New `ZenWebsocket.HeartbeatManager` module created
- [ ] Handles platform-specific heartbeat sending (Deribit, generic, none)
- [ ] Tracks heartbeat state (last_sent, interval, type)
- [ ] Client delegates heartbeat operations to new module
- [ ] All existing heartbeat tests pass
- [ ] Module under 100 lines

**Files to create:**
- `lib/zen_websocket/heartbeat_manager.ex`

**Tests:**
- Unit tests for heartbeat interval calculation
- Integration tests for Deribit heartbeat flow

---

### Task R002: Extract SubscriptionManager `[P]`

**[D:4/B:7 → Priority:1.75]** 🚀

Extract subscription tracking from Client.ex into dedicated module.

**Current location:** `client.ex` (subscription state, restore logic)

**Success criteria:**
- [ ] New `ZenWebsocket.SubscriptionManager` module created
- [ ] Tracks active subscriptions per client
- [ ] Handles subscription restoration after reconnect
- [ ] Clean API: `add/2`, `remove/2`, `list/1`, `restore/2`
- [ ] All existing subscription tests pass
- [ ] Module under 80 lines

**Files to create:**
- `lib/zen_websocket/subscription_manager.ex`

---

### Task R003: Extract RequestCorrelator `[P]`

**[D:5/B:7 → Priority:1.4]** 🚀

Extract JSON-RPC request/response correlation from Client.ex.

**Current location:** `client.ex` (pending_requests map, timeout handling)

**Success criteria:**
- [ ] New `ZenWebsocket.RequestCorrelator` module created
- [ ] Tracks pending requests with timeouts
- [ ] Matches responses to requests by ID
- [ ] Cleans up timed-out requests properly
- [ ] API: `track/3`, `resolve/2`, `timeout/2`, `pending/1`
- [ ] All JSON-RPC correlation tests pass
- [ ] Module under 100 lines

**Files to create:**
- `lib/zen_websocket/request_correlator.ex`

---

### Task R004: Slim Down Client.ex

**[D:6/B:9 → Priority:1.5]** 🚀

After extracting R001-R003, refactor Client.ex to delegate to new modules.

**Success criteria:**
- [ ] Client.ex under 300 lines (from 862)
- [ ] Client focuses only on: connection lifecycle, message routing, public API
- [ ] All extracted concerns delegated to specialized modules
- [ ] No functionality changes - all tests pass
- [ ] Maintains backward-compatible public API

**Depends on:** R001, R002, R003

---

## Phase 3: Memory Safety [D:4/B:8 → Priority:2.0] 🎯

> Fix potential resource leaks.

### Task R005: RateLimiter ETS Cleanup

**[D:3/B:8 → Priority:2.7]** 🎯

Add proper ETS table cleanup to prevent memory leaks.

**Current issues:**
- ETS tables persist if process crashes
- No cleanup mechanism on termination
- Queue limit (100) is hardcoded

**Success criteria:**
- [ ] Implement `terminate/2` callback for ETS cleanup
- [ ] Add configurable queue limit
- [ ] Add telemetry for queue depth monitoring
- [ ] Test cleanup on process crash
- [ ] Document memory characteristics

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

### Task R007: Fix Credo Warnings `[P]`

**[D:2/B:5 → Priority:2.5]** 🎯

Address the 6 Credo warnings in test files.

**Current warnings:**
- 4x `length/1` usage (expensive, use pattern matching)
- Located in: `supervised_connection_test.exs`, `supervised_client_test.exs`, `subscription_management_test.exs`

**Success criteria:**
- [ ] Replace `length(list) == 0` with `list == []`
- [ ] Replace `length(list) > 0` with pattern match `[_ | _]`
- [ ] Credo strict passes with 0 warnings
- [ ] All tests still pass

---

### Task R008: Replace Magic Numbers `[P]`

**[D:2/B:4 → Priority:2.0]** 🎯

Replace hardcoded constants with named module attributes.

**Current issues:**
- `timeout + 100` - unexplained adjustment
- `max(timeout, 1000)` - minimum timeout not documented
- Various millisecond values without explanation

**Success criteria:**
- [ ] All timeout adjustments use named constants
- [ ] Each constant has documentation comment
- [ ] No unexplained numeric literals in core modules

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
| R005: RateLimiter ETS Cleanup | 🎯 2.7 | D:3 | ⬜ Pending |
| R007: Fix Credo Warnings | 🎯 2.5 | D:2 | ⬜ Pending |
| R008: Replace Magic Numbers | 🎯 2.0 | D:2 | ⬜ Pending |
| R001: Extract HeartbeatManager | 🎯 2.0 | D:4 | ⬜ Pending |

### Short-term (v0.2.0)

| Task | Priority | Effort |
|------|----------|--------|
| R002: Extract SubscriptionManager | 🚀 1.75 | D:4 |
| R012: Building Adapters Guide | 🚀 1.7 | D:3 |
| R003: Extract RequestCorrelator | 🚀 1.4 | D:5 |
| R004: Slim Down Client.ex | 🚀 1.5 | D:6 |
| R009: Standardize Debug Logging | 🚀 1.5 | D:2 |

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
R001, R002, R003 [P] - Extract modules (independent extractions)
R007, R008, R009 [P] - Code quality fixes (independent)
R012, R013 [P] - Documentation (independent)
```

**Coordination rule:** Update status to 🔄 with branch name before starting.

---

## Success Metrics

### Post-Refactor Targets

| Metric | Current | Target |
|--------|---------|--------|
| Client.ex LOC | 862 | <300 |
| Largest module | 862 | <200 |
| Credo warnings | 6 | 0 |
| Property tests | 0 | 10+ |
| Dialyzer skips | 14 | <10 |

### Quality Gates (must pass before each release)

```bash
mix test.json --quiet --summary-only  # All tests pass
mix dialyzer                          # No new warnings
mix credo --strict                    # Score ≥8.0
mix doctor                            # 100% moduledoc coverage
```

---

## Architectural Decisions

### Why Split Client.ex?

The 862-line Client module handles:
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

`deribit_rpc.ex` (237 lines) and similar files are:
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
2. **Client.ex is the main target** - 862 lines doing 5+ jobs
3. **WNX0026 (hex.pm) should complete first** - Don't refactor during publish prep
4. **Business logic migration depends on market_maker** - External dependency
5. **Real API testing is non-negotiable** - Project principle, don't add mocks

The project has excellent documentation. Read:
- `CLAUDE.md` for project principles
- `docs/TaskList.md` for existing task tracking
- `docs/Architecture.md` for system design
