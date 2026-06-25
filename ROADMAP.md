# ZenWebsocket Roadmap

**Vision:** Production-grade WebSocket client library for Elixir, designed for financial APIs.

**Status:** v0.4.2 published on hex.pm (2026-04-18)

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## Current Focus

**Post-v0.4.2: Backlog open**

> **Philosophy reminder:** Trust working quality gates, fail gracefully on dead connections, and preserve caller configuration across reconnects.

### Recently Completed
| Task | Description | Notes |
|------|-------------|-------|
| R054 | Deduplicate `send_json_rpc/2` across two Deribit adapters | Shared `JsonRpcTransport` helper |
| R046 | MessageHandler property tests via GunStub | See CHANGELOG v0.4.1 |
| R045 | GunStub test helper (R044-fenced transport shapes) | See CHANGELOG v0.4.1 |
| R048 | Retire unreachable `:frame` / `:frame_error` handler shapes | See CHANGELOG v0.4.1 |
| R047 | Document handler message shapes | See CHANGELOG v0.4.1 |
| R044 | Amend testing policy: allow transport shape fixtures | See CHANGELOG v0.4.1 |
| R010 | Property-based testing (Frame, Config, JsonRpc) | See CHANGELOG v0.4.1 |
| R043 | Reject duplicate live request IDs | See CHANGELOG v0.4.1 |
| R042 | Fail pending requests on disconnect | See CHANGELOG v0.4.1 |
| R025 | Deployment guide for trading apps | See CHANGELOG v0.4.1 |
| R030 | Preserve config across reconnect | See CHANGELOG v0.4.1 |
| R011 | Error scenario test coverage | See CHANGELOG v0.4.1 |
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

> Managed by `rmap` — source of truth is `roadmap/tasks.toml`. Run `rmap show <id>` for full task detail, `rmap next` to pick the next task.

<!-- FOCUS:BEGIN -->
**Focus phase:** 1 — Post-v0.4.2 Backlog (1 of 8 done · 0 in progress)

**Last shipped:** no recent shipments

**Up next:** Task R050 — Audit unmatched-handler sites flagged by mix reach.otp [D:3/B:7/U:6 → Eff:2.17] 🎯
<!-- FOCUS:END -->

<!-- TASKS:BEGIN phase=1 -->
| Task | Status | Notes |
|------|--------|-------|
| Task R050 | ⬜ | 🎁 **code-quality** · Audit unmatched-handler sites flagged by mix reach.otp [D:3/B:7/U:6 → Eff:2.17?] 🎯 |
| Task R049 | ⬜ | 🎁 **code-quality** · Collapse repeated state.config field reads in Client [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task R052 | ⬜ | 🎁 **code-quality** · Flatten Client.connect/2 control flow (dominator depth 22) [D:4/B:5/U:5 → Eff:1.25?] 📋 |
| Task R051 | ⬜ | 🎁 **code-quality** · Decompose Reconnection.establish_connection/1 (dominator depth 39) [D:5/B:6/U:4 → Eff:1.0?] 📋 |
| Task R053 | ⬜ | 🎁 **code-quality** · Fix minor code smells surfaced by mix reach.smell [D:1/B:2/U:2 → Eff:2.0?] 🎯 |
| Task R055 | ⬜ | 🎁 **code-quality** · Extract duplicated Gun connect/reconnect log block in Client [D:2/B:3/U:2 → Eff:1.25?] 📋 |
| Task R056 | ⬜ | 🎁 **ci** · Make CI coverage gate measure core library only [D:4/B:5/U:5 → Eff:1.25?] 📋 |
| Task R054 | ✅ | 🎁 **code-quality** · Deduplicate send_json_rpc/2 across the two Deribit adapters [D:2/B:4/U:4 → Eff:2.0?] 🎯 |
<!-- TASKS:END -->

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
| v0.4.1 | Config preservation, pending-request safety, property tests, transport-shape policy (R010-R011, R025, R030, R042-R048) | 11 |
| v0.4.2 | Credo dep restored to hex (release-only maintenance) | — |

---

## Backlog

Tasks below seeded from `mix reach` (1.5) analysis on 2026-04-20. Findings captured in conversation, not stored as an artifact — rerun `mix reach.{otp,hotspots,depth,smell}` to refresh before starting.

---

Task detail now lives in `roadmap/tasks.toml` (rendered above / `rmap show <id>`). The sections below are decision history, byte-preserved by `rmap render`.

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

1. **v0.4.2 is live on hex.pm** — Latest release. v0.4.0 added R024-R041 (custom discovery hooks, stale PID safety, handler contract change, descripex integration, full doc review — breaking handler contract from v0.3.x). v0.4.1 added R010-R011, R025, R030, R042-R048 (config preservation, pending-request drain on disconnect, property tests, transport-shape testing policy). v0.4.2 restored credo to hex (no consumer-visible changes)
2. **Before v0.4.0, v0.3.1 was the last published version** — Pool routing, session recording, test helpers, docs rewrite
3. **R026 was abandoned** — Moving examples to separate mix projects caused too many problems
4. **Real API testing is non-negotiable** — Project principle. One narrow exception (R044): opaque Gun transport message-shape fixtures. See CLAUDE.md → Real API Testing Policy → Narrow exception
5. **Quality aliases removed** — No `mix lint/check/typecheck/coverage/rebuild`. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly
6. **Every task updates docs** — A task without updated `.md` files is incomplete
7. **Client has 9+ public functions** — Not "only 5". Core: connect, send_message, subscribe, get_state, close. Monitoring: get_latency_stats, get_heartbeat_health, get_state_metrics, reconnect
