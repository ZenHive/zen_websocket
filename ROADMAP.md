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

| Task | Status | Eff | Description |
|------|--------|-----|-------------|
| R050 | ⬜ | 2.17 🎯 | Audit 8 unmatched-handler sites flagged by `mix reach.otp` |
| R049 | ⬜ | 1.5 🚀 | Collapse repeated `state.config` field reads in `Client` |
| R052 | ⬜ | 1.25 📋 | Flatten `Client.connect/2` control flow (depth 22) |
| R051 | ⬜ | 1.0 📋 | Decompose `Reconnection.establish_connection/1` (depth 39) |
| R053 | ⬜ | 1.5 🚀 | Fix minor code smells surfaced by `mix reach.smell` |
| R054 | ⬜ | 2.5 🎯 | Deduplicate `send_json_rpc/2` across two Deribit adapters |
| R055 | ⬜ | 1.67 🚀 | Extract duplicated Gun connect/reconnect log block in `Client` |

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

### Task R050: Audit unmatched-handler sites — [D:3/B:7/U:6 → Eff:2.17] 🎯

`mix reach.otp` flags 8 call sites targeting handlers it can't resolve. In a WebSocket client with reconnect and recording paths, an unmatched message is a silent drop — the exact failure mode we cannot afford.

**Sites flagged:**
- `lib/zen_websocket/client.ex:263`
- `lib/zen_websocket/client_supervisor.ex:127`
- `lib/zen_websocket/recorder_server.ex:102, 137`
- `lib/zen_websocket/examples/deribit_genserver_adapter.ex:59, 96`
- `lib/zen_websocket/examples/batch_subscription_manager.ex:96`
- `lib/zen_websocket/examples/docs/error_handling.ex:105`

**What to do:** For each site, determine whether it's a genuine unmatched message (missing `handle_call`/`handle_cast`/`handle_info` clause, or clause that won't pattern-match the sent shape) or a false positive (dynamic dispatch, cross-module call reach can't resolve). For each genuine miss, add the handler clause and a test that exercises the path. For each false positive, document the pattern so future audits can skip it.

**Success:** Each of the 8 sites has either (a) a matching handler + test, or (b) an inline comment explaining why reach flagged it and why it's safe.

---

### Task R049: Collapse repeated `state.config` reads in `Client` — [D:2/B:3/U:3 → Eff:1.5] 🚀

`mix reach.smell` flagged 14+ consecutive identical `state.config` field accesses in `lib/zen_websocket/client.ex` (lines 756-817, roughly covering `handle_info/2` and nearby clauses). Destructure once at clause entry (`%{config: cfg} = state`) or use `with` binding.

**Scope:** Only the flagged ranges. Don't refactor broader state-handling patterns. Don't rename fields.

**Success:** Re-running `mix reach.smell` no longer reports the `:state.config called twice` findings in `client.ex`. All existing tests pass. No behavior change.

---

### Task R053: Fix minor code smells from `mix reach.smell` — [D:1/B:2/U:2 → Eff:2.0] 🎯

One-off cleanups flagged by `mix reach.smell`:

- `lib/mix/tasks/zen_websocket.usage.ex:182-183` — `Enum.map |> Enum.map` fusion
- `lib/zen_websocket/examples/deribit_genserver_adapter.ex:204` — `state.subscriptions` read twice; bind once
- `lib/zen_websocket/pool_router.ex:233` — duplicate module-attribute read
- `lib/zen_websocket/testing/server.ex:96` — duplicate module-attribute read
- `lib/zen_websocket/examples/usage_patterns.ex:78` — `client.server_pid` read twice

**Success:** Each flagged site is either resolved or has a comment noting why the duplication is intentional. Existing tests pass.

---

### Task R052: Flatten `Client.connect/2` control flow — [D:4/B:5/U:5 → Eff:1.25] 📋

`mix reach.depth` reports `ZenWebsocket.Client.connect/2` at dominator depth 22 (branches=4, callers=2). It's the public entry point — high cyclomatic complexity here hurts both testability and the mental model for new adapter authors.

**What to do:** Investigate the function at `lib/zen_websocket/client.ex:228`. Identify whether the depth comes from legitimate branching (protocol negotiation, config validation, transport selection) or from accumulated conditionals that can be extracted into small helpers or a `with` pipeline. Match the style already used in the rest of the module.

**Non-goals:** Changing the public signature, altering error return shapes, or restructuring callers.

**Success:** Depth reduced meaningfully (target <15). Behavior preserved — all integration and mock-server tests still pass. No new Dialyzer warnings.

---

### Task R054: Deduplicate `send_json_rpc/2` across Deribit adapters — [D:2/B:4/U:4 → Eff:2.0] 🎯

`mix ex_dna` finds an exact duplicate of `send_json_rpc/2` across the two Deribit example adapters:

- `lib/zen_websocket/examples/deribit_adapter.ex:127`
- `lib/zen_websocket/examples/deribit_genserver_adapter.ex:224`

Both are the same 7-line `case Client.send_message/Jason.encode!` wrapper. Because both live under `examples/`, the right fix is probably a small shared helper in a neutral location rather than one adapter depending on the other. Investigate whether `ZenWebsocket.JsonRpc` (the existing JSON-RPC module) is the right home, or whether a shared `DeribitHelpers` module fits better given both files target Deribit specifically.

**Non-goals:** Don't merge the two adapters. They demonstrate different patterns (standalone vs GenServer-wrapped) on purpose.

**Success:** `mix ex_dna` no longer reports this clone. Both adapters still compile, their tests pass, and the public example surface is unchanged.

---

### Task R055: Extract duplicated Gun connect/reconnect log block — [D:2/B:3/U:2 → Eff:1.25] 🚀

`mix ex_dna --literal-mode abstract` finds an 18-line `Debug.log` block duplicated at `lib/zen_websocket/client.ex:598` and `:640`. The only differences are four log prefix strings — one branch logs "Gun connection established", the other logs "Gun reconnection successful", etc. Classic candidate for a helper that takes the four labels as arguments.

**Note:** ex_dna's second abstract-mode hit (`heartbeat_manager.ex:76` vs `subscription_manager.ex:140`) is a **false positive** — both sites use descripex's `api()` macro, whose structural similarity is by design. Do not collapse those.

**Success:** `mix ex_dna --literal-mode abstract` no longer reports the client.ex:598/640 clone. All existing tests pass. No behavior change.

---

### Task R051: Decompose `Reconnection.establish_connection/1` — [D:5/B:6/U:4 → Eff:1.0] 📋

`mix reach.depth` reports `ZenWebsocket.Reconnection.establish_connection/1` at dominator depth 39 — the deepest function in the codebase by a wide margin. Reconnection logic is the most failure-prone area of any WebSocket client; depth here makes the "what happens when X fails halfway through?" question hard to answer.

**What to do:** Investigate `lib/zen_websocket/reconnection.ex:50`. The function almost certainly chains several phases (open transport → upgrade → authenticate → resubscribe → restore state). Extract each phase into a named helper with a clear error-return type. A `with` pipeline or an explicit phase-list reducer both work — pick what reads better against the existing codebase style.

**Constraints:** Must preserve existing telemetry events. Must preserve existing retry/backoff semantics. Must not change the public return shape.

**Success:** Depth reduced to <20. Existing reconnection regression tests (R033, R036) pass unchanged. No new Dialyzer warnings. Easier to reason about "what state are we in when this fails?"

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

1. **v0.4.2 is live on hex.pm** — Latest release. v0.4.0 added R024-R041 (custom discovery hooks, stale PID safety, handler contract change, descripex integration, full doc review — breaking handler contract from v0.3.x). v0.4.1 added R010-R011, R025, R030, R042-R048 (config preservation, pending-request drain on disconnect, property tests, transport-shape testing policy). v0.4.2 restored credo to hex (no consumer-visible changes)
2. **Before v0.4.0, v0.3.1 was the last published version** — Pool routing, session recording, test helpers, docs rewrite
3. **R026 was abandoned** — Moving examples to separate mix projects caused too many problems
4. **Real API testing is non-negotiable** — Project principle. One narrow exception (R044): opaque Gun transport message-shape fixtures. See CLAUDE.md → Real API Testing Policy → Narrow exception
5. **Quality aliases removed** — No `mix lint/check/typecheck/coverage/rebuild`. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly
6. **Every task updates docs** — A task without updated `.md` files is incomplete
7. **Client has 9+ public functions** — Not "only 5". Core: connect, send_message, subscribe, get_state, close. Monitoring: get_latency_stats, get_heartbeat_health, get_state_metrics, reconnect
