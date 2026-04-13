# ZenWebsocket Roadmap

**Vision:** Production-grade WebSocket client library for Elixir, designed for financial APIs.

**Status:** v0.4.0 prepared for hex.pm (v0.3.1 currently published)

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## Current Focus

**Post-v0.4.0: Remaining Tasks**

> **Philosophy reminder:** Trust working quality gates, fail gracefully on dead connections, and preserve caller configuration across reconnects.

### Recently Completed
| Task | Description | Notes |
|------|-------------|-------|
| R010 | Property-based testing (Frame, Config, JsonRpc) | See CHANGELOG [Unreleased] |
| R042 | Fail pending requests on disconnect | See CHANGELOG [Unreleased] |
| R025 | Deployment guide for trading apps | See CHANGELOG [Unreleased] |
| R030 | Preserve config across reconnect | See CHANGELOG [Unreleased] |
| R041 | Doc review (USAGE_RULES.md, guides, examples) | See CHANGELOG v0.4.0 |
| R040 | Wire in descripex to public modules | See CHANGELOG v0.4.0 |
| R029 | Fail gracefully on stale client PIDs | See CHANGELOG v0.4.0 |
| R038 | Subscription messages forwarded to handler | See CHANGELOG v0.4.0 |
| R039 | Protocol errors forwarded to handler | See CHANGELOG v0.4.0 |
| R035 | Fix double callback delivery | See CHANGELOG v0.4.0 |
| R024 | Custom client discovery hooks | See CHANGELOG v0.4.0 |
| R036 | Strengthen reconnection test | See CHANGELOG v0.4.0 |
| R037 | Strengthen subscribe test | See CHANGELOG v0.4.0 |
| R033 | Reconnection regression coverage | See CHANGELOG v0.4.0 |
| R031 | Preserve query params on upgrade | See CHANGELOG v0.4.0 |
| R034 | Refresh top-level API docs | See CHANGELOG v0.4.0 |
| R027 | Nil-client guards on adapter | See CHANGELOG v0.4.0 |
| R028 | BatchSubscriptionManager error handling | See CHANGELOG v0.4.0 |

### Current Tasks
| Task | Status | Priority | Description |
|------|--------|----------|-------------|
| R040 | ✅ | [D:3/B:7/U:7 → Eff:2.33] | Wire in descripex to public modules |
| R041 | ✅ | [D:3/B:7/U:6 → Eff:2.17] | Doc review (USAGE_RULES.md, guides, examples) |
| R025 | ✅ | [D:3/B:5/U:5 → Eff:1.67] | Deployment guide for trading apps |
| R030 | ✅ | [D:5/B:8/U:6 → Eff:1.4] | Preserve config across reconnect |
| R011 | ✅ | [D:4/B:5/U:3 → Eff:1.0] | Error scenario testing |
| R042 | ✅ | [D:4/B:7/U:6 → Eff:1.63] | Fail pending requests on disconnect |
| R043 | ⬜ | [D:3/B:5/U:4 → Eff:1.5] | Reject duplicate live request IDs |
| R010 | ✅ | [D:5/B:6/U:2 → Eff:0.8] | Property-based testing |
| R044 | ⬜ | [D:1/B:4/U:5 → Eff:4.5] 🎯 | Amend testing policy: allow transport shape fixtures |
| R045 | ⬜ | [D:3/B:5/U:4 → Eff:1.5] | GunStub test helper (blocked by R044) |
| R046 | ⬜ | [D:2/B:4/U:3 → Eff:1.75] | MessageHandler property tests (blocked by R045) |

### Quick Commands
```bash
mix test.json                                  # Tests (with logs/warnings)
mix test.json --quiet --failed --first-failure # Iterate on failures
mix dialyzer.json --quiet --summary-only       # Dialyzer health
mix credo --strict --format json               # Static analysis
mix security                                   # Sobelow
mix docs                                       # Local docs build
```

---

## Completed Phases

> Task details in [CHANGELOG.md](CHANGELOG.md).

| Phase | Description | Tasks |
|-------|-------------|-------|
| Phase 1 | Pre-Refactor (Hex publishing, guidelines) | 2 |
| Phase 2 | Critical Refactoring (Client.ex split) | 4 |
| Phase 3 | Memory Safety (ETS cleanup, monitors) | 2 |
| Phase 4 | Code Quality (Credo, magic numbers, logging) | 3 |
| Phase 9 | Test Coverage Infrastructure | 4 |
| v0.2.0 | User Experience (latency, errors, backpressure) | 7 |
| v0.3.0 | Developer Experience (recording, testing, docs, pool) | 4 |
| v0.4.0 | Correctness, stability, descripex, doc review (R024-R041) | 16 |

---

## Backlog

### Task R029: Fail Gracefully on Stale Client PIDs ✅

**[D:4/B:9/U:8 → Eff:2.13]** — **Complete**

Make stale or dead client references safe. Public API calls should return normal
error tuples instead of exiting the caller when a stored `server_pid` is no
longer alive.

**Success criteria:**
- [x] `Client.send_message/2` does not exit on a dead `server_pid`
- [x] `ClientSupervisor.send_balanced/2` handles dead PIDs from custom discovery and racey shutdowns
- [x] Load balancing skips or fails over dead candidates instead of crashing the caller
- [x] Regression tests cover stale client structs and dead PIDs returned by `client_discovery`

---

### Task R040: Wire in Descripex to Public Modules ✅

**[D:3/B:7/U:7 → Eff:2.33]** — **Complete**

Add `use Descripex` to all public-facing modules so the library is self-describing. This enables JSON Schema generation, MCP tool discovery, and progressive disclosure via `describe/0-2`.

**Success criteria:**
- [x] `use Descripex` added to public modules (Client, Config, Recorder, Testing, ClientSupervisor, PoolRouter, etc.)
- [x] `api()` macro configured with function descriptions for each module
- [x] `ZenWebsocket.describe/0` returns library-level overview
- [x] `mix docs` still builds cleanly
- [x] Dialyzer and Credo pass

**Docs:** Update all affected `.md` files (README, CLAUDE.md, ROADMAP, CHANGELOG, AGENTS, CONTRIBUTING) before marking complete.

---

### Task R041: Doc Review (USAGE_RULES.md, Guides, Examples) ✅

**[D:3/B:7/U:6 → Eff:2.17]** — **Complete**

Audit all documentation files for accuracy against current codebase. The codebase has evolved significantly since docs were last updated — stale API references, removed aliases, and outdated examples need cleanup.

**Scope:**
- `USAGE_RULES.md` — verify all code examples compile, API signatures match current code, telemetry events are current
- `docs/guides/*.md` — verify building_adapters, performance_tuning, troubleshooting_reconnection are accurate
- `docs/Architecture.md` — verify module list and descriptions match reality
- `AGENTS.md` — verify module overview table, example code snippets
- Example code in `lib/zen_websocket/examples/` — verify compiles and matches documented patterns

**Success criteria:**
- [x] All code examples in docs compile against current codebase
- [x] No references to removed APIs, aliases, or modules
- [x] Telemetry event table matches actual emitted events
- [x] Module overview tables match actual public functions

**Docs:** Update all affected `.md` files (README, CLAUDE.md, ROADMAP, CHANGELOG, AGENTS, CONTRIBUTING) before marking complete.

---

### Task R030: Preserve Config Across Reconnect ✅

**[D:5/B:8/U:6 → Eff:1.4]** — **Complete**

Reconnect should preserve the connection contract the caller originally set up.
Implemented for both automatic reconnect and explicit `Client.reconnect/1`.

**Success criteria:**
- [x] Reconnect keeps validated config fields such as timeout, headers, retry config, request timeout, and recording path
- [x] Reconnect behavior for heartbeat and handler options is either preserved or explicitly documented if unsupported
- [x] Regression tests verify reconnect keeps the intended runtime contract

---

### Task R025: Deployment Guide for Trading Applications ✅

**[D:3/B:5/U:5 → Eff:1.67]** — **Complete**

Add deployment considerations guide for trading applications using zen_websocket.
Educational documentation, not prescriptive.

**Topics:** Latency considerations, cloud provider regions, connection architecture, monitoring in production.

**Success criteria:**
- [x] `docs/guides/deployment_considerations.md` created
- [x] Covers latency, geography, architecture trade-offs
- [x] Includes "questions to ask yourself" framework
- [x] Not prescriptive — helps users decide based on their use case

**Docs:** Update all affected `.md` files (README, CLAUDE.md, ROADMAP, CHANGELOG, AGENTS, CONTRIBUTING) before marking complete.

---

### Task R011: Error Scenario Testing

**[D:4/B:5/U:3 → Eff:1.0]**

Add tests for edge cases and error scenarios.

**Target areas:** Gun error types not currently tested, frame corruption handling, correlation timeout cleanup, rate limit recovery.

**Success criteria:**
- [x] Each error category has explicit test
- [x] Recovery paths verified
- [x] Error messages are clear and actionable

**Completed:** Added `describe "Gun error variants"` (error_handler_test.exs), `describe "decode/1 malformed input"` (frame_test.exs), `describe "concurrent timeout cleanup"` (request_correlator_test.exs), `describe "recovery scenarios"` (rate_limiter_test.exs). Deferred client-level reconnect/pending-cleanup integration test — see [CHANGELOG.md](CHANGELOG.md) for discovered-work note.

---

### Task R042: Fail pending requests on disconnect ✅

**[D:4/B:7/U:6 → Eff:1.63]** — **Complete** (discovered during R011)

**Scope: automatic Gun disconnect/reconnect only.** The explicit `Client.reconnect/1` path (`client.ex:433`) stops the old GenServer, so blocked `GenServer.call` receivers fail immediately via caller-side `:exit` around `client.ex:452` rather than hanging. If that path is later shown to leak pending callers, expand this task.

On the automatic path, `pending_requests` (initialized empty at `client.ex:546`) is never cleared when Gun reports the connection down (`client.ex:943`). Callers blocked on `GenServer.call` for a correlated response hang until their per-call timeout fires — the socket is gone and the response will never arrive.

**Expected behavior:** On automatic Gun disconnect, drain `pending_requests`, reply `{:error, :disconnected}` to each `from`, and ensure stale timeout messages from the disconnected request cannot time out a reused ID after reconnect.

**Success criteria:**
- [x] On automatic Gun disconnect, every pending caller receives a prompt `{:error, :disconnected}` reply (not a later timeout)
- [x] Reused request IDs after reconnect are not failed by stale timeout messages from the disconnected request
- [x] Integration test in `test/zen_websocket/client_test.exs` using `MockWebSockServer` covers the full path

---

### Task R043: Reject duplicate live request IDs

**[D:3/B:5/U:4 → Eff:1.5]** — surfaced during R042 review

`RequestCorrelator.track/4` uses `Map.put/3` on `state.pending_requests`, so tracking a request whose ID matches an already-pending entry silently overwrites the earlier caller — the first caller never gets a reply and its timeout timer is orphaned. R042 fixed stale timers across reconnect; this covers duplicate IDs within a single live connection.

**Expected behavior:** Detect the collision at track time and either (a) return an error tuple to the caller without overwriting, or (b) refuse the second tracking and leave the existing entry intact. Pick whichever aligns with how the client surfaces the result to `send_message` callers.

**Success criteria:**
- [ ] Tracking an ID already present in `pending_requests` does not overwrite the existing entry
- [ ] The second caller receives a deterministic error (not a silent hang)
- [ ] The first caller's timer and `from` are preserved
- [ ] Unit test in `request_correlator_test.exs` covers the collision path

---

### Task R010: Property-Based Testing ✅

**[D:5/B:6/U:2 → Eff:0.8]** — **Complete**

Added property-based tests using stream_data for Frame, Config, and JsonRpc.

**Success criteria:**
- [x] Property tests for Frame module
- [x] Property tests for Config validation
- [x] At least 3 property-based test files (Frame, Config, JsonRpc)

**Deferred:** MessageHandler property tests require Gun transport shape fixtures — tracked as R044/R045/R046 below.

---

### Task R044: Amend Testing Policy for Transport Shape Fixtures

**[D:1/B:4/U:5 → Eff:4.5]** 🎯 — surfaced during R010 planning

The current "NO MOCKS ALLOWED" policy blocks property-testing pure-logic modules that consume Gun messages (MessageHandler in particular), because Gun's `pid` and `stream_ref` are opaque BEAM primitives — there's no real behavior for a fixture to drift against.

**Expected outcome:** Amend CLAUDE.md and AGENTS.md testing policy to add a narrow exception: test doubles are permitted for **opaque transport message shapes only** (Gun `:gun_upgrade` / `:gun_ws` / `:gun_down` / `:gun_error` tuples). All other mocking (API responses, auth flows, exchange behavior) remains prohibited; real-API and `MockWebSockServer` coverage stays the source of truth for business logic.

**Success criteria:**
- [ ] CLAUDE.md testing section documents the narrow exception with rationale and boundaries
- [ ] AGENTS.md mirrors or references the updated policy
- [ ] Policy change is explicit about what is NOT newly allowed (prevents future drift)

---

### Task R045: Add GunStub Test Helper

**[D:3/B:5/U:4 → Eff:1.5]** — blocked by R044

Add a minimal test helper that constructs Gun transport message tuples (`:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`) for unit-level routing tests. Scope strictly bounded per R044 — shape-only, no behavior simulation.

**Success criteria:**
- [ ] `GunStub` module in `test/support/` exposes constructors for each Gun message shape
- [ ] Uses real pids (from `self()` or `spawn`) and real refs (from `make_ref/0`) — no fake opaque values
- [ ] `@moduledoc` explicitly scopes the helper to transport shapes per R044
- [ ] At least one existing unit test adopts it to prove the helper is useful

---

### Task R046: MessageHandler Property Tests

**[D:2/B:4/U:3 → Eff:1.75]** — blocked by R045

Add property-based tests for `MessageHandler.handle_message/2` using `GunStub`. Targets routing totality (unknown shapes never raise), error classification, and frame-type dispatch determinism.

**Success criteria:**
- [ ] Property: arbitrary non-Gun tuples return `{:ok, {:unknown_message, _}}` without raising
- [ ] Property: `{:gun_down, pid, _, reason, _}` always returns `{:ok, {:connection_down, pid, reason}}` regardless of reason term
- [ ] Property: text/binary frames route through the handler callback
- [ ] Uses `GunStub` from R045 rather than hand-constructed tuples

---

## Future / Deferred

### Task R024: Custom Client Discovery Hooks ✅

**[D:4/B:7/U:7 → Eff:1.75]** — **Complete**

Enable applications to plug in custom registries (pg, Horde, :global, etc.) for `send_balanced/2` client discovery without library changes.

**Success criteria:**
- [x] `send_balanced/2` accepts optional `client_discovery` function
- [x] Optional `on_connect`/`on_disconnect` callbacks in `start_client/2`
- [x] Default behavior unchanged (local discovery)
- [x] Documentation with pg/Horde integration examples

---

### ~~Task R014: Migrate Deribit Examples to market_maker~~ — **Deferred**

Deferred: R026 attempted moving examples to a separate mix project but was reverted. Examples stay in `lib/zen_websocket/examples/`. Revisit when market_maker project has core infrastructure in place.

---

### ~~Task R026: Create Deribit Example Project~~ — **Abandoned**

Reverted — ergonomic cost too high (broken Tidewave, broken `.iex.exs`, 13+ stale doc references).

---

## Quality Gates

```bash
mix test.json --quiet --summary-only           # All tests pass
mix dialyzer.json --quiet --summary-only       # No new warnings
mix credo --strict --format json               # Clean static analysis
mix doctor                                     # 100% moduledoc coverage
```

---

## Architectural Decisions

### Why Split Client.ex?

Original Client handled too many concerns. Extracted HeartbeatManager, SubscriptionManager, RequestCorrelator. Client.ex reduced from 870 to ~200 lines.

### Example Code Policy

All examples live in `lib/zen_websocket/examples/`. R026 attempted separate mix projects but was reverted.

---

## Notes for Future Claude Instances

1. **v0.4.0 prepared** — Includes all R024-R041 work: custom discovery hooks, stale PID safety, handler contract change, descripex integration, full doc review. Handler callback now delivers decoded maps for JSON frames (breaking change from v0.3.x)
2. **v0.3.1 was the last published version** — Pool routing, session recording, test helpers, docs rewrite
3. **R026 was abandoned** — Moving examples to separate mix projects caused too many problems
4. **Real API testing is non-negotiable** — Project principle, don't add mocks
5. **Quality aliases removed** — No `mix lint/check/typecheck/coverage/rebuild`. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly
6. **Every task updates docs** — A task without updated `.md` files is incomplete
7. **Client has 9+ public functions** — Not "only 5". Core: connect, send_message, subscribe, get_state, close. Monitoring: get_latency_stats, get_heartbeat_health, get_state_metrics, reconnect
