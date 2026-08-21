# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-08-21

### Removed

- **BREAKING — RateLimiter queue telemetry:**
  `[:zen_websocket, :rate_limiter, :queue]`,
  `[:zen_websocket, :rate_limiter, :queue_full]`, and
  `[:zen_websocket, :rate_limiter, :pressure]` are no longer emitted. Remove
  handlers attached to those events; instrument the caller's
  `{:error, :rate_limited}` branch for rejection or pressure signals, while
  retaining `:consume` and `:refill` handlers for successful token use and
  refills.
- **BREAKING — RateLimiter queue configuration:** `:max_queue_size` and
  `@default_max_queue_size` were removed. Remove that key from limiter
  configuration and bound any application-owned retry queue where requests are
  actually retained.
- **BREAKING — `ZenWebsocket.RateLimiter.state/0`:** the public type was
  removed with the internal queue state. Replace references to it with an
  application-owned status-map type (or `map()`); use
  `ZenWebsocket.RateLimiter.config/0` for `init/2` input.
- **BREAKING — `mix stability_test`:** the shipped
  `Mix.Tasks.StabilityTest` task and its guide were removed. The task was part
  of the package because the package definition ships the complete `lib` tree.
  Replace scripts that invoke it with the relevant test command, such as
  `mix test --only external_network`, or an application-owned soak test.
- **BREAKING — `ZenWebsocket.Client.reconnect_opts_from_state/1`:** this
  function was removed from the `ZenWebsocket.Client` surface; it was not made
  private. Code that still needs this internal-state conversion can call the
  public `ZenWebsocket.Client.Reconnect.reconnect_opts_from_state/1` function.

### Changed

- **BREAKING — RateLimiter is an allow/deny gate, not a request queue.**
  `consume/2` now returns only `:ok | {:error, :rate_limited}` and never retains
  a rejected request; `{:error, :queue_full}` is gone. On `:rate_limited`, keep
  and retry the request in caller-owned code. `status/1` retains
  `queue_size`, `pressure_level`, and `suggested_delay_ms` only as neutral
  compatibility fields (`0`, `:none`, and `0`). Token consumption and refill
  now use compare-and-swap so concurrent refills cannot restore spent tokens.
- **BREAKING — `Client.connect/2` failure term and latency.** In 0.6.1 a third
  `:await_connection` clause immediately returned
  `{:error, :connection_failed}` when the client was neither `:connected` nor
  `:connecting`. The caller is now parked while the configured retry/backoff
  ladder runs and receives its terminal normalized reason: for example
  `{:error, :nxdomain}` when no retry applies, or
  `{:error, :max_reconnection_attempts}` when configured retries are exhausted.
  Match `{:error, reason}` instead of the single atom. `retry_count: 0` skips
  the backoff ladder but still waits for the first attempt to fail.
- **BREAKING — `ClientSupervisor.start_client/2` startup failures.** A client
  process dying during startup now yields `{:error, reason}` instead of exiting
  the caller. Replace `catch :exit` handling with an `{:error, reason}` match.
- **BREAKING — Deribit adapter JSON-RPC errors.**
  `DeribitAdapter.authenticate/1`, `subscribe/2`, and `unsubscribe/2`, plus
  `DeribitGenServerAdapter.authenticate/1` and `subscribe/2`, now return
  `{:error, reason}` for JSON-RPC error bodies instead of passing an
  `{:ok, error_body}` through (or accepting a failed heartbeat acknowledgement).
  Match the error tuple before treating authentication, subscribe, or
  unsubscribe as successful.
- **BREAKING — subscription tracking follows operations, not market-data
  ticks.** `SubscriptionManager.handle_message/2` tracks Deribit-style
  `public/subscribe` and `public/unsubscribe` requests, applies correlated
  result frames, and clears failed operations. It no longer adds every
  `"params.channel"` seen in inbound data. Tracking the Deribit dialect only is
  intentional: `build_restore_message/1` always emits Deribit's
  `public/subscribe` payload, so calling `SubscriptionManager.add/2` and
  `remove/2` from a non-Deribit integration records channels but does not give
  that venue working reconnect restoration. Non-Deribit consumers should own
  their own re-subscribe on reconnect.
- **BREAKING — generic heartbeat state reports the active type.** A generic
  heartbeat replaces `active_heartbeats` instead of accumulating every type
  ever observed. Treat `get_heartbeat_health/1`'s list as current state; retain
  history in application state or from heartbeat telemetry if needed.
- `JsonRpc.build_request/2` and the JSON-RPC client example now type positional
  parameter lists as well as named maps. Runtime acceptance was already broad;
  the corrected spec lets onchain remove its upstream Dialyzer suppression for
  list parameters.
- `ZenWebsocket.Client` remains the public GenServer. Call wrapping, Gun
  lifecycle, retry policy, frame routing, correlation, recording, and callback
  bodies were moved into responsibility-scoped submodules under
  `lib/zen_websocket/client/`. Apart from the
  `reconnect_opts_from_state/1` move documented above, supported Client
  signatures and return shapes are unchanged; the new
  `Client.build_client_struct/2` assembly helper is `@doc false` and used by
  `ClientSupervisor`.

### Fixed

- Client-owned Gun attempts use one retry state machine with Gun's independent
  retry disabled and attempt-specific timers, preventing duplicate reconnects
  and stale timeouts from terminating a later attempt.
- Supervisor discovery ignores non-PID child states such as `:restarting`.
- `:ping_pong` heartbeats use a unique payload and count only the matching pong;
  a missed pong increments `heartbeat_failures`. Gun forwards pong frames to
  the client, and `MessageHandler` no longer sends a duplicate pong for an
  inbound ping.
- Pool health state survives the first caller exiting. Scores use pending
  requests, latency, and errors; the unreachable pressure penalty was removed.
- Failed Deribit authentication or subscription restoration no longer reports
  success or discards the subscriptions still needing restoration.
- Recorder buffers flush when their linked owner terminates abnormally.

## [0.6.1] - 2026-08-17

### Changed — dependency refresh

- Resolved the published `descripex 0.12.1` patch within the unchanged
  `~> 0.12.0` runtime requirement.
- Updated development and analysis tooling: `ex_ast` 0.12.10 → 0.13.1,
  `sobelow` 0.14.1 → 0.15.0, `tidewave` 0.8.1 → 0.8.4, and transitive
  `spitfire` 0.3.13 → 0.4.0. The direct dev/test `ex_ast` dependency
  explicitly overrides Reach 2.8.2's older `~> 0.12.0` declaration.

## [0.6.0] - 2026-08-01

### Changed — `{:descripex, "~> 0.11"}` → `{:descripex, "~> 0.12.0"}` (breaking for consumers pinned below 0.12)

descripex 0.12.0 changed `short_name` in `describe/1` output from an atom to a
string — a consumer-visible contract change shipped at a *minor* bump. The old
`~> 0.11` bound (`>= 0.11.0 and < 1.0.0`) would have absorbed that silently on
any fresh resolution, so the requirement is now three-segment (`>= 0.12.0 and
< 0.13.0`). A 0.x package that breaks on minor earns the tighter form; raise the
cap deliberately after reading its release notes.

zen_websocket itself does not read `short_name` — the 17 `use Descripex` sites
and the `Descripex.Discoverable` root module are unaffected, and no library or
test code changed. The break is in the *bound*, not the behaviour.

**Minor, not patch**, for the same reason 0.5.0's gun floor was: narrowing a
runtime dependency requirement can fail resolution for a consumer pinned to
descripex 0.11.x. Loud failure, but still a compatibility break.

### Changed — lockfile

`req 0.7.1 → 0.7.2` (dev/test only, via the doc/tooling stack).

## [0.5.0] - 2026-08-01

### Changed — `{:gun, "~> 2.2"}` → `{:gun, "~> 2.4"}` (breaking for consumers pinned below 2.4)

gun 2.4.0 (2026-06-08) carries the fix for GHSA-w4f7-4cxr-rv3c. Under the old
`~> 2.2` bound a fresh install could still resolve a vulnerable gun; raising the
floor makes the fixed version *required* rather than merely permitted.

This is a **minor** bump, not a patch, because narrowing a runtime dependency
requirement can fail resolution for a consumer pinned to gun 2.2.x or 2.3.x.
That failure is loud rather than silent, but it is still a compatibility break
and semver should say so. (The 0.4.3 notes below state that declared bounds were
unchanged — true for 0.4.3; this release is where they change.)

### Changed — the coverage gate now measures something

`--cover-threshold` was **80** while actual coverage was **54.58%**, so
`mix precommit` could never pass and CI ran a separate 50% workaround. A floor
above actual coverage enforces nothing.

Measured before deciding, and the first hypothesis was wrong: the gap is *not*
an artifact of `--exclude integration`. Integration-inclusive coverage
(excluding only `external_network`/`stability*`) is **67.67%** — still short of
80. The floor was unreachable under every run mode.

Coverage was raised first where it was cheap and meaningful — **54.58% →
58.29%** — then the floor set to the measured value rounded down (**58**) at
both `cover-threshold` sites. Ratchet it as real coverage grows; never pad it.

New unit tests, all failure-capable rather than line-execution padding: `Config`
redaction edge cases, `Debug` logging on/off, `ConnectionRegistry` double-init,
`MessageHandler` routing branches, `PoolRouter` health formula and stale-error
clearing, `Recorder` malformed-data / corrupt-line / realtime-delay handling,
`RecorderServer` file-open failure and flush-timer paths, `HeartbeatManager`
telemetry gating, and `ClientSupervisor.send_balanced/2` failover.

Honest split of the remaining gap: most is genuinely integration-only (live
Gun/WebSocket paths — 133 `integration` and 25 `external_network` tests of 570),
plus an `ignore_modules` gap in `ex_unit_json --cover` for `Examples.*` /
`Mix.Tasks.*`. Only a couple of one-line TOCTOU/IO-error branches are "hard but
not integration."

### Changed — the quality gates now actually gate

- **`reach.check --smells` was reporting findings and exiting 0.** It raises only
  when `opts[:strict] || config.smells.strict`, and neither was set. `.reach.exs`
  now sets `smells: [strict: true]`; findings get fixed, never ignore-listed.
- **`mix_audit` added and wired.** `deps.audit.gated` proves the advisory
  database is current *before* auditing — `mix_audit` discards its own sync exit
  status (mirego/mix_audit#61), so a database that can no longer sync still
  prints "No vulnerabilities found" and exits 0.
- **`agents.check`** fails when `AGENTS.md` has drifted from `CLAUDE.md`.
- **CI invokes `mix ci`** instead of a hand-maintained check list, so the alias
  and the workflow can no longer drift apart.
- **MCP config mirrored to all four agent families** (`.cursor/`, `.codex/`,
  `.grok/`) — a server declared only in `.mcp.json` is invisible to cross-family
  agents.

`.mix_audit_ignore` carries exactly one entry, GHSA-w4f7-4cxr-rv3c, a verified
false positive *for gun*: the advisory covers cowboy (`< 2.16.0`) and gun
(`< 2.4.0`), but the mirror's importer groups by `ghsaId` alone, so both collapse
into one gun file carrying cowboy's range — and no cowboy file is written at all
(mirego/elixir-security-advisories#8).

## [0.4.3] - 2026-07-31

### Changed — dependency refresh
- **Lockfile dependency refresh** — `gun 2.4.1 → 2.5.0` (runtime), plus test/dev bumps: `cowboy 2.16.1 → 2.18.0`, `stream_data 1.3.0 → 1.4.0`, `styler 1.11.0 → 1.12.2`, `tidewave 0.6.1 → 0.8.1`, `reach 2.7.5 → 2.8.2`, `ex_slop 0.4.2 → 0.4.4`, `ex_dna 1.5.3 → 1.5.4`, `ex_ast 0.12.5 → 0.12.10`, `usage_rules 1.2.6 → 1.2.7`, and transitives (`plug`, `plug_crypto`, `req`, `mint`, `hpax`, `cowlib`, `ranch`, `igniter`, `bandit`, `earmark_parser`, `makeup`, `glob_ex`, `circular_buffer`). Lockfile resolution only — declared bounds in `mix.exs` are unchanged and the gun move stays inside `~> 2.2`. Verified green: 515 tests (incl. integration) passing, dialyzer clean, credo strict clean.
- `ex_ast` resolves to 0.12.10, not 0.13.1. Widening this project's `~> 0.12` bound would not change that: `reach 2.8.2` itself declares `ex_ast ~> 0.12.0`, so 0.13.x is unreachable in any project that depends on reach. The cap is upstream's, not this project's.

Additive release — no public-API or behavior change. Consumers upgrading from
0.4.2 need no code changes; the declared runtime bounds (`gun ~> 2.2`,
`jason ~> 1.4`, `telemetry ~> 1.3`, `certifi ~> 2.5`) are unchanged.

### Added
- **`ZenWebsocket.Examples.JsonRpcTransport`** — shared JSON-RPC send helper extracted from the two Deribit example adapters, removing the duplicated `send_json_rpc/2` wrapper (R054).
- **Reach architecture policy** (`.reach.exs`) and `ci` / `check.fast` / `precommit` / `precommit.full` mix aliases for deterministic quality gates.
- **ex_slop** Credo plugin and inline `ExDNA.Credo` clone diagnostics in `.credo.exs`.

### Changed
- **Dependency modernization** — `gun 2.2 → 2.4` (runtime), plus dev/test bumps: `reach 1.5 → 2.7`, `ex_ast 0.3 → 0.12`, `ex_dna 1.1 → 1.5`, `descripex 0.6 → 0.11`, `dialyzer_json`, `doctor`, `sobelow`, `tidewave`, `boxart`. Dialyzer PLT now uses `plt_add_deps: :apps_direct` to avoid transitive-dep bloat. The gun move is a lockfile resolution only — the declared `~> 2.2` bound already admitted 2.4.
- **Internal cleanups** — deduplicated the Deribit `public/test` heartbeat into a compile-time constant, removed redundant `@doc false` on private functions, and simplified pass-through `case` expressions to `match?/2`. No public-API or behavior change.

## [0.4.2] - 2026-04-18

### Changed
- **Credo dependency switched from git branch back to hex** — `mix.exs` pinned credo to `github: "rrrene/credo", branch: "release/1.7"` as a workaround for a 1.7.x sigil crash on Elixir 1.20+. The fix has landed in `credo 1.7.18` on hex, so the dep now reads `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`. Dev/test dependency only — no runtime or consumer impact; the shipped hex tarball is byte-identical to 0.4.1 modulo this `mix.exs` line and the lockfile.
- **ex_unit_json lockfile bump 0.4.2 → 0.4.3** — Picked up during `mix deps.get`. Dev/test dependency only; no runtime impact.

## [0.4.1] - 2026-04-18

### Changed
- **Handler message contract retired two unreachable shapes** — `{:frame, term}` and `{:frame_error, {:decode_error, term}}` are removed from `@type handler_message`, the default handler, `USAGE_RULES.md`, and the `ErrorHandling` example. Both shapes were documented in R047 prep but never actually delivered: `{:frame, _}` was the `other ->` catch-all of `route_data_frame/2`, unreachable because `MessageHandler.handle_control_frame/3` consumes every non-text/non-binary decode output before it gets there; `{:frame_error, {:decode_error, _}}` depended on `ErrorHandler.handle_error/1` returning non-`:stop` for `{:bad_frame, _}`, but `check_fatal/1` classifies every bad frame (and every unclassified error) as fatal, so the recoverable branch never ran. Decision was to retire rather than expand reachability — there is no concrete user need for recoverable frame-decode behavior, and `Frame.decode/1` only emits one error shape (`{:error, "Unknown frame type: ..."}`), which is a protocol violation with nothing to recover from. `MessageHandler.handle_message/2` and `decode_and_handle_control/1` simplify to always produce `{:protocol_error, _}` in the decode-error branch; `create_handler/1` drops the `{:decode_error, _}` routing clause. `handle_frame_error/2`'s tightened `@spec` now declares `{:protocol_error, term()}` as the only reachable error tag. This is a breaking change against the prepared v0.4.0 handler contract — **not** against the published v0.3.1 surface, since the retired tuples were added in v0.4.0 doc work (R047) but were never emitted at runtime (R048)
- **Handler message contract is now self-documenting and typed** — `ZenWebsocket.Client` exposes `@type handler_message/0` and `@type handler/0`, and the `handler` field in the GenServer state type uses `handler()` instead of `(term() -> term())`. USAGE_RULES.md adds a "Handler Message Reference" section with input-shape and default-handler translation tables, a custom-handler example, and a note on the `:protocol_error` / `:frame_error` payload asymmetry. The default handler now forwards `:unmatched_response` to the parent as `:websocket_unmatched_response` — previously the `_other` catch-all dropped it silently, making orphan JSON-RPC responses invisible to callers relying on default-handler delivery. Integration tests in `client_test.exs` cover the custom- and default-handler paths. The `:frame` and `:frame_error` handler shapes were discovered to be currently unreachable (control-frame consumption and fatal bad-frame classification respectively); both call sites carry `TODO(Task R048)` markers for the retire-or-reach decision (R047)
- **Testing policy now permits opaque Gun transport message-shape fixtures** — The "NO MOCKS ALLOWED" rule in CLAUDE.md and AGENTS.md is amended with a narrow, fenced exception: test doubles may construct the four Gun transport tuples (`:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`) using real pids (from `self()` / `spawn`) and real refs (from `make_ref/0`), because Gun's `pid` and `stream_ref` are opaque BEAM primitives with no public contract — there is no behavior for a fixture to drift against. Business-logic mocking (API response fixtures, auth-flow simulation, exchange-behavior simulation) remains explicitly prohibited; `MockWebSockServer` and real-API tests remain the source of truth for all `Client` / reconnection / subscription / exchange tests. AGENTS.md carries the "what is permitted" pointer; CLAUDE.md holds the full rationale and the "what is NOT newly allowed" list. Unblocks R045 (`GunStub` test helper) and R046 (`MessageHandler` property tests) (R044)

### Fixed
- **Duplicate live request IDs no longer silently overwrite the first caller** — `RequestCorrelator.track/4` used `Map.put/3` on `state.pending_requests`, so tracking a second request whose ID matched an already-pending entry silently replaced the first caller's `from` and timer. The first caller then blocked on `GenServer.call` until its per-call `request_timeout` fired, and its timeout timer became orphaned against an ID now owned by the second caller. `track/4` now returns `{:ok, new_state}` on success and `{:error, :duplicate_id, state}` on collision, leaving the first caller's pending entry (and its timer) intact. At the `Client.handle_call({:send_message, _}, …)` call site, the second caller receives `{:error, :duplicate_request_id}` immediately and no WebSocket frame is sent. No `:track` telemetry is emitted on the duplicate path, keeping event counts honest. Covered by unit tests in `request_correlator_test.exs` (`describe "track/4 duplicate ID"`) and an integration test in `client_test.exs` (`describe "duplicate request ID (R043)"`) that fires two `send_message` calls with the same JSON-RPC id back-to-back and asserts the second returns the error while the first still resolves when the server replies (R043)
- **Blocked callers no longer hang or inherit stale timeouts on automatic disconnect** — On the automatic Gun disconnect/reconnect path, `state.pending_requests` was never drained, so callers blocked on `GenServer.call` for a correlated response waited until their per-call `request_timeout` fired even though the socket was gone. `handle_connection_error/2` now calls `RequestCorrelator.fail_all/2`, which replies `{:error, :disconnected}` to every pending caller and emits `[:zen_websocket, :request_correlator, :fail_all]` telemetry. Correlation timers now use unique timer refs in their mailbox messages, so a stale timeout from a disconnected or already-resolved request cannot incorrectly time out a new request that reuses the same ID after reconnect (R042)
- **retry_count not reset after successful reconnect** — After a disconnect-reconnect cycle, `retry_count` accumulated instead of resetting to 0. This silently degraded reconnection capability over the lifetime of a long-running process — each successive disconnect cycle had fewer retry attempts available. Now reset to 0 on successful WebSocket upgrade (R030)
- **Explicit reconnect now preserves the original connection contract** — `Client.reconnect/1` no longer falls back to URL-only reconnects. Client structs returned by `connect/2` or `ClientSupervisor.start_client/2` now retain their validated config plus runtime callbacks such as `handler`, `heartbeat_config`, `on_connect`, and `on_disconnect`, so explicit reconnects keep the same headers, timeouts, retry settings, callback behavior, and supervision mode (R030)
- **Config inspection now redacts header values** — `inspect(config)` (and `inspect(client)` output containing `client.config`) redacts header values via a custom `Inspect` impl, preventing bearer tokens or API keys from leaking through struct inspection. Debug-mode log line that directly logged `config.headers` during WebSocket upgrade has been removed (R030)

### Added
- **`GunStub` test helper codifies the R044 transport-shape fence** — New `ZenWebsocket.Test.Support.GunStub` in `test/support/` exposes four constructors (`gun_upgrade/3`, `gun_ws/3`, `gun_down/4`, `gun_error/3`) that build the raw Gun transport tuples consumed by `MessageHandler.handle_message/2`. Every constructor defaults to real pids (`self/0`) and real refs (`make_ref/0`) — no fake opaque values, as required by R044. The `@moduledoc` states the fence verbatim and enumerates what is explicitly not allowed (API fixtures, auth flows, exchange semantics), pointing to `MockWebSockServer` as the source of truth for behavioral tests. One existing test in `message_handler_test.exs` ("handles gun_upgrade message for websocket") adopts the helper to prove it is viable; further adoption is incremental (R045)
- **MessageHandler property-test coverage** — New `message_handler_property_test.exs` uses `GunStub` + `stream_data` to assert `handle_message/2` routing totality and shape determinism: arbitrary non-Gun tuples always route to `{:ok, {:unknown_message, _}}` without raising; `gun_down` returns `{:connection_down, pid, reason}` for any reason term; `gun_error` returns `{:connection_error, pid, ref, reason}` for any reason term; text and binary data frames reach the handler callback across `StreamData.string(:utf8)` and `StreamData.binary()` respectively. Runs `async: true` and is fully pure (no network, no MockWebSockServer), so it stays in the default unit-test band (R046)
- **Property-based test coverage** — Added property tests using `stream_data` for three pure, deterministic modules (R010):
  - `Frame`: Gun-format and direct-format decode round-trips, constructor round-trips, close-frame normalization (integer code discarded), totality on arbitrary unknown shapes
  - `Config`: valid-input totality across all positive-int fields, URL scheme/host validation, per-field non-positive rejection, `max_backoff < retry_delay` ordering constraint, `new!/2` consistency with `new/2`
  - `JsonRpc`: `build_request/2` shape invariants, unique ID generation across N calls, `match_response/1` coverage for result, error, and notification cases
  - Deferred: `MessageHandler` property tests require Gun transport shape fixtures, which are blocked by the current "NO MOCKS" policy — tracked as R044 (policy amendment), R045 (`GunStub` helper), R046 (MessageHandler properties)
- **Error scenario test coverage** — Added explicit coverage for previously-untested error paths (R011):
  - Gun error variants in `error_handler_test.exs`: `{:gun_error, ..., :closed}`, `{:gun_error, ..., :timeout}`, `{:gun_down, ..., :tls_error, []}`, `{:gun_down, ..., :protocol_error, [refs]}`, and explain/1 unwrapping for both shapes
  - Frame corruption in `frame_test.exs`: unknown atom frame types, non-tuple input, empty tuple, arity-mismatched `:ws` frames, unknown inner `:ws` type, empty and 1MB payloads, deeply nested inner type, map input — all return `{:error, _}` rather than crashing
  - Concurrent correlation timeout cleanup in `request_correlator_test.exs`: N concurrent tracks timing out clear `pending_requests` and emit N telemetry events; timeout on an already-resolved request is a no-op
  - Rate limit recovery in `rate_limiter_test.exs`: queue drain via refill after `:queue_full`, mixed-cost bucket-capacity cap behavior, refill token cap verification, and concurrent consume calls not losing tokens
  - **Follow-up:** The gap R011 surfaced (pending requests not drained on Gun disconnect) is addressed by R042 above.
- **Deployment considerations guide** — New `docs/guides/deployment_considerations.md` covering latency sensitivity by strategy type, geographic proximity to exchange matching engines, connection architecture trade-offs (single vs pool vs per-account), production monitoring signals, and cancel-on-disconnect interactions. Framed as "questions to ask yourself" rather than prescriptive rules — the right answer depends on the operator's strategy and constraints. Cross-linked from README guide table and registered in `mix.exs` ExDoc `Guides` group (R025)
- **Reconnection behavior documentation** — USAGE_RULES.md now distinguishes automatic reconnect from explicit `Client.reconnect/1`, documenting what is preserved, reset, or carried across each path (R030)
- **Config preservation regression tests** — Mock-server regression tests now run in the default test suite and verify: retry_count resets after successful automatic reconnect, handler callbacks survive reconnect, Config structs remain identical across reconnects, supervised reconnect reruns lifecycle callbacks under `ClientSupervisor`, and explicit reconnect preserves the stored connection contract even after the original client is closed (R030)

## [0.4.0] - 2026-04-12

### Added
- **Self-describing API via Descripex** — All 17 library modules annotated with `use Descripex` and `api()` macro declarations. Root `ZenWebsocket` module uses `Descripex.Discoverable` for three-level progressive disclosure: `describe/0` (library overview), `describe/1` (module functions), `describe/2` (full function detail). Existing `@doc` strings preserved — `api()` writes machine-readable hints (BEAM slot 5) while `@doc` retains human prose (slot 4). Enables MCP tool discovery and JSON Schema generation. Tests cover all three describe levels and module registration completeness (R040)
- **Custom client discovery hooks** — `send_balanced/2` accepts optional `:client_discovery` function for plugging in custom registries (pg, Horde, :global) instead of local-only discovery. `start_client/2` accepts `:on_connect` and `:on_disconnect` lifecycle callbacks for external registry integration. Default behavior (local discovery via `list_clients/0`) unchanged. Documentation with pg and Horde examples in USAGE_RULES.md (R024)

### Fixed
- **Stale client PIDs no longer crash callers** — `send_message/2`, `get_state/1`, `get_heartbeat_health/1`, `get_state_metrics/1`, and `get_latency_stats/1` now check `Process.alive?` before `GenServer.call`. Dead PIDs return appropriate fallbacks (error tuple, `:disconnected`, or `nil`) instead of raising `:exit`. `send_balanced/2` benefits automatically via existing failover logic. Best-effort guard — callers needing race-proof delivery should use `send_balanced/2` with `:client_discovery` (R024) (R029)
- **Subscription messages not reaching user handler** — `route_data_frame/2` sent `"method" => "subscription"` messages only to `SubscriptionManager`, never forwarding to the user handler callback. Now updates tracker state and forwards to handler (R038)
- **Protocol errors not reaching user handler** — `handle_frame_error/2` stopped the GenServer on protocol errors without notifying the user handler first. Now calls `handler.({:protocol_error, reason})` before stopping, matching the `create_handler/1` contract (R039)
- **Double callback delivery bug** — `MessageHandler.handle_message/2` called user handler, then `route_data_frame` called it again for every data frame. Added `decode_and_handle_control/1` to MessageHandler for decode + control frame handling without handler invocation; Client GenServer uses this instead. Malformed frames are still classified as fatal protocol errors via ErrorHandler (R035)
- Skipped reconnection TODO replaced with real integration test — verifies Client GenServer survives MockWebSockServer disconnect and enters reconnection mode (R033)
- WebSocket upgrade now preserves query parameters from the connection URL — previously `wss://host/path?token=abc` would upgrade as just `/path`, dropping the query string (R031)
- `DeribitAdapter.subscribe/2`, `unsubscribe/2`, `authenticate/1`, and `send_request/3` now return `{:error, :not_connected}` when client is nil instead of raising `FunctionClauseError` (R027)
- `BatchSubscriptionManager` now handles subscribe failures: marks request as failed with error reason and stops processing instead of silently ignoring the return value (R028)
- `DeribitGenServerAdapter` `@doc` corrected from "handler module" to "handler function" (R028)
- **ErrorHandling example missing `handle_info` clause** — `{:websocket_error, reason}` messages caused `FunctionClauseError` in `examples/docs/error_handling.ex`. Added catch-all error handler clause (R041)
- **`subscribe/2` return type documented incorrectly** — USAGE_RULES.md showed `{:ok, subscription_id}` but actual spec returns `:ok | {:error, term()}` (R041)
- **`send_message/2` examples passed maps instead of binaries** — README.md and USAGE_RULES.md examples used `%{action: "ping"}` but spec requires `binary()`. Fixed to use `Jason.encode!/1` (R041)
- **Non-existent telemetry event documented** — `[:zen_websocket, :client, :message_received]` in USAGE_RULES.md replaced with accurate event list (R041)
- **Stale telemetry events in performance_tuning.md** — Events table listed `[:zen_websocket, :request, :start/complete/timeout]` and `[:zen_websocket, :subscription, :add/remove]` which use wrong namespaces. Replaced with actual 16 events from codebase across 6 namespaces (R041)
- **`get_state/1` misused in performance_tuning.md** — Examples showed `Client.get_state/1` returning full state map. Fixed to use `get_latency_stats/1`, `get_heartbeat_health/1`, `get_state_metrics/1` (R041)
- **Monitoring return shapes wrong in docs** — `get_heartbeat_health` documented as `%{failures: ..., last_at: ...}` but returns `%{failure_count: ..., last_heartbeat_at: ...}`. `get_state_metrics` documented as `%{pending_requests: ..., subscriptions: ..., memory_bytes: ...}` but returns `%{pending_requests_size: ..., subscriptions_size: ..., state_memory: ...}`. Latency stats documented as floats but returns integers. Fixed in USAGE_RULES.md and performance_tuning.md (R041)
- **`reconnect/1` missing limitation note** — Documented without noting it drops custom opts (headers, timeouts, etc.) on reconnect. Added note referencing R030 (R041)
- **ErrorHandling example `send_message` @doc claimed JSON encoding** — `@doc` said "will be JSON encoded" but `Client.send_message/2` requires binary. Fixed doc and spec (R041)
- **Architecture.md claimed "Gun HTTP/2"** — Library actually forces HTTP/1.1 ALPN for WSS upgrades. Also claimed "5 functions per module" without qualifying existing modules. Fixed both (R041)
- **`last_heartbeat_at` documented as DateTime** — Docs showed `~U[...]` but actual value is `System.monotonic_time(:millisecond)` (monotonic integer). Fixed in USAGE_RULES.md and performance_tuning.md (R041)
- **ErrorHandling example understated error surface** — `send_message/1` doc/spec claimed only `:ok | {:error, :not_connected}` but delegates to `Client.send_message/2` which returns `:ok | {:ok, map()} | {:error, term()}` including `{:error, {:not_connected, reason}}` variants. Fixed spec and doc (R041)

### Improved
- Reconnection test now restarts mock server and verifies post-reconnect frame delivery — previously only proved GenServer survived disconnect (R036)
- Subscribe test now captures server-received frame and validates JSON-RPC payload structure (method, channels) — previously only checked `:ok` return (R037)

- **Example files updated for handler contract change** — `ErrorHandling` example now handles `{:websocket_protocol_error, ...}` and `{:websocket_frame_error, ...}` instead of non-existent `{:websocket_error, ...}`; `JsonRpcClient.handle_message/1` now accepts pre-decoded maps instead of assuming raw JSON strings (codex review)
- **AGENTS.md module overview corrected** — Fixed stale function names across 9 modules (Frame, ErrorHandler, JsonRpc, Reconnection, MessageHandler, HeartbeatManager, SubscriptionManager, RequestCorrelator, RateLimiter). Added missing LatencyStats entry. Fixed test code example using non-existent `Frame.encode/1` (codex review)

### Changed
- **Quality workflow updated** — Removed `mix lint`, `mix typecheck`, `mix coverage`, `mix check`, `mix rebuild` aliases from mix.exs. Use `mix test.json`, `mix dialyzer.json --quiet`, `mix credo --strict --format json` directly for AI-friendly structured output. `mix security` remains as the Sobelow alias and now includes `--skip` so `.sobelow-skips` is honored for the known low-confidence Recorder findings.
- **CLAUDE.md imports updated** — Added `cli-aliases.md` and `agent-economy.md` includes; reordered to match Elixir Library template
- **Roadmap reformatted** — Migrated to `[D:X/B:Y/U:Z → Eff:W]` priority format; archived completed task details to CHANGELOG; added doc-update requirement to all pending tasks
- **Added `descripex ~> 0.6`** dependency for self-describing APIs
- **All docs updated** — README, AGENTS.md, CONTRIBUTING.md, USAGE_RULES.md updated to reference JSON output commands instead of removed aliases
- **Handler callback contract** — valid JSON text frames are now delivered as decoded maps (`%{"key" => "value"}`) instead of raw binary strings. Non-JSON text frames remain as binary. If your handler pattern-matches on `{:websocket_message, msg} when is_binary(msg)` and calls `Jason.decode/1`, update to match on `{:websocket_message, %{} = msg}` for JSON and `{:websocket_message, msg} when is_binary(msg)` for non-JSON text (R035)
- Root `ZenWebsocket` moduledoc rewritten to document current API — replaces legacy references to `Connection`, `Platform`, `Behaviors`, and `Defaults` with actual `Client`, `ClientSupervisor`, and module index (R034)
- **AGENTS.md module overview and file tree updated** — Corrected function names/arities for all modules, added missing ConnectionRegistry/Debug entries, updated file organization tree to all 19 modules, removed stale "separate mix project" guidance for examples (R041)
- **docs/Architecture.md updated** — Added 9 missing modules (LatencyStats, RecorderServer, Testing, ClientSupervisor, PoolRouter, Debug, HeartbeatManager, SubscriptionManager, RequestCorrelator), updated data flow diagram (R041)
- **"5 functions" framing updated** — USAGE_RULES.md, README.md, and AGENTS.md now describe "5 essential/core functions" with note about additional monitoring and management functions (R041)
- Version bump to 0.4.0

### Reverted
- R026 (Deribit example as separate mix project) — ergonomic cost outweighed benefit: broken Tidewave access, broken `.iex.exs`, 13+ stale doc references. Examples stay in `lib/zen_websocket/examples/`

## [0.3.1] - 2026-01-21

### Changed
- Update ex_doc to ~> 0.40 for llms.txt support (AI-friendly documentation)

## [0.3.0] - 2026-01-21

### Added
- `ZenWebsocket.PoolRouter` module for health-based connection routing (R022)
  - `select_connection/1` - select healthiest connection from pool
  - `calculate_health/1` - score (0-100) based on pending requests, latency, errors, pressure
  - `record_error/1` / `clear_errors/1` - error tracking with 60s decay
  - `pool_health/1` - get health snapshot for all connections
  - Round-robin fallback when connections have equal health
- `ClientSupervisor.send_balanced/2` for load-balanced message routing (R022)
  - Routes to healthiest connection using PoolRouter scoring
  - Automatic failover on send failure (configurable max_attempts)
  - Records errors and emits telemetry on failover
- Telemetry events for pool routing (R022)
  - `[:zen_websocket, :pool, :route]` - connection selected with health score
  - `[:zen_websocket, :pool, :health]` - pool health snapshot
  - `[:zen_websocket, :pool, :failover]` - failover attempt with reason
- `AGENTS.md` guide for AI coding agents contributing to the project (R023)
  - Module overview with key functions
  - Project constraints (5 functions, 15 lines, real API testing)
  - Testing strategy and common patterns
  - Debugging guide (recording, state inspection)
- `ZenWebsocket.Testing` module with consumer-facing test utilities (R020)
  - `start_mock_server/1` - simplified mock server startup with URL generation
  - `stop_server/1` - cleanup server and resources
  - `simulate_disconnect/2` - trigger disconnect scenarios (`:normal`, `:going_away`, `{:code, n}`)
  - `inject_message/2` - send message from server to connected clients
  - `assert_message_sent/3` - verify client sent expected message (string, regex, map, or function matcher)
  - Helpers integrate with ExUnit setup/on_exit patterns
- `ZenWebsocket.Recorder` module for session recording (R019)
  - `format_entry/3` - format frames as JSONL entries
  - `parse_entry/1` - parse JSONL entries back to structs
  - `replay/3` - stream recorded sessions to handler function
  - `metadata/1` - get session statistics (count, duration, timestamps)
- `ZenWebsocket.RecorderServer` async GenServer for file I/O (R019)
  - Buffered writes with periodic flush (1s interval or 100 entries)
  - Non-blocking `record/3` via send (not call)
  - `stats/1` returns entries count and bytes written
- Config option `record_to: path` enables session recording (R019)
  - Records inbound and outbound frames with microsecond timestamps
  - JSONL format (one JSON object per line) for streaming writes
  - Binary frames encoded as base64
  - Close frames include code and reason

### Changed
- `PoolRouter.calculate_health/1` uses `div/2` for cleaner integer arithmetic
- `ClientSupervisor` restart policy documented in `@moduledoc` (moved from comment)
- Private functions consistently use `@doc false` with explanatory comments
- `USAGE_RULES.md` expanded with v0.2.0+ features (R023)
  - Testing module documentation (replaced MockWebSockServer references)
  - Session recording section with Recorder API
  - Expanded monitoring/observability section (latency, heartbeat, metrics)
  - ErrorHandler.explain/1 usage example
  - New config options (record_to, latency_buffer_size)
  - Telemetry events reference table
  - Updated test count (93 → 395)

### Removed
- Stale documentation files superseded by ROADMAP.md and AGENTS.md
  - `docs/TaskList.md`, `docs/deferred_tasks.md`
  - `docs/JsonRPCElixir_MigrationTasks.md`, `docs/json_rpc_elixir.md`
  - `docs/WNX0019_learnings.md`, `docs/test_roadmap.md`

## [0.2.0] - 2026-01-20

### Added
- Building Adapters Guide enhanced at `docs/guides/building_adapters.md` (R012)
  - Adapter decision tree (plain client vs struct vs GenServer)
  - Heartbeat interface documentation (`:deribit`, `:ping_pong`, `:binance`, custom)
  - Authentication patterns (API key+secret, HMAC signature, OAuth token flow)
  - Binance Spot adapter example (non-JSON-RPC pattern)
- Performance Tuning Guide at `docs/guides/performance_tuning.md` (R013)
  - Configuration parameter tuning (timeouts, reconnection, latency buffer)
  - Rate limiter tuning with exchange-specific cost functions
  - Telemetry events reference table
  - Memory characteristics documentation
  - Common tuning scenarios (HFT, market data, resource-constrained)
- JsonRpc edge case tests for nil/empty params, empty methods, malformed responses (R016)
- `ErrorHandler.explain/1` returns human-readable error messages with fix suggestions (R018)
- `ZenWebsocket.LatencyStats` module for bounded circular buffer latency statistics (R017)
- `Client.get_latency_stats/1` returns p50/p99/last/count latency metrics (R017)
- Telemetry event `[:zen_websocket, :connection, :upgrade]` with `connect_time_ms` measurement (R017)
- Telemetry event `[:zen_websocket, :heartbeat, :pong]` with `rtt_ms` measurement (R017)
- Telemetry event `[:zen_websocket, :rate_limiter, :pressure]` for backpressure signaling (R021)
- Config option `latency_buffer_size` (default: 100) for latency stats circular buffer (R017)
- `RateLimiter.status/1` now returns `pressure_level` and `suggested_delay_ms` fields (R021)
- `ZenWebsocket.HeartbeatManager` module for heartbeat lifecycle management (R001)
- `ZenWebsocket.SubscriptionManager` module for subscription tracking and restoration (R002)
- `ZenWebsocket.RequestCorrelator` module for JSON-RPC request/response correlation (R003)
- Telemetry events for SubscriptionManager: `:add`, `:remove`, `:restore` (R002)
- Telemetry events for RequestCorrelator: `:track`, `:resolve`, `:timeout` (R003)
- `RateLimiter.shutdown/1` for proper ETS table cleanup (R005)
- Configurable `max_queue_size` option for RateLimiter (default: 100) (R005)
- Telemetry events for rate limiter: `:consume`, `:queue`, `:queue_full`, `:refill` (R005)
- Memory characteristics documentation in RateLimiter @moduledoc (R005)
- Test tagging conventions documentation in test_helper.exs (R015)
- Test coverage exclusion config for non-production modules (T001)
- Test coverage roadmap documentation at `docs/test_roadmap.md`
- Frame edge case tests for direct frame format decoding (T002)
- Config boundary value tests for `new!/2` and `request_timeout` validation (T003)
- Reconnection extreme value tests for nil max_backoff and zero retries (T004)

### Changed
- RequestCorrelator now stores timestamps and emits `round_trip_ms` in resolve telemetry (R017)
- RateLimiter tracks pressure level and emits threshold-crossing events at 25%/50%/75% queue fill (R021)
- HeartbeatManager emits RTT telemetry on heartbeat responses (R017)
- Client tracks connection timing from connect start to WebSocket upgrade (R017)
- Test coverage metrics now exclude non-production modules (Examples, Test.Support, Mix.Tasks) - reported coverage ~38% → ~70% (T001)
- Frame module now at 100% test coverage (T002)
- Config module now at 100% test coverage (T003)
- Extracted heartbeat logic from Client.ex to HeartbeatManager (789 lines from 870) (R001)
- Extracted subscription tracking from Client.ex to SubscriptionManager (R002)
- Extracted request/response correlation from Client.ex to RequestCorrelator (R003)
- Client.ex now fully delegates to extracted modules; removed dead `restore_subscriptions/4` from Reconnection (R004)
- Automatic subscription restoration on reconnect via `maybe_restore_subscriptions/1` (R002)
- Replaced magic numbers with named module attributes in Client, ClientSupervisor, and Reconnection modules (R008)
- Standardized `Debug.log/2` to accept only `Config.t()` struct, removed polymorphic state map interface (R009)
- BasicUsage example now uses Deribit testnet instead of echo.websocket.org
- MockWebSockServer handler registration improved in `websocket_init/1`
- Downgraded Elixir from 1.20.0-rc.1 to 1.19.5 (fixes Credo false positives)
- RateLimiter `handle_rate_limit/5` now accepts config parameter to avoid double ETS lookup (R005)

### Fixed
- Dialyzer warning on `Client.maybe_restore_subscriptions/1` - expanded `Client.state()` type to include all fields (R002)
- ConnectionRegistry monitor leaks: `cleanup_dead/1` and `shutdown/0` now properly demonitor before deletion (R006)
- Flaky tests: migrated from unreliable echo.websocket.org to local MockWebSockServer
- Race conditions in ErrorHandlingTest with proper `wait_for_connection/1` polling
- MockWebSockServer now raises clear error when TLS certificates unavailable
- Test tagging: 7 integration test files now properly tagged with `@moduletag :integration` (R015)
  - `mix test` now runs 141 unit tests (~5 seconds vs ~93 seconds for full suite)
  - Removed incorrect `@moduletag :integration` from `platform_adapter_template_test.exs` (pure unit tests)
  - Removed module-level tag from `rate_limiting_test.exs` (uses `@describetag` for integration blocks only)

## [0.1.4] - 2025-11-05

### Changed
- **Breaking**: DeribitRpc functions now return `{:ok, map()}` tuples instead of bare maps for consistency with library conventions
- Updated Erlang from 27.3.4 to 28.1.1
- Updated Elixir from 1.18.4 to 1.19.1-otp-28

### Improved
- DeribitAdapter and DeribitGenServerAdapter updated to use `with` statements for better error handling
- Correlation test improved with MockWebSockServer usage
- Test helper configuration cleaned up for better readability

## [0.1.3] - 2025-08-11

### Fixed
- Compilation error in mix zen_websocket.validate_usage task (regex in module attributes)

## [0.1.2] - 2025-08-11

### Added
- USAGE_RULES.md for AI agents and developer guidance
- Mix task `zen_websocket.usage` to export usage rules
- Mix task `zen_websocket.validate_usage` to validate code patterns
- Integration with usage_rules library ecosystem
- JSON export format for usage rules
- Automated code validation for common anti-patterns

### Improved
- Documentation with clear usage patterns and examples
- Package metadata for Hex.pm publishing

## [0.1.1] - 2025-05-24

### Added
- Initial release of ZenWebsocket
- Core WebSocket client implementation with Gun transport
- Automatic reconnection with exponential backoff
- Comprehensive error handling and categorization
- JSON-RPC 2.0 protocol support
- Request/response correlation manager
- Configurable token bucket rate limiter
- Integrated heartbeat/keepalive functionality
- Fault-tolerant adapter architecture
- Production-ready Deribit exchange integration
- Connection registry for multi-connection management
- Message handler with routing capabilities
- WebSocket frame encoding/decoding
- Telemetry events for monitoring
- Comprehensive test suite using real APIs (no mocks)
- Full documentation with examples

### Features
- Simple 5-function public API
- Financial-grade reliability for trading systems
- Platform-agnostic design with adapter pattern
- Real-world tested against live WebSocket endpoints
- Strict code quality standards (max 5 functions per module, 15 lines per function)

[Unreleased]: https://github.com/ZenHive/zen_websocket/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/ZenHive/zen_websocket/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/ZenHive/zen_websocket/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/ZenHive/zen_websocket/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ZenHive/zen_websocket/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/ZenHive/zen_websocket/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/ZenHive/zen_websocket/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/ZenHive/zen_websocket/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ZenHive/zen_websocket/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/ZenHive/zen_websocket/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ZenHive/zen_websocket/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ZenHive/zen_websocket/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/ZenHive/zen_websocket/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/ZenHive/zen_websocket/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ZenHive/zen_websocket/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ZenHive/zen_websocket/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ZenHive/zen_websocket/releases/tag/v0.1.1
