# ZenWebsocket Roadmap

**Status:** Production-ready, v0.3.1 published on hex.pm
**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks (search by task ID: R001, R017, etc.).

---

## 🎯 Current Focus

**Post v0.3.1: Bug Fixes & Testing**

> **Philosophy reminder:** Maximum 5 functions per module, 15 lines per function, direct Gun API usage, real API testing only.

### ✅ Recently Completed
| Task | Description | Notes |
|------|-------------|-------|
| R027 | Nil-client guards on adapter | `subscribe/2`, `unsubscribe/2`, `authenticate/1`, `send_request/3` return `{:error, :not_connected}` |
| R028 | BatchSubscriptionManager error handling | Marks request as failed and stops on subscribe error; handler doc fix |

### 📋 Remaining Tasks
| Order | Task | Priority | What It Does | Status |
|-------|------|----------|--------------|--------|
| - | **R010**: Property-Based Testing | 📋 1.2 | stream_data tests | ⬜ Pending |
| - | **R011**: Error Scenario Testing | 📋 1.25 | Edge case tests | ⬜ Pending |
| - | **R025**: Deployment Guide | 📋 1.7 | Trading deployment docs | ⬜ Pending |

### Quick Commands
```bash
mix check                    # All quality checks
mix test.json --quiet --summary-only  # Test health
mix dialyzer                 # Type checking
mix credo --strict           # Static analysis
mix hex.publish --dry-run    # Verify before publishing
```

---

## Completed Phases

> Task details in [CHANGELOG.md](CHANGELOG.md) under [0.2.0] section.

| Phase | Description | Tasks |
|-------|-------------|-------|
| Phase 1 | Pre-Refactor (Hex publishing, guidelines) | 2 |
| Phase 2 | Critical Refactoring (Client.ex split) | 4 |
| Phase 3 | Memory Safety (ETS cleanup, monitors) | 2 |
| Phase 4 | Code Quality (Credo, magic numbers, logging) | 3 |
| Phase 9 | Test Coverage Infrastructure | 4 |
| v0.2.0 | User Experience (latency, errors, backpressure) | 7 |
| v0.3.0 | Developer Experience (recording, testing, docs, pool) | 4 |
| Post-v0.3.1 | Bug fixes (R027 nil-client guard, R028 batch error handling) | 2 |

---

## Active Tasks

### Task R020: Test Helpers Module ✅

**[D:4/B:6 → Priority:1.5]** 🚀 — **Complete**

Create consumer-facing test utilities building on MockWebSockServer.

**Builds on:** MockWebSockServer exists in `test/support/` but isn't exposed to consumers.

**Success criteria:**
- [x] `ZenWebsocket.Testing` module with public helpers
- [x] `start_mock_server/1` - simplified server startup
- [x] `simulate_disconnect/2` - trigger disconnect scenarios
- [x] `assert_message_sent/3` - verify client sent expected message
- [x] `inject_message/2` - send message from server to client
- [x] Helpers work with ExUnit (setup/on_exit integration)
- [x] Documentation with usage examples

---

### Task R019: Session Recording ✅

**[D:5/B:7 → Priority:1.4]** 🚀 — **Complete**

Add optional message recording for debugging and testing.

**Builds on:** Client already routes all messages through `route_data_frame/2`.

**Success criteria:**
- [x] Config option `record_to: path` enables recording
- [x] Records: timestamps, direction (in/out), raw frames, parsed messages
- [x] JSONL format (one JSON object per line) for streaming writes
- [x] `ZenWebsocket.Recorder.replay/2` plays back to a handler module
- [x] Recording has minimal performance impact (<1ms overhead per message)
- [x] Integration test with real connection recording/replay

---

### Task R023: Rewrite USAGE_RULES.md and Add AGENTS.md ✅

**[D:2/B:5 → Priority:2.5]** 🎯 — **Complete**

Modernize AI agent documentation files to follow current conventions.

**Approach:** Use CHANGELOG.md as source of truth for feature coverage.

**USAGE_RULES.md rewrite:**
- Audit CHANGELOG.md for features missing from current docs
- Update to match current API (latency stats, backpressure, etc.)
- Add new telemetry events from R017/R021
- Document ErrorHandler.explain/1 usage patterns
- Document LatencyStats.summary/1 and RateLimiter.status/1

**AGENTS.md (new file):**
- AI coding agent guidance for contributing to zen_websocket
- Document module limits (5 functions, 15 lines)
- Explain real API testing requirement
- Link to roadmap for task coordination

**Success criteria:**
- [x] CHANGELOG.md audited for undocumented features
- [x] USAGE_RULES.md updated with v0.2.0 features
- [x] AGENTS.md created with contributor guidance
- [x] Both files follow hex.pm conventions
- [x] Cross-referenced from README.md

---

## Backlog

### Phase 5: Testing Enhancements

#### Task R010: Property-Based Testing

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

#### Task R011: Error Scenario Testing

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

### Phase 8: User Experience (Continued)

#### Task R022: Connection Pool Load Balancing ✅

**[D:6/B:6 → Priority:1.0]** 📋 — **Complete**

Add load balancing to existing ClientSupervisor infrastructure.

**Builds on:** ClientSupervisor + ConnectionRegistry already manage multiple clients.

**Depends on:** R017 (latency metrics needed for health scoring) ✅ Complete

**Success criteria:**
- [x] `ClientSupervisor.send_balanced/2` routes to healthiest connection
- [x] Health score based on: pending requests, latency, error rate
- [x] Round-robin fallback when all connections have equal health
- [x] Automatic failover when connection dies
- [x] Telemetry for pool utilization metrics
- [x] Integration tests with multiple connections

---

## Future / Deferred

Tasks blocked on external dependencies or deferred for later consideration.

### Task R014: Migrate Deribit Examples to market_maker

**[D:4/B:6 → Priority:1.5]** — **Deferred**

~~Move Deribit-specific business logic to market_maker project (per WNX0028 analysis).~~

**Deferred:** R026 attempted moving examples to a separate mix project but was reverted — the ergonomic cost (broken Tidewave, broken .iex.exs, stale doc references) outweighed the architectural benefit. Examples stay in `lib/zen_websocket/examples/`.

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

**Revisit when:** market_maker project has core infrastructure in place.

---

### Task R024: Custom Client Discovery Hooks

**[D:4/B:6 → Priority:1.5]** 📋 — **Future**

Add hooks for applications to integrate their own client discovery/registry.

**Philosophy:** Clustering is application concern, not library concern. The library should provide hooks, not mandate solutions.

**Current state:** `ClientSupervisor.list_clients/0` only discovers local children. This is correct for a library - applications own distribution.

**Goal:** Enable applications to plug in custom registries (pg, Horde, :global, etc.) without library changes.

**Proposed API:**
```elixir
# Option 1: Discovery function
ClientSupervisor.send_balanced(msg, client_discovery: fn -> MyRegistry.list_ws_clients() end)

# Option 2: Callbacks for registration
ClientSupervisor.start_client(url,
  on_connect: fn pid -> :pg.join(:ws_pool, pid) end,
  on_disconnect: fn pid -> :pg.leave(:ws_pool, pid) end
)
```

**Success criteria:**
- [ ] `send_balanced/2` accepts optional `client_discovery` function
- [ ] Optional `on_connect`/`on_disconnect` callbacks in `start_client/2`
- [ ] Default behavior unchanged (local discovery)
- [ ] Documentation with pg/Horde integration examples
- [ ] Tests with custom discovery function

**Implementation notes:**
- Keep changes minimal - just hooks, no clustering logic
- Applications bring their own registry
- Health checks already work with remote PIDs (GenServer.call)

---

### Task R025: Deployment Guide for Trading Applications

**[D:3/B:5 → Priority:1.7]** 📋 — **Future**

Add deployment considerations guide for trading applications using zen_websocket.

**Scope:** Educational documentation, not prescriptive. Help users make informed decisions.

**Topics to cover:**
- **Latency considerations**
  - Geographic proximity to exchanges matters for HFT
  - Common exchange locations (Tokyo, Frankfurt, Chicago, Singapore, London)
  - Co-location vs cloud trade-offs

- **Cloud provider regions**
  - AWS regions near major exchanges
  - Fly.io edge locations
  - When cloud latency is "good enough" (non-HFT strategies)

- **Connection architecture**
  - Single node vs distributed
  - When to use connection pools
  - Failover patterns

- **Monitoring in production**
  - Telemetry events to watch
  - Latency percentiles that matter
  - Alert thresholds

**Success criteria:**
- [ ] `docs/guides/deployment_considerations.md` created
- [ ] Covers latency, geography, architecture trade-offs
- [ ] Includes "questions to ask yourself" framework
- [ ] Links to exchange-specific latency data where available
- [ ] Not prescriptive - helps users decide based on their use case

**Implementation notes:**
- This is guidance, not the library's responsibility
- Focus on "things to consider" not "do this"
- Acknowledge different strategies have different needs

---

### ~~Task R026: Create Deribit Example Project~~ — **Abandoned**

Attempted moving Deribit adapters to `examples/deribit/` as a separate mix project. Reverted because the ergonomic cost was too high: broken Tidewave access, broken `.iex.exs` aliases, 13+ stale doc references, and interactive debugging required a second IEx session. Examples stay in `lib/zen_websocket/examples/`.

---

## Parallel Work Opportunities

These tasks can be worked on simultaneously:

```
v0.3.0 Complete:
R019 ✅ - Session Recording (Client)
R020 ✅ - Test Helpers Module (test support)
R023 ✅ - USAGE_RULES.md + AGENTS.md (documentation)
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

The original Client module handled too many concerns (connection lifecycle, message routing, heartbeat, subscriptions, correlation, state). This violated "max 5 functions per module" and Single Responsibility Principle.

**Result:** Extracted HeartbeatManager, SubscriptionManager, RequestCorrelator. Client.ex reduced from 870 to ~200 lines.

### Example Code Policy

**Non-negotiable workflow:** All examples must be written and tested in `lib/` and `test/` first with full validation.

**All examples live in `lib/zen_websocket/examples/`.** R026 attempted moving large examples to separate mix projects but was reverted — the ergonomic cost (broken Tidewave, broken .iex.exs, stale doc references) outweighed the benefit.

---

## Notes for Future Claude Instances

Key context for picking up this roadmap:

1. **The library works well** - This is improvement, not emergency repair
2. **v0.3.1 is published** - Pool routing, session recording, test helpers, docs rewrite
3. **R026 was abandoned** - Moving examples to separate mix projects caused too many problems. Examples stay in `lib/zen_websocket/examples/`
4. **Real API testing is non-negotiable** - Project principle, don't add mocks
5. **Example code policy** - All examples live in `lib/zen_websocket/examples/`

**What was implemented for v0.3.0:**
- R019 (Recording) → `ZenWebsocket.Recorder` + `RecorderServer`, hooks in Client.ex
- R020 (Test Helpers) → `ZenWebsocket.Testing` exposes MockWebSockServer to consumers
- R023 (Docs) → Updated USAGE_RULES.md with new features, created AGENTS.md for AI agents
- R022 (Pool) → `ZenWebsocket.PoolRouter` + `ClientSupervisor.send_balanced/2` for health-based routing

The project has excellent documentation. Read:
- `CLAUDE.md` for project principles
- `docs/Architecture.md` for system design
- `CHANGELOG.md` for what's been done
