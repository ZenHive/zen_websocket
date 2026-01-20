# ZenWebsocket Usage Rules

<!-- This file follows the usage_rules convention for AI agents and developers -->

## Core Principles

1. **Start Simple**: Use direct connection for development, add supervision for production
2. **Only 5 Functions**: The entire public API is just 5 functions
3. **Real API Testing**: Always test against real endpoints, never mock WebSocket behavior

## Quick Start Pattern

```elixir
# Simplest possible usage - connect and send
{:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")
ZenWebsocket.Client.send_message(client, Jason.encode!(%{method: "public/test"}))
```

## The 5 Essential Functions

```elixir
# 1. Connect to WebSocket
{:ok, client} = ZenWebsocket.Client.connect(url, opts)

# 2. Send messages
:ok = ZenWebsocket.Client.send_message(client, message)

# 3. Subscribe to channels
{:ok, subscription_id} = ZenWebsocket.Client.subscribe(client, channels)

# 4. Check connection state
state = ZenWebsocket.Client.get_state(client)  # :connected, :connecting, :disconnected

# 5. Close connection
:ok = ZenWebsocket.Client.close(client)
```

## Common Patterns

### Pattern 1: Development/Testing (No Supervision)
```elixir
# Direct connection - crashes won't restart
{:ok, client} = ZenWebsocket.Client.connect(url)
# Use the client...
ZenWebsocket.Client.close(client)
```

### Pattern 2: Production with Dynamic Connections
```elixir
# Add to your supervision tree
children = [
  ZenWebsocket.ClientSupervisor,
  # ... other children
]

# Start connections dynamically
{:ok, client} = ZenWebsocket.ClientSupervisor.start_client(url, opts)
```

### Pattern 3: Production with Fixed Connections
```elixir
# Add specific clients to supervision tree
children = [
  {ZenWebsocket.Client, [
    url: "wss://api.example.com/ws",
    id: :main_websocket,
    heartbeat_config: %{type: :ping, interval: 30_000}
  ]}
]
```

## Configuration Options

```elixir
opts = [
  # Connection
  timeout: 5000,              # Connection timeout in ms
  headers: [],                # Additional headers
  debug: false,               # Enable verbose debug logging

  # Reconnection
  retry_count: 3,             # Max reconnection attempts
  retry_delay: 1000,          # Initial retry delay (exponential backoff)
  reconnect_on_error: true,   # Auto-reconnect on errors
  restore_subscriptions: true, # Restore subscriptions after reconnect

  # Heartbeat
  heartbeat_config: %{
    type: :ping,              # :ping, :pong, :deribit, :custom
    interval: 30_000,         # Heartbeat interval in ms
    message: nil              # Custom heartbeat message (for :custom type)
  },

  # Session Recording
  record_to: "/tmp/session.jsonl",  # Enable message recording (nil to disable)

  # Latency Monitoring
  latency_buffer_size: 100    # Samples for p50/p99 calculations
]
```

## Session Recording

Record WebSocket sessions for debugging, testing, and replay:

```elixir
# Enable recording when connecting
{:ok, client} = ZenWebsocket.Client.connect(url, record_to: "/tmp/debug.jsonl")

# Use the connection normally - all messages are recorded
ZenWebsocket.Client.send_message(client, %{action: "subscribe", channel: "trades"})

# Close to flush remaining buffer
ZenWebsocket.Client.close(client)

# Get session metadata (count, duration, timestamps)
{:ok, meta} = ZenWebsocket.Recorder.metadata("/tmp/debug.jsonl")
# => %{count: 42, inbound: 30, outbound: 12, duration_ms: 5000, ...}

# Replay the recorded session
ZenWebsocket.Recorder.replay("/tmp/debug.jsonl", fn entry ->
  IO.inspect(entry, label: "#{entry.dir} at #{entry.ts}")
end)
```

**Recording format:** JSONL (one JSON object per line) for streaming writes. Binary frames are base64-encoded.

## Platform-Specific Rules

### Deribit Integration
```elixir
# Use the Deribit adapter for complete integration
{:ok, adapter} = ZenWebsocket.Examples.DeribitAdapter.start_link([
  url: "wss://test.deribit.com/ws/api/v2",
  client_id: System.get_env("DERIBIT_CLIENT_ID"),
  client_secret: System.get_env("DERIBIT_CLIENT_SECRET")
])

# The adapter handles:
# - Authentication flow
# - Heartbeat/test_request
# - Subscription management
# - Cancel-on-disconnect
```

## Error Handling

```elixir
# All functions return tagged tuples
case ZenWebsocket.Client.connect(url) do
  {:ok, client} ->
    # Success path
    client

  {:error, reason} ->
    # Get human-readable explanation with fix suggestion
    explanation = ZenWebsocket.ErrorHandler.explain(reason)
    Logger.error("#{explanation.message}. #{explanation.suggestion}")
    # Errors are passed raw from Gun/WebSocket
    # Common errors: :timeout, :connection_refused, :protocol_error
end
```

## Testing Rules

```elixir
# Use the Testing module for controlled tests
alias ZenWebsocket.Testing

# Start a mock server
{:ok, server} = Testing.start_mock_server()
{:ok, client} = ZenWebsocket.Client.connect(server.url)

# Inject messages from server to client
Testing.inject_message(server, ~s({"type": "hello"}))

# Assert client sent expected message (supports string, regex, map, or function matchers)
assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

# Simulate disconnects for error handling tests
Testing.simulate_disconnect(server, :going_away)

# Cleanup
Testing.stop_server(server)
```

### ExUnit Integration Pattern
```elixir
defmodule MyTest do
  use ExUnit.Case
  alias ZenWebsocket.Testing

  setup do
    {:ok, server} = Testing.start_mock_server()
    on_exit(fn -> Testing.stop_server(server) end)
    {:ok, server: server}
  end

  test "client handles server message", %{server: server} do
    {:ok, client} = ZenWebsocket.Client.connect(server.url)
    Testing.inject_message(server, ~s({"type": "pong"}))
    assert_receive {:websocket_message, _}, 1000
    ZenWebsocket.Client.close(client)
  end
end
```

### Real API Testing
```elixir
# For integration tests against real endpoints
@tag :integration
test "real WebSocket behavior" do
  {:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")
  # Test against real API...
end
```

## DO NOT

1. **Don't create wrapper modules** - Use the 5 functions directly
2. **Don't mock WebSocket behavior** - Test against real endpoints or use Testing module
3. **Don't add custom reconnection** - Use built-in retry options
4. **Don't transform errors** - Handle raw Gun/WebSocket errors
5. **Don't avoid GenServers** - Client uses GenServer appropriately for state

## Architecture Notes

- **Gun Transport**: Built on Gun for HTTP/2 and WebSocket
- **GenServer State**: Client maintains connection state in GenServer
- **ETS Registry**: Fast connection lookups via ETS
- **Exponential Backoff**: Smart reconnection with backoff
- **Real API Testing**: 395 tests, all using real APIs or Testing module

## Monitoring and Observability

### Latency Statistics
```elixir
# Get latency metrics (p50/p99/last/count)
stats = ZenWebsocket.Client.get_latency_stats(client)
# => %{p50: 12.5, p99: 45.2, last: 10.0, count: 100}
```

### Heartbeat Health
```elixir
# Check heartbeat status
health = ZenWebsocket.Client.get_heartbeat_health(client)
# => %{failures: 0, last_at: ~U[2026-01-20 10:30:00Z]}
```

### State Metrics
```elixir
# Get connection state metrics
metrics = ZenWebsocket.Client.get_state_metrics(client)
# => %{pending_requests: 5, subscriptions: 12, memory_bytes: 1024}
```

### Rate Limiter Status
```elixir
# Check rate limiter pressure
status = ZenWebsocket.RateLimiter.status(limiter)
# => %{tokens: 85, capacity: 100, pressure_level: :low, suggested_delay_ms: 0}
# pressure_level: :low (<25%), :medium (25-50%), :high (50-75%), :critical (>75%)
```

### Key Telemetry Events

| Event | Measurements | When |
|-------|--------------|------|
| `[:zen_websocket, :client, :message_received]` | `size` | Message received |
| `[:zen_websocket, :connection, :upgrade]` | `connect_time_ms` | WebSocket upgrade complete |
| `[:zen_websocket, :heartbeat, :pong]` | `rtt_ms` | Heartbeat response received |
| `[:zen_websocket, :rate_limiter, :pressure]` | `level`, `queue_size` | Pressure threshold crossed |

See [Performance Tuning Guide](docs/guides/performance_tuning.md) for complete telemetry reference.

```elixir
# Attach to telemetry events
:telemetry.attach(
  "websocket-logger",
  [:zen_websocket, :client, :message_received],
  fn _event, measurements, metadata, _config ->
    Logger.info("Message received: #{measurements.size} bytes")
  end,
  nil
)
```

## Module Limits

Each module follows strict simplicity rules:
- Maximum 5 public functions per module
- Maximum 15 lines per function
- Maximum 2 levels of function calls
- Real API testing only (no mocks)

## Getting Help

- **Examples**: See `lib/zen_websocket/examples/` directory
- **Tests**: Review `test/` for usage patterns
- **Deribit**: See `DeribitAdapter` for complete platform integration
- **Guides**: See `docs/guides/` for performance tuning and adapter building

## Common Mistakes to Avoid

1. **Creating abstractions too early** - Start with direct usage
2. **Mocking in tests** - Always use real WebSocket endpoints or Testing module
3. **Custom error types** - Handle raw Gun/WebSocket errors
4. **Complex supervision** - Use provided patterns (1, 2, or 3)
5. **Ignoring heartbeats** - Configure heartbeat for production

## Migration from Other Libraries

### From Websockex
```elixir
# Old (Websockex with callbacks)
defmodule MyClient do
  use WebSockex
  def handle_frame({:text, msg}, state), do: {:ok, state}
end

# New (ZenWebsocket - simpler)
{:ok, client} = ZenWebsocket.Client.connect(url)
# Messages handled via message_handler configuration
```

### From Gun directly
```elixir
# You're already using the right approach!
# ZenWebsocket is a thin, focused layer over Gun
```

## Performance Characteristics

- **Connection Time**: < 100ms typical
- **Message Latency**: < 1ms processing
- **Memory**: ~50KB per connection
- **Reconnection**: Exponential backoff (1s, 2s, 4s...)
- **Concurrency**: Thousands of simultaneous connections

## Required Environment Variables

For platform integrations:
```bash
# Deribit
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

## Best Practices Summary

1. Start with Pattern 1 (direct) for development
2. Move to Pattern 2 or 3 for production
3. Configure heartbeats for long-lived connections
4. Test against real endpoints or use Testing module
5. Handle raw errors with pattern matching
6. Use telemetry for monitoring
7. Enable `record_to` for debugging production issues
8. Keep it simple - just 5 functions!
