# ZenWebsocket Roadmap

**Vision:** Production-grade WebSocket client library for Elixir, designed for financial APIs.

**Status:** v0.4.2 preparing for hex.pm (v0.4.1 currently published)

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## Current Focus

**Post-v0.4.0: Remaining Tasks**

> **Philosophy reminder:** Trust working quality gates, fail gracefully on dead connections, and preserve caller configuration across reconnects.

### Recently Completed
| Task | Description | Notes |
|------|-------------|-------|
| R046 | MessageHandler property tests via GunStub | See CHANGELOG [Unreleased] |
| R045 | GunStub test helper (R044-fenced transport shapes) | See CHANGELOG [Unreleased] |
| R048 | Retire unreachable `:frame` / `:frame_error` handler shapes | See CHANGELOG [Unreleased] |
| R047 | Document handler message shapes | See CHANGELOG [Unreleased] |
| R044 | Amend testing policy: allow transport shape fixtures | See CHANGELOG [Unreleased] |
| R010 | Property-based testing (Frame, Config, JsonRpc) | See CHANGELOG [Unreleased] |
| R043 | Reject duplicate live request IDs | See CHANGELOG [Unreleased] |
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
_No pending tasks — backlog open._

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

_Open — no pending tasks. Add new entries here with D/B/U scoring._

---

## Future / Deferred

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
4. **Real API testing is non-negotiable** — Project principle. One narrow exception (R044): opaque Gun transport message-shape fixtures. See CLAUDE.md → Real API Testing Policy → Narrow exception
5. **Quality aliases removed** — No `mix lint/check/typecheck/coverage/rebuild`. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly
6. **Every task updates docs** — A task without updated `.md` files is incomplete
7. **Client has 9+ public functions** — Not "only 5". Core: connect, send_message, subscribe, get_state, close. Monitoring: get_latency_stats, get_heartbeat_health, get_state_metrics, reconnect
