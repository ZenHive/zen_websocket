# CLAUDE.md

@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md

<!--
  Selective-load (Opus 4.8): the eager floor is `critical-rules` (hard guardrails
  that must stay ambient) + `harness-workflow` (implement -> review -> land loop —
  zen_websocket is a registered harness dispatch target). Everything else is
  skill-on-demand: `elixir:ex-unit-json`, `elixir:dialyzer-json`,
  `elixir:zen-websocket`, `elixir:code-style`, `tasks:rmap`,
  `workflow:git-worktrees`. Re-add an `@`-import here only if Opus is observed
  failing on that surface.
-->

---

## Project Overview

**ZenWebsocket** is a robust WebSocket client library for Elixir, specifically designed for financial APIs (particularly Deribit cryptocurrency trading). Built on Gun transport with reconnection, heartbeat, rate limiting, and request/response correlation.

**Financial Development Principle**: Start simple, add complexity only when necessary based on real data.

## Project-Specific Commands

```bash
# Code Quality (use JSON output for AI-friendly results)
mix test.json                                  # Run tests (see logs/warnings)
mix test.json --quiet                          # Run tests (clean JSON only)
mix test.json --quiet --failed --first-failure # Iterate on failures
mix dialyzer.json --quiet                      # Type checking
mix credo --strict --format json               # Static analysis
mix security                                   # Sobelow security scan

# Testing (integration tests excluded by default)
mix test.json --quiet --summary-only   # Quick health check
mix test --include integration         # Include integration tests (MockWebSockServer / Gun)
mix test --include external_network    # Tests requiring internet (Deribit testnet, etc.)
mix zen_websocket.usage                # Export usage rules
mix zen_websocket.validate_usage       # Check Client API usage against the public surface
```

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Canonical gate:** `mix precommit.full` (alias `mix ci`) — the comprehensive pass the harness reviewer's `check_command` runs and what GitHub CI (`.github/workflows/harness.yml`) invokes directly. Fast local loop: `mix precommit` (skips the cold-PLT dialyzer + deps audit).
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 90 --exclude integration --include local_network` (`MIX_ENV=test`), `dialyzer` (forced `MIX_ENV=dev` — see below), `agents.check`.
- **`mix ex_dna --max-clones 0` is not a byte-identical-function detector.** The gate (and the same defaults on `ExDNA.Credo` during `mix credo`) is Type I + Type II with `literal_mode: :keep`, `min_mass: 30`, Type III off (`min_similarity: 1.0`). Comments add no mass. Cross-module comparison works; what it misses are fragments below 30 AST nodes (the shared callback wrapper was mass 22–26; the shared heartbeat `if` was mass 22) and above-threshold functions whose ASTs still differ after Type-II keep — `__MODULE__` vs a qualified alias, local vs remote call, reversed argument order (`build_client_struct/2` was mass 35–36 and still silent). Type II `--literal-mode abstract` also missed those three; Type III at 0.85 flagged unrelated descripex `api()` wrappers, not them. A green zero-clone run means nothing crossed *that* boundary, not that duplication is absent. See the comment on `"ex_dna --max-clones 0"` in `mix.exs`.
- **The coverage floor is a measured ratchet, not an aspiration.** 90 is core-library coverage measured 2026-08-21 (`mix test.json --cover --exclude integration --include local_network` after honoring `test_coverage: ignore_modules`), rounded down. The previous 58 measured the diluted suite because ex_unit_json 0.6.0 ignores regexes in that list. Raise it in lockstep with real core coverage; never pad it.
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape.
- **The gate's dialyzer step forces `MIX_ENV=dev`, not `:test`.** Under `:test`, the test-only mock-server stack (`cowboy`, `plug_cowboy`, `websock`, `x509`, `temp`, `stream_data`) joins this repo's `plt_add_deps: :apps_direct` analyzed set and produces false `unknown_function` warnings against the OOM-tuned PLT (see `defp dialyzer` in `mix.exs`). `preferred_envs` in `def cli` is ignored inside alias steps, so the dev override is an explicit `cmd env MIX_ENV=dev mix dialyzer`.
- **`reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`). Smell findings must be fixed for real, never added to an ignore list.
- **`deps.audit.gated` proves the local mix_audit advisory mirror is fresh (`bin/advisory-freshness.sh` in `onchain-stack`) before running `mix deps.audit --ignore-file .mix_audit_ignore`** — `mix_audit` discards its own sync exit status (`mirego/mix_audit#61`), so a frozen mirror would otherwise report a false "No vulnerabilities found." `.mix_audit_ignore` carries exactly one verified false positive (GHSA-w4f7-4cxr-rv3c on `gun`); do not add other advisory ids there — a real finding gets reported, never suppressed.

## Documentation

Use the existing docs instead of re-explaining patterns from scratch:

- `README.md` for package overview and top-level discovery
- `AGENTS.md` for contributor workflow and verification expectations
- `docs/guides/building_adapters.md` for adapter patterns
- `docs/guides/performance_tuning.md` for telemetry and tuning
- `docs/guides/troubleshooting_reconnection.md` for reconnect diagnostics
- `docs/guides/deployment_considerations.md` for production deployment trade-offs

## Architecture

### Module Structure
```
lib/zen_websocket/
├── client.ex               # Main client interface (GenServer + public API)
├── client/
│   ├── call_facade.ex      # Process-down-safe GenServer.call + connect await
│   ├── callbacks.ex        # handle_call/handle_info clause routing
│   ├── correlation.ex      # JSON-RPC response/timeout correlation
│   ├── connection.ex       # Gun open, upgrade, attempt-identity timers
│   ├── frames.ex           # WebSocket frame routing and dispatch
│   ├── reconnect.ex        # Explicit reconnect target and options
│   ├── recorder.ex         # Session recorder lifecycle
│   ├── retry.ex            # Disconnect retry, backoff, stop-with-error
│   ├── retry_policy.ex     # Retry eligibility and error normalization
│   └── transport_errors.ex # Gun error/down logging and retry dispatch
├── client_supervisor.ex    # DynamicSupervisor for pooled connections
├── config.ex               # Configuration struct and validation
├── frame.ex                # WebSocket frame encoding/decoding
├── connection_registry.ex  # ETS-based connection tracking
├── reconnection.ex         # Exponential backoff retry logic
├── message_handler.ex      # Message parsing and routing
├── error_handler.ex        # Error categorization and recovery
├── json_rpc.ex             # JSON-RPC 2.0 protocol support
├── request_correlator.ex   # Request/response correlation
├── rate_limiter.ex         # API rate limit management
├── heartbeat_manager.ex    # Heartbeat lifecycle
├── heartbeat_interval.ex   # Shared interval-pong telemetry + state update
├── subscription_manager.ex # Subscription tracking and restoration
├── latency_stats.ex        # Latency percentile tracking
├── pool_router.ex          # Health-based pool routing
├── recorder.ex             # Session recording (pure functions)
├── recorder_server.ex      # Async file I/O for recording
├── debug.ex                # Conditional debug logging
├── safe_callback.ex        # Crash-safe lifecycle callback wrapper
├── testing.ex              # Consumer-facing test utilities
├── testing/
│   └── server.ex           # Mock WebSocket server used by Testing
├── helpers/
│   └── deribit.ex          # Deribit helper functions
└── examples/
    └── deribit_adapter.ex  # Deribit platform integration (plus other in-tree examples)
```

### Public API
```elixir
# Connection lifecycle
ZenWebsocket.Client.connect(url, opts)
ZenWebsocket.Client.send_message(client, message)
ZenWebsocket.Client.subscribe(client, channels)
ZenWebsocket.Client.get_state(client)
ZenWebsocket.Client.close(client)
ZenWebsocket.Client.reconnect(client)

# Monitoring
ZenWebsocket.Client.get_heartbeat_health(client)
ZenWebsocket.Client.get_state_metrics(client)
ZenWebsocket.Client.get_latency_stats(client)

# Public but @doc false — used internally by ClientSupervisor.start_client/2
ZenWebsocket.Client.build_client_struct(state, pid)
```

### Project Constraints
- Maximum 5 functions per module (new modules)
- Maximum 15 lines per function
- Direct Gun API usage - no wrapper layers
- Real API testing only - zero mocks

### Example Code Policy
All examples are written and tested in-tree under `lib/zen_websocket/examples/` with matching tests in `test/`. Validate with compile, Dialyzer, Credo, and tests before considering an example done. Keep examples in this tree — a separate mix project under `examples/<name>/` was tried (R026) and reverted.
- **Executable examples**: Live in `lib/zen_websocket/examples/` without a per-file line limit
- **Packaging**: Examples and `Mix.Tasks.ZenWebsocket.*` ship in the Hex package; removing them would make existing example modules and tasks unavailable to consumers

## Configuration

### Environment Setup
```bash
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

### ZenWebsocket.Config Options
- `url` - WebSocket endpoint URL
- `headers` - Connection headers
- `timeout` - Connection timeout (default: 5000ms)
- `retry_count` - Maximum retry attempts (default: 3)
- `retry_delay` - Initial retry delay (default: 1000ms)
- `heartbeat_interval` - Ping interval (default: 30000ms)

## Testing Strategy

### Test Coverage Requirements
**When modifying any module, ensure it has both:**
1. **Unit tests** - Pure function logic, no network/I/O, fast execution
2. **Integration tests** - Real connections via MockWebSockServer or external APIs

If either is missing, create them before completing the task.

### Test Tagging
- `:integration` - Tests using MockWebSockServer, Gun, or external APIs. Excluded from default `mix test`; excluded from coverage unless paired with `:local_network`.
- `:external_network` - Tests requiring internet access. Excluded from default `mix test` and the coverage gate.
- `:local_network` - Mock-server socket tests retained in the coverage ratchet. Always paired with `:integration`, so default `mix test` still excludes them.
- Default `mix test` excludes every socket-opening test.

### Real API Testing Policy
**NO MOCKS ALLOWED** - Only real API testing:
- `test.deribit.com` for Deribit integration
- Local mock servers using `MockWebSockServer`
- Real network conditions and error scenarios

**Rationale**: Financial software requires testing against real conditions. Mocks hide edge cases that cause financial losses.

#### Narrow exceptions

Two fenced carve-outs. Everything else remains prohibited.

##### 1. Opaque Gun transport message shapes

Test doubles are permitted for **Gun transport message tuples only** — the four shapes `:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`.

**What is permitted:**
- Constructing the four Gun tuple shapes for unit-level tests of pure functions that consume them (e.g., `MessageHandler.handle_message/2`)
- Fixtures must use **real** `pid()` values (from `self()` or `spawn`) and **real** `reference()` values (from `make_ref/0`). No fake opaque values.

**Why this is not a real mock:** Gun's `pid` and `stream_ref` are opaque BEAM primitives with no public contract. There is no behavior for a fixture to drift against — only a tuple shape. Shape-only fixtures enable property-based testing of routing totality without stubbing any behavior.

##### 2. ClientSupervisor routing stand-in

A test-only GenServer that answers **only** the three `Client` calls `send_balanced/2` uses (`:send_message`, `:get_state_metrics`, `:get_latency_stats`) is permitted in `client_supervisor_send_balanced_test.exs`. `send_balanced/2` reaches candidates solely through `GenServer.call/2` on `server_pid`; the stand-in has no Gun connection, no frame handling, and no exchange semantics. It exists to drive failover and load-balancing deterministically (injected `:ok` / `{:ok, map()}` / `{:error, reason}` replies) without a live socket.

**What is permitted:**
- A `start_supervised/1` GenServer that replies to those three calls
- Injecting the exact reply `Client.send_message/2` would return

**What is NOT allowed** (either exception):
- API response fixtures (Deribit, Binance, any exchange)
- Authentication flow simulation
- Exchange behavior simulation (subscription acks, order responses, heartbeats)
- Stubbing Gun, cowboy, or WebSocket frames
- Using the routing stand-in to test `Client` GenServer state, reconnection, or message handling
- Any fixture with semantic content beyond the raw transport-frame shape or the three `send_balanced/2` call replies

**Source of truth unchanged:** `MockWebSockServer` (real cowboy/websock stack) and real-API tests remain the source of truth for all business logic. `client_supervisor_test.exs` covers `send_balanced/2` end-to-end against a real connection. Any test touching `Client` GenServer state, reconnection, subscription semantics, or exchange behavior continues to require `MockWebSockServer` or a real endpoint.

### Test Support Modules
- `MockWebSockServer` - Controlled WebSocket server (`test/support/mock_websock_server.ex`)
- `CertificateHelper` - TLS certificate generation (`test/support/certificate_helper.ex`)
- `GunStub` - Shape-only constructors for Gun transport tuples (`test/support/gun_stub.ex`)

## WebSocket Connection Architecture

### Connection Model
- WebSocket connections are Gun processes managed by `ZenWebsocket.Client`
- Connection processes monitored via `Process.monitor/1`
- Failures classified by exit reasons

### Reconnection Pattern
```elixir
{:ok, client} = ZenWebsocket.Client.connect(url, [
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  heartbeat_interval: 30000
])
```

## Platform Integration

### Deribit Adapter
Located in `lib/zen_websocket/examples/deribit_adapter.ex`:
- Authentication flow
- Subscription management
- Heartbeat/test_request handling
- JSON-RPC 2.0 formatting
- Cancel-on-disconnect protection

**Supervised Pattern (production):**
```elixir
connect_opts = [
  reconnect_on_error: false,  # Adapter handles reconnection
  heartbeat_config: %{...}
]
```

**Standalone Pattern (simple use):**
```elixir
{:ok, client} = Client.connect(url)  # reconnect_on_error: true (default)
```

## Key Dependencies

### Core Runtime
- `gun ~> 2.4` - HTTP/2 and WebSocket client (bound requires the GHSA-w4f7-4cxr-rv3c fix, not just permits it)
- `jason ~> 1.4` - JSON encoding/decoding
- `telemetry ~> 1.3` - Metrics and monitoring

### Development
- `credo`, `dialyxir`, `sobelow`, `ex_doc`, `ex_dna` (code duplication detection)

### Testing
- `cowboy ~> 2.10`, `websock ~> 0.5`, `stream_data ~> 1.0`, `x509 ~> 0.8`

## Task Management

### Roadmap
Tasks live in `roadmap/tasks.toml` and are rendered to `ROADMAP.md` by `rmap`. Use `rmap` to list, create, score, and prioritize work.

### Task ID Format
Current ids are numeric (`7`, `8`, …). Historical ids use `R0NN` (`R026`, `R052`). There is no `WNX####` scheme.

### Task Tracking
`rmap` is the substrate. Status, scores, and write-sets live in `roadmap/tasks.toml`; `ROADMAP.md` is a generated view.

Priority uses D/B/U scoring (Difficulty / Benefit / Urgency). `rmap next` selects work from those scores.

### WebSocket-Specific Requirements
- All connection tasks must include real API testing
- Platform integration tasks reference Deribit adapter patterns
- Frame handling tasks include malformed data testing
- Reconnection tasks test real network interruptions
