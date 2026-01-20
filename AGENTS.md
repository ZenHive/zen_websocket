# ZenWebsocket Agent Guide

Guide for AI coding agents contributing to zen_websocket.

## Start Here

```bash
# Check test health
mix test.json --quiet --summary-only

# Run all quality checks before making changes
mix check
```

## Project Constraints

These constraints are **non-negotiable**:

| Constraint | Limit |
|------------|-------|
| Public functions per module | 5 max |
| Lines per function | 15 max |
| Function call depth | 2 levels max |
| @spec on public functions | Required |
| Real API testing | Required (no mocks) |

## Quick Reference

| Command | Purpose |
|---------|---------|
| `mix test.json --quiet --summary-only` | Test health check |
| `mix test.json --quiet --failed --first-failure` | Fast iteration on failures |
| `mix check` | All quality checks |
| `mix lint` | Credo strict mode |
| `mix typecheck` | Dialyzer |
| `mix docs` | Generate documentation |
| `mix test --include integration` | Full test suite with integration |

## Module Overview

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `Client` | Main interface | `connect/2`, `send_message/2`, `subscribe/2`, `get_state/1`, `close/1` |
| `Config` | Configuration | `new/2`, `new!/2`, `validate/1` |
| `Frame` | WebSocket frames | `encode/1`, `decode/1` |
| `Reconnection` | Retry logic | `calculate_delay/2`, `should_reconnect?/2` |
| `MessageHandler` | Message routing | `handle/2`, `route/2` |
| `ErrorHandler` | Error categorization | `categorize/1`, `explain/1` |
| `RateLimiter` | Token bucket | `new/2`, `check/2`, `consume/2`, `status/1` |
| `JsonRpc` | JSON-RPC 2.0 | `encode/3`, `decode/1`, `is_response?/1` |
| `HeartbeatManager` | Heartbeat lifecycle | `new/1`, `start/1`, `handle_response/2` |
| `SubscriptionManager` | Subscription tracking | `add/2`, `remove/2`, `restore/1` |
| `RequestCorrelator` | Request/response tracking | `track/3`, `resolve/2`, `timeout/2` |
| `Recorder` | Session recording | `format_entry/3`, `replay/3`, `metadata/1` |
| `RecorderServer` | Async file I/O | `start_link/1`, `record/3`, `stats/1` |
| `Testing` | Test utilities | `start_mock_server/0`, `inject_message/2`, `assert_message_sent/3` |

## Testing Strategy

### Unit Tests (Default)
- Pure function logic, no network
- Run with `mix test` or `mix test.json --quiet --summary-only`
- Located in `test/zen_websocket/`

### Integration Tests
- Use `ZenWebsocket.Testing` module for controlled tests
- Tag with `@tag :integration`
- Run with `mix test --include integration`

### External Network Tests
- Real endpoints (Deribit testnet, etc.)
- Tag with `@tag :external_network`
- Require credentials in environment

```elixir
# Unit test example
test "encode/decode round-trip" do
  frame = %{type: :text, payload: "hello"}
  assert frame == Frame.decode(Frame.encode(frame))
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

## DO NOT

| Anti-Pattern | Why |
|--------------|-----|
| Create wrapper modules | Use the 5 functions directly |
| Mock WebSocket behavior | Test against real APIs or Testing module |
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
3. Run `mix check` to verify starting state
4. Create branch if doing parallel work

### After Completing a Task

1. Run `mix check` - all must pass
2. Update ROADMAP.md status to `✅`
3. Add entry to CHANGELOG.md under `[Unreleased]`
4. Commit with task ID in message

## File Organization

```
lib/zen_websocket/
├── client.ex              # Main interface (5 functions)
├── config.ex              # Configuration struct
├── frame.ex               # Frame encoding/decoding
├── connection_registry.ex # ETS connection tracking
├── reconnection.ex        # Retry logic
├── message_handler.ex     # Message routing
├── error_handler.ex       # Error categorization
├── json_rpc.ex           # JSON-RPC 2.0
├── correlation_manager.ex # Request correlation
├── rate_limiter.ex        # Token bucket
├── heartbeat_manager.ex   # Heartbeat lifecycle
├── subscription_manager.ex # Subscription tracking
├── request_correlator.ex  # Request/response tracking
├── latency_stats.ex       # Latency metrics
├── recorder.ex            # Session recording (pure)
├── recorder_server.ex     # Async file I/O
├── testing.ex             # Test utilities
├── testing/
│   └── server.ex          # Mock server wrapper
└── examples/
    └── deribit_adapter.ex # Platform integration example
```

## Key Documentation

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project principles and commands |
| `USAGE_RULES.md` | API usage patterns |
| `ROADMAP.md` | Task tracking and priorities |
| `CHANGELOG.md` | Version history |
| `docs/guides/building_adapters.md` | Adapter patterns |
| `docs/guides/performance_tuning.md` | Telemetry and tuning |
