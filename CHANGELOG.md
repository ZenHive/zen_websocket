# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-08-25

### Fixed — documentation described a different library than the one that ships

A full accuracy pass over the consumer-facing docs. The reference layer
(`@doc`/`@spec`, telemetry and `Config` tables) was already accurate; every
defect below was in copy-pasteable example code, so following the old docs
produced runtime errors rather than merely misleading prose.

- **`Client.send_message/2` takes an encoded `binary()`, not a map.** Twelve
  call sites across `README.md`, `USAGE_RULES.md` and the guides passed raw
  maps. They now encode with `Jason.encode!/1`. The inbound direction is
  unchanged: text frames are decoded for you, so handlers still receive maps.
- **`heartbeat_interval` was never a connect option.** The knob is
  `heartbeat_config` (default `:disabled`); the documented `heartbeat_interval:`
  had no effect. Corrected in `README.md` and `USAGE_RULES.md`, along with the
  invented `:custom` / `:standard` heartbeat types.
- **Supervised start paths need `:handler` to deliver unsolicited frames.**
  Only `Client.connect/2` installs a parent-forwarding handler (via
  `Client.CallFacade.with_default_handler/2`). Other start paths use a discard
  handler by default; internal heartbeat and pending JSON-RPC response handling
  still work, but user-deliverable frames are dropped unless a handler is
  supplied.
- **Frames matching `%{"method" => "heartbeat"}` never reach the user handler**
  — documented in `docs/guides/building_adapters.md`, which previously implied
  all text frames are delivered.
- `docs/gun_integration.md` documented the pre-decomposition monolith and
  mis-described `await_transport/2`'s monitor handling; `docs/Examples.md`
  claimed the Deribit examples had moved out of this repo (a reverted decision)
  and linked to paths that 404 on hexdocs.
- Removed fabricated benchmark figures and a contradictory
  16-24-vs-8 bytes/sample claim; Deribit rate limits now cite `docs.deribit.com`.
- `MessageHandler.default_handler/1` documented as accepting and discarding —
  it never logged. `Logger.warn` (removed from Elixir) replaced with
  `Logger.warning`. `SECURITY.md` no longer claims only 0.4.x is supported.
- Doctest corrections in `Recorder` (wrong JSON key order and a
  non-existent microsecond padding) and `LatencyStats.percentile/2`
  (`percentile(1..100, 50)` returns `51`, not `50`).

### Changed — self-describing API

- `ZenWebsocket.describe/0` now omits the four Client-owned internal managers,
  while `describe(:client)` includes the supervised `start_link/2` and
  `child_spec/1` entry points. Wire-derived inputs and opaque Client-owned state
  are marked as non-caller-supplied `:exchange_data`; caller-created rate-limit
  requests remain ordinary `:value` inputs.
- `mix zen_websocket.validate_usage` derives the allowed Client calls from the
  same Descripex declarations, eliminating a second hand-maintained API list.

### Added

- `ZenWebsocket.ConnectionRegistry` is now annotated with `Descripex`, so it
  appears in `ZenWebsocket.describe/0` output with per-function metadata. It was
  the one module listed in the `Discoverable` manifest without annotations.
- `defrpc` now emits an `@spec` for each generated function.
- 16 doctests are now executed by the suite (`ZenWebsocketTest`). Previously
  authored doctests in `ErrorHandler`, `JsonRpc`, `LatencyStats`, `Recorder`
  and `Reconnection` were never run, which is why the errors above survived.
- `CHANGELOG-archive.md` — releases 0.1.1 through 0.4.3 moved out of
  `CHANGELOG.md` and shipped as a separate documentation extra. Entries whose
  provenance is uneven are marked as such, and a missing `0.1.5` entry was
  reconstructed.

## [0.7.1] - 2026-08-22

### Changed — descripex bound

- Runtime requirement widened `{:descripex, "~> 0.12.0"}` →
  `{:descripex, "~> 0.12"}` so a descripex minor no longer forces a
  zen_websocket release. The committed `mix.lock` still pins the resolved
  version; a new descripex lands only through a deliberate `mix deps.update`.
- Resolved `descripex 0.13.0` in the lockfile. 0.13.0 adds
  `typeless_params/1` and folds more `@spec` shapes into JSON Schema; it does
  not change `json_spec ~> 1.1` or zen_websocket's `use Descripex` call sites.

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
- **BREAKING — the `ZenWebsocket.RateLimiter` `state/0` type:** the public type was
  removed with the internal queue state. Replace references to it with an
  application-owned status-map type (or `map()`); use
  `t:ZenWebsocket.RateLimiter.config/0` for `init/2` input.
- **BREAKING — `mix stability_test`:** the shipped
  `Mix.Tasks.StabilityTest` task and its guide were removed. The task was part
  of the package because the package definition ships the complete `lib` tree.
  Replace scripts that invoke it with the relevant test command, such as
  `mix test --only external_network`, or an application-owned soak test.
- **BREAKING — `ZenWebsocket.Client` `reconnect_opts_from_state/1`:** this
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

- `mix zen_websocket.validate_usage` recognizes nested
  `ZenWebsocket.Client.*` module references instead of reporting the module
  segment as an unknown Client function.
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
- **`mix ci` is the canonical repository gate.** The GitHub Actions workflows
  were removed, so no check runs automatically on push.
- **MCP config mirrored to all four agent families** (`.cursor/`, `.codex/`,
  `.grok/`) — a server declared only in `.mcp.json` is invisible to cross-family
  agents.

`.mix_audit_ignore` carries exactly one entry, GHSA-w4f7-4cxr-rv3c, a verified
false positive *for gun*: the advisory covers cowboy (`< 2.16.0`) and gun
(`< 2.4.0`), but the mirror's importer groups by `ghsaId` alone, so both collapse
into one gun file carrying cowboy's range — and no cowboy file is written at all
(mirego/elixir-security-advisories#8).

Releases 0.4.3 and earlier are in [CHANGELOG-archive.md](CHANGELOG-archive.md).

[Unreleased]: https://github.com/ZenHive/zen_websocket/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/ZenHive/zen_websocket/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/ZenHive/zen_websocket/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/ZenHive/zen_websocket/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/ZenHive/zen_websocket/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ZenHive/zen_websocket/compare/v0.4.3...v0.5.0
