# ZenWebsocket Agent Guide

Guide for AI coding agents contributing to zen_websocket.

## Start Here

```bash
# Check test health
mix test.json --quiet --summary-only

# Run the explicit verification workflow from CLAUDE.md
mix dialyzer.json --quiet
mix credo --strict --format json
mix security
mix docs
```

## Project Constraints

These constraints are **non-negotiable**:

| Constraint | Limit |
|------------|-------|
| Public functions per new module | 5 max (existing core modules may exceed) |
| Lines per function | 15 max |
| Function call depth | 2 levels max |
| @spec on public functions | Required |
| Real API testing | Required (no mocks) |

## Quick Reference

| Command | Purpose |
|---------|---------|
| `mix test.json --quiet --summary-only` | Test health check |
| `mix test.json --quiet --failed --first-failure` | Fast iteration on failures |
| `mix dialyzer.json --quiet` | Type checking |
| `mix credo --strict --format json` | Static analysis |
| `mix security` | Sobelow security scan |
| `mix docs` | Generate documentation |
| `mix test --include integration` | Full test suite with integration |

## Module Overview

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `Client` | Main interface | `connect/2`, `send_message/2`, `subscribe/2`, `get_state/1`, `close/1`, `get_latency_stats/1`, `get_heartbeat_health/1`, `get_state_metrics/1`, `reconnect/1` |
| `Config` | Configuration | `new/2`, `new!/2`, `validate/1` |
| `Frame` | WebSocket frames | `text/1`, `binary/1`, `ping/0`, `pong/1`, `decode/1` |
| `Reconnection` | Retry logic | `establish_connection/1`, `build_gun_opts/1`, `calculate_backoff/3`, `should_reconnect?/1`, `max_retries_exceeded?/2` |
| `MessageHandler` | Message routing | `handle_message/2`, `decode_and_handle_control/1`, `create_handler/1` |
| `ErrorHandler` | Error categorization | `categorize_error/1`, `recoverable?/1`, `handle_error/1`, `explain/1` |
| `RateLimiter` | Token bucket | `init/2`, `consume/2`, `refill/1`, `status/1`, `shutdown/1` |
| `JsonRpc` | JSON-RPC 2.0 | `build_request/2`, `match_response/1` |
| `HeartbeatManager` | Heartbeat lifecycle | `start_timer/1`, `cancel_timer/1`, `handle_message/2`, `send_heartbeat/1`, `get_health/1` |
| `SubscriptionManager` | Subscription tracking | `add/2`, `remove/2`, `list/1`, `build_restore_message/1`, `handle_message/2` |
| `RequestCorrelator` | Request/response tracking | `extract_id/1`, `track/4`, `resolve/2`, `timeout/2`, `pending_count/1` |
| `Recorder` | Session recording | `format_entry/3`, `parse_entry/1`, `replay/3`, `metadata/1` |
| `RecorderServer` | Async file I/O | `start_link/1`, `record/3`, `flush/1`, `stop/1`, `stats/1` |
| `Testing` | Test utilities | `start_mock_server/1`, `stop_server/1`, `inject_message/2`, `assert_message_sent/3`, `simulate_disconnect/2` |
| `ClientSupervisor` | Pool management | `start_client/2`, `send_balanced/2`, `list_clients/0`, `stop_client/1` |
| `PoolRouter` | Health-based routing | `select_connection/1`, `calculate_health/1`, `record_error/1`, `clear_errors/1`, `pool_health/1` |
| `LatencyStats` | Latency metrics | `new/1`, `add/2`, `percentile/2`, `summary/1` |
| `ConnectionRegistry` | ETS connection tracking | `init/0`, `register/2`, `deregister/1`, `get/1`, `cleanup_dead/1`, `shutdown/0` |
| `Debug` | Debug logging | `log/2` |

## Testing Strategy

### Unit Tests (Default)
- Pure function logic, no network
- Run with `mix test.json --quiet --summary-only`
- Located in `test/zen_websocket/`

### Integration Tests
- Use `ZenWebsocket.Testing` module for controlled tests
- Tag with `@tag :integration`
- Run with `mix test --include integration`

### External Network Tests
- Real endpoints (Deribit testnet, etc.)
- Tag with `@tag :external_network`
- Require credentials in environment

### Mocking Policy

Real-API and `MockWebSockServer` coverage are the source of truth for all business logic. One narrow, fenced exception applies: opaque Gun transport message tuples (`:gun_upgrade`, `:gun_ws`, `:gun_down`, `:gun_error`) may be constructed as shape-only fixtures using real pids and refs, because they carry no public behavior for a fixture to drift against. Full rationale and the explicit "what is NOT newly allowed" list live in CLAUDE.md → Real API Testing Policy → Narrow exception.

```elixir
# Unit test example
test "text frame round-trip" do
  frame = Frame.text("hello")
  assert {:ok, {:text, "hello"}} = Frame.decode(frame)
end

# Integration test example
@tag :integration
test "client sends to mock server" do
  {:ok, server} = Testing.start_mock_server()
  {:ok, client} = Client.connect(server.url)
  Client.send_message(client, "hello")
  assert Testing.assert_message_sent(server, "hello", 1000)
  Testing.stop_server(server)
end
```

## Common Patterns

### Adding a Config Option

1. Add field to Config struct with `@default_*` constant
2. Handle in Config.new/2 with validation
3. Add typespec
4. Document in `@moduledoc`
5. Add test for valid and invalid values

### Adding a Telemetry Event

1. Emit with `:telemetry.execute/3`
2. Use namespace `[:zen_websocket, :module, :event]`
3. Include measurements map and metadata map
4. Document in module `@moduledoc`
5. Add to Performance Tuning Guide table

### Writing Tests with Testing Module

```elixir
alias ZenWebsocket.Testing

setup do
  {:ok, server} = Testing.start_mock_server()
  on_exit(fn -> Testing.stop_server(server) end)
  {:ok, server: server}
end

test "example", %{server: server} do
  {:ok, client} = Client.connect(server.url)

  # Inject server -> client message
  Testing.inject_message(server, ~s({"type": "hello"}))

  # Assert client -> server message
  assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

  # Simulate disconnect
  Testing.simulate_disconnect(server, :going_away)
end
```

## Example Code Policy

**Non-negotiable workflow for all examples:**

1. **Write in lib/test first** - All example code starts in `lib/` with tests in `test/`
2. **Full validation required** - Must compile, pass Dialyzer, pass Credo, have tests
3. **Then decide location** - After validation, determine final home

**Where examples live:**

All examples live in `lib/zen_websocket/examples/`. This includes both small patterns and full adapters (like the Deribit adapter). Separate mix projects were tried (R026) but abandoned due to ergonomic costs (broken Tidewave, stale doc references).

**Current example files:**
- `deribit_adapter.ex` — Non-GenServer Deribit integration
- `deribit_genserver_adapter.ex` — GenServer-based Deribit adapter
- `deribit_rpc.ex` — JSON-RPC helpers for Deribit
- `batch_subscription_manager.ex` — Batch subscription patterns
- `adapter_supervisor.ex` — Adapter supervision patterns
- `supervised_client.ex` — Supervised client usage
- `platform_adapter_template.ex` — Template for new adapters
- `usage_patterns.ex` — Common usage patterns
- `docs/` — Examples from documentation (basic_usage, error_handling, json_rpc_client, subscription_management)

## DO NOT

| Anti-Pattern | Why |
|--------------|-----|
| Create wrapper modules | Use the Client functions directly |
| Mock WebSocket behavior (except opaque Gun transport message shapes — see CLAUDE.md) | Test against real APIs or Testing module |
| Add custom reconnection | Use built-in retry options |
| Transform errors | Pass raw Gun/WebSocket errors |
| Exceed function limits | Extract to new module instead |
| Skip @spec annotations | Required for all public functions |
| Use magic numbers | Define as module attributes |

## Debugging

### Enable Debug Logging
```elixir
{:ok, client} = Client.connect(url, debug: true)
```

### Session Recording
```elixir
{:ok, client} = Client.connect(url, record_to: "/tmp/debug.jsonl")
# ... use connection ...
Client.close(client)

# Analyze
{:ok, meta} = Recorder.metadata("/tmp/debug.jsonl")
Recorder.replay("/tmp/debug.jsonl", &IO.inspect/1)
```

### State Inspection
```elixir
# Latency stats
Client.get_latency_stats(client)

# Heartbeat health
Client.get_heartbeat_health(client)

# Connection metrics
Client.get_state_metrics(client)

# Rate limiter pressure
RateLimiter.status(limiter)
```

## Roadmap Integration

See `ROADMAP.md` in the repository for:
- Current focus and active tasks
- Backlog with priority scores (D/B ratio)
- Blocked/deferred tasks

### Task ID Format
- Core: `WNX0001-WNX0099`
- Features: `WNX0100-WNX0199`
- Docs: `WNX0200-WNX0299`
- Tests: `WNX0300-WNX0399`
- Roadmap tasks: `R001-R099`

### Before Starting a Task

1. Check ROADMAP.md for current status
2. Update task status to `🔄` with branch name
3. Run `mix test.json --quiet --summary-only` to verify starting state
4. Create branch if doing parallel work

### After Completing a Task

1. Run `mix test.json --quiet --summary-only`
2. Run `mix dialyzer.json --quiet`
3. Run `mix credo --strict --format json`
4. Run `mix security`
5. Run `mix docs`
6. Update ROADMAP.md status to `✅`
7. Add entry to CHANGELOG.md under `[Unreleased]`
8. Commit with task ID in message

## File Organization

```
lib/zen_websocket/
├── client.ex              # Main interface (connect, send, subscribe, close, monitoring)
├── client_supervisor.ex   # DynamicSupervisor + pool management
├── config.ex              # Configuration struct and validation
├── connection_registry.ex # ETS connection tracking
├── debug.ex               # Debug logging utility
├── error_handler.ex       # Error categorization and recovery
├── frame.ex               # WebSocket frame encoding/decoding
├── heartbeat_manager.ex   # Heartbeat lifecycle management
├── json_rpc.ex            # JSON-RPC 2.0 protocol support
├── latency_stats.ex       # Circular buffer latency metrics
├── message_handler.ex     # Message parsing and routing
├── pool_router.ex         # Health-based connection routing
├── rate_limiter.ex        # Token bucket rate limiting
├── reconnection.ex        # Exponential backoff retry logic
├── recorder.ex            # Session recording (pure functions)
├── recorder_server.ex     # Async file I/O for recording
├── request_correlator.ex  # Request/response correlation
├── subscription_manager.ex # Subscription tracking and restoration
├── testing.ex             # Consumer-facing test utilities
├── testing/
│   └── server.ex          # Mock WebSocket server implementation
├── helpers/
│   └── deribit.ex         # Deribit platform support
└── examples/
    ├── deribit_adapter.ex           # Deribit adapter (non-GenServer)
    ├── deribit_genserver_adapter.ex  # Deribit adapter (GenServer)
    ├── deribit_rpc.ex               # Deribit JSON-RPC helpers
    ├── batch_subscription_manager.ex # Batch subscription patterns
    ├── adapter_supervisor.ex         # Adapter supervision
    ├── supervised_client.ex          # Supervised client usage
    ├── platform_adapter_template.ex  # Template for new adapters
    ├── usage_patterns.ex             # Common patterns
    └── docs/                         # Documentation examples
```

## Key Documentation

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project principles and commands |
| `USAGE_RULES.md` | API usage patterns |
| `ROADMAP.md` | Task tracking and priorities |
| `CHANGELOG.md` | Version history |
| `docs/guides/building_adapters.md` | Adapter patterns |
| `docs/guides/deployment_considerations.md` | Production deployment trade-offs for trading applications |
| `docs/guides/performance_tuning.md` | Telemetry and tuning |
