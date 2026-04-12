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
| R011 | ⬜ | [D:4/B:5/U:3 → Eff:1.0] | Error scenario testing |
| R010 | ⬜ | [D:5/B:6/U:2 → Eff:0.8] | Property-based testing |

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
- [ ] Each error category has explicit test
- [ ] Recovery paths verified
- [ ] Error messages are clear and actionable

**Docs:** Update all affected `.md` files (README, CLAUDE.md, ROADMAP, CHANGELOG, AGENTS, CONTRIBUTING) before marking complete.

---

### Task R010: Property-Based Testing

**[D:5/B:6/U:2 → Eff:0.8]**

Implement property-based tests using stream_data (already installed but unused).

**Target areas:** Frame encoding/decoding (round-trip properties), Config validation (valid configs always pass, invalid always fail), message routing (pattern matching completeness).

**Success criteria:**
- [ ] Property tests for Frame module
- [ ] Property tests for Config validation
- [ ] At least 3 property-based test files

**Docs:** Update all affected `.md` files (README, CLAUDE.md, ROADMAP, CHANGELOG, AGENTS, CONTRIBUTING) before marking complete.

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
