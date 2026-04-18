# CLAUDE.md

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/web-command.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/agent-economy.md
@~/.claude/includes/reach.md

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
- `gun ~> 2.2` - HTTP/2 and WebSocket client
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
