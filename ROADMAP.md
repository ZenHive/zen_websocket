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
| Task | Status | Priority | Description |
|------|--------|----------|-------------|
| R048 | ⬜ | [D:3/B:4/U:4 → Eff:1.33] | Resolve unreachable `:frame` / `:frame_error` handler paths |
| R046 | ⬜ | [D:2/B:4/U:3 → Eff:1.75] | MessageHandler property tests (blocked by R045) |
| R045 | ⬜ | [D:3/B:5/U:4 → Eff:1.5] | GunStub test helper |

**R048 — Resolve unreachable `:frame` / `:frame_error` handler paths**

Discovered during R047: two handler message shapes documented in `t:ZenWebsocket.Client.handler_message/0` are currently unreachable.

- `{:frame, _}` at `client.ex:1092–1098` — `route_data_frame/2` routes `other ->` to the handler, but `MessageHandler.handle_control_frame/3` already consumes every non-text/non-binary Frame.decode output (ping/pong/close all return `:handled`), so the catch-all never fires.
- `{:frame_error, {:decode_error, _}}` at `client.ex:1125–1134` — `handle_frame_error/2` accepts `{:decode_error, _}` but `MessageHandler.decode_and_handle_control/1` only produces that tag when `ErrorHandler.handle_error/1` returns non-`:stop`. `ErrorHandler.check_fatal/1` classifies every `{:bad_frame, _}` as `:fatal` → `:stop`, so the `:decode_error` branch is dead.

Both paths carry `TODO(Task R048):` markers in `client.ex`.

**Decide and implement one of:**
1. Retire the dead shapes: remove the two `state.handler.({:frame, _})` / `({:frame_error, _})` call sites, drop them from `@type handler_message`, remove the corresponding default-handler clauses and their USAGE_RULES rows.
2. Expand reachability: add the missing path(s) — e.g., admit some `{:bad_frame, _}` subtypes as recoverable in `ErrorHandler.check_recoverable/1`, or add a Frame.decode output that isn't consumed by `handle_control_frame/3` — and cover with integration tests.

**Success criteria:**
- [ ] Decision documented in CHANGELOG under whatever version ships R048
- [ ] Either both shapes removed from the contract, or both reachable via a MockWebSockServer integration test
- [ ] `TODO(Task R048)` markers removed from `client.ex`
- [ ] USAGE_RULES "Handler Message Reference" updated to match the new reality

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

### Task R047: Document Handler Message Shapes

**[D:2/B:5/U:6 → Eff:2.75]** 🎯

Document the six tuple shapes delivered to user-provided message handlers (`client.ex` lines 1051–1109, enumerated by Reach taint analysis in session on 2026-04-17): `{:message, map_or_binary}`, `{:binary, binary}`, `{:frame, term}`, `{:unmatched_response, map}`, `{:protocol_error, reason}`, `{:frame_error, error}`. Add a "Handler Message Reference" section to `USAGE_RULES.md`. Tighten the `handler` typespec in `client.ex:115` from `(term() -> term())` to a union of the six shapes. Also document the default-handler translation to `{:websocket_*, ...}` messages in the parent process. Flag as a minor follow-up: the default handler silently drops `{:unmatched_response, _}` (falls through to `_other -> :ok` at `client.ex:236`) — decide whether to forward it as `{:websocket_unmatched_response, _}` or leave the silent drop intentional.

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
