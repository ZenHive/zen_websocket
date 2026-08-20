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

**ZenWebsocket** is a robust WebSocket client library for Elixir, specifically designed for financial APIs (particularly Deribit cryptocurrency trading). Built on Gun transport with 8 foundation modules, enhanced with critical financial infrastructure.

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
mix test --include integration         # Include integration tests
mix test.api              # Real API integration tests
mix test.api --deribit    # Deribit-specific tests
mix test.performance      # Performance/stress testing
```

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Canonical gate:** `mix precommit.full` (alias `mix ci`) — the comprehensive pass the harness reviewer's `check_command` runs and what GitHub CI (`.github/workflows/harness.yml`) invokes directly. Fast local loop: `mix precommit` (skips the cold-PLT dialyzer + deps audit).
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 58 --exclude integration` (`MIX_ENV=test`), `dialyzer` (forced `MIX_ENV=dev` — see below), `agents.check`.
- **The coverage floor is a measured ratchet, not an aspiration.** 58 is the non-integration coverage measured 2026-08-01, rounded down; the previous 80 had never been met by any run and so gated nothing. Raise it in lockstep with real coverage; never pad it.
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
├── client.ex              # Main client interface (5 public functions)
├── config.ex              # Configuration struct and validation
├── frame.ex               # WebSocket frame encoding/decoding
├── connection_registry.ex # ETS-based connection tracking
├── reconnection.ex        # Exponential backoff retry logic
├── message_handler.ex     # Message parsing and routing
├── error_handler.ex       # Error categorization and recovery
├── json_rpc.ex           # JSON-RPC 2.0 protocol support
├── correlation_manager.ex # Request/response correlation
├── rate_limiter.ex        # API rate limit management
└── examples/
    └── deribit_adapter.ex # Deribit platform integration
```

### Public API (5 Functions)
```elixir
ZenWebsocket.Client.connect(url, opts)
ZenWebsocket.Client.send_message(client, message)
ZenWebsocket.Client.close(client)
ZenWebsocket.Client.subscribe(client, channels)
ZenWebsocket.Client.get_state(client)
```

### Project Constraints
- Maximum 5 functions per module (new modules)
- Maximum 15 lines per function
- Direct Gun API usage - no wrapper layers
- Real API testing only - zero mocks

### Example Code Policy
**Non-negotiable:** All examples must be written and tested in `lib/` and `test/` first, with full validation (compile, Dialyzer, Credo, tests). After validation:
- **Small patterns** (< 50 lines): Stay in `lib/zen_websocket/examples/`
- **Large applications**: Move to `examples/<name>/` as separate mix project

See AGENTS.md for full policy details.

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
- `:integration` - Tests using MockWebSockServer or external services
- `:external_network` - Tests requiring internet (Deribit testnet, etc.)
- Default `mix test` excludes these for fast feedback

### Real API Testing Policy
**NO MOCKS ALLOWED** - Only real API testing:
- `test.deribit.com` for Deribit integration
- Local mock servers using `MockWebSockServer`
- Real network conditions and error scenarios

**Rationale**: Financial software requires testing against real conditions. Mocks hide edge cases that cause financial losses.

#### Narrow exception: opaque transport message shapes

Test doubles are permitted for **Gun transport message tuples only** — the four shapes `:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`. This is a single, fenced carve-out; all other forms of mocking remain prohibited.

**What is permitted:**
- Constructing the four Gun tuple shapes for unit-level tests of pure functions that consume them (e.g., `MessageHandler.handle_message/2`)
- Fixtures must use **real** `pid()` values (from `self()` or `spawn`) and **real** `reference()` values (from `make_ref/0`). No fake opaque values.

**Why this is not a real mock:** Gun's `pid` and `stream_ref` are opaque BEAM primitives with no public contract. There is no behavior for a fixture to drift against — only a tuple shape. Shape-only fixtures enable property-based testing of routing totality without stubbing any behavior.

**What is NOT newly allowed** (explicit, to prevent drift):
- API response fixtures (Deribit, Binance, any exchange)
- Authentication flow simulation
- Exchange behavior simulation (subscription acks, order responses, heartbeats)
- Any fixture with semantic content beyond the raw transport-frame shape
- Fixtures for anything that is not one of the four Gun tuple shapes

**Source of truth unchanged:** `MockWebSockServer` (real cowboy/websock stack) and real-API tests remain the source of truth for all business logic. Any test touching `Client` GenServer state, reconnection, subscription semantics, or exchange behavior continues to require `MockWebSockServer` or a real endpoint.

### Test Support Modules
- `MockWebSockServer` - Controlled WebSocket server
- `CertificateHelper` - TLS certificate generation
- `NetworkSimulator` - Network condition simulation
- `TestEnvironment` - Environment management

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
See [roadmap.md](roadmap.md) for:
- Current focus and active tasks
- Prioritized task list with D/B scoring
- Completed work history

### Task ID Format
Use `WNX####` format:
- Core: WNX0001-WNX0099
- Features: WNX0100-WNX0199
- Docs: WNX0200-WNX0299
- Tests: WNX0300-WNX0399

### Task Tracking
Tasks tracked in [roadmap.md](roadmap.md) with status markers:
- ⬜ Pending
- 🔄 In progress
- ✅ Complete

Priority uses D/B scoring (Difficulty/Benefit ratio).

### WebSocket-Specific Requirements
- All connection tasks must include real API testing
- Platform integration tasks reference Deribit adapter patterns
- Frame handling tasks include malformed data testing
- Reconnection tasks test real network interruptions
