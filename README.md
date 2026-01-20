# ZenWebsocket

[![Hex.pm](https://img.shields.io/hexpm/v/zen_websocket.svg)](https://hex.pm/packages/zen_websocket)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/zen_websocket)
[![License](https://img.shields.io/hexpm/l/zen_websocket.svg)](https://github.com/ZenHive/zen_websocket/blob/main/LICENSE)

A robust WebSocket client library for Elixir, built on Gun transport for production-grade reliability. Designed for financial APIs with automatic reconnection, comprehensive error handling, and real-world testing.

## Features

- **Gun Transport** - Battle-tested HTTP/2 and WebSocket client
- **Automatic Reconnection** - Exponential backoff with state preservation
- **Financial-Grade Reliability** - Built for high-frequency trading systems
- **Platform Adapters** - Ready-to-use Deribit integration, extensible for others
- **Real API Testing** - No mocks, tested against live systems
- **Simple API** - Only 5 public functions to learn
- **Comprehensive Error Handling** - Categorized errors with recovery strategies
- **Rate Limiting** - Configurable token bucket algorithm
- **JSON-RPC 2.0** - Full protocol support with correlation tracking
- **Pool Load Balancing** - Health-based routing with automatic failover
- **Session Recording** - JSONL message recording for debugging and replay
- **Test Utilities** - Consumer-facing test helpers with mock server

## Installation

Add `zen_websocket` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zen_websocket, "~> 0.1"}
  ]
end
```

## Quick Start

### Basic Connection

```elixir
# Connect to a WebSocket endpoint (use your actual endpoint)
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws", [
  timeout: 5000,
  heartbeat_interval: 30000
])

# Send a message
{:ok, _} = ZenWebsocket.Client.send_message(client, %{action: "ping"})

# Receive messages in your process
receive do
  {:websocket_message, message} ->
    # Process the incoming message
    handle_message(message)
after
  5_000 -> {:error, :timeout}
end

# Close the connection
:ok = ZenWebsocket.Client.close(client)
```

### Subscription Management

ZenWebsocket tracks channel subscriptions and automatically restores them after reconnection:

```elixir
# Subscribe to channels
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws")
:ok = ZenWebsocket.Client.subscribe(client, ["ticker.BTC", "trades.BTC"])

# Subscriptions are automatically tracked when confirmations arrive
# On reconnect, tracked subscriptions are restored automatically
```

**What the library handles:**
- Tracking confirmed subscriptions via `SubscriptionManager`
- Automatic restoration after reconnection (when `restore_subscriptions: true`, the default)
- Building restore messages in the correct format

**What your client needs to handle:**
- Processing subscription data messages (sent to your handler callback)
- Unsubscription logic (call your API's unsubscribe method, then the library removes from tracking)
- Authentication before subscribing to private channels

**Configuration:**

```elixir
# Disable automatic subscription restoration
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws",
  restore_subscriptions: false
)
```

For more detailed examples, see our working examples with fully tested implementations:
- **Basic Usage** - Connection management and messaging
- **Error Handling** - Robust error recovery patterns  
- **JSON-RPC Client** - JSON-RPC 2.0 protocol usage
- **Subscription Management** - Channel subscription patterns

See the [Examples Guide](https://hexdocs.pm/zen_websocket/Examples.html) for complete code samples and usage patterns.

### Session Recording

Record WebSocket sessions for debugging and replay:

```elixir
# Enable recording when connecting
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws",
  record_to: "/tmp/session.jsonl"
)

# Use the connection normally - all messages are recorded
ZenWebsocket.Client.send_message(client, %{action: "subscribe", channel: "trades"})

# Close to flush remaining buffer
ZenWebsocket.Client.close(client)

# Replay the recorded session
ZenWebsocket.Recorder.replay("/tmp/session.jsonl", fn entry ->
  IO.inspect(entry, label: "#{entry.dir} at #{entry.ts}")
end)

# Get session metadata
{:ok, meta} = ZenWebsocket.Recorder.metadata("/tmp/session.jsonl")
# => %{count: 42, inbound: 30, outbound: 12, duration_ms: 5000, ...}
```

### Connection Pool Load Balancing

Route messages to the healthiest connection in a pool:

```elixir
# Start the supervisor in your application
{:ok, _} = ZenWebsocket.ClientSupervisor.start_link([])

# Create multiple supervised connections
{:ok, _client1} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws")
{:ok, _client2} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws")
{:ok, _client3} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws")

# Send messages with automatic load balancing
# Routes to healthiest connection based on: pending requests, latency, errors
:ok = ZenWebsocket.ClientSupervisor.send_balanced(message)

# Automatic failover on connection failure (max 3 attempts by default)
:ok = ZenWebsocket.ClientSupervisor.send_balanced(message, max_attempts: 5)

# Check pool health
health = ZenWebsocket.PoolRouter.pool_health(ZenWebsocket.ClientSupervisor.list_clients())
# => [%{pid: #PID<0.123.0>, health: 95}, %{pid: #PID<0.124.0>, health: 87}, ...]
```

### Deribit Integration

```elixir
# Configure Deribit credentials
config = %{
  client_id: System.get_env("DERIBIT_CLIENT_ID"),
  client_secret: System.get_env("DERIBIT_CLIENT_SECRET"),
  test_mode: true
}

# Start the supervised adapter
{:ok, adapter} = ZenWebsocket.Examples.DeribitGenServerAdapter.start_link(config)

# Subscribe to market data
{:ok, _} = ZenWebsocket.Examples.DeribitGenServerAdapter.subscribe(
  adapter,
  ["book.BTC-PERPETUAL.raw", "trades.BTC-PERPETUAL.raw"]
)

# Send a custom JSON-RPC request (e.g., place an order)
{:ok, response} = ZenWebsocket.Examples.DeribitGenServerAdapter.send_request(
  adapter,
  "private/buy",
  %{
    instrument_name: "BTC-PERPETUAL",
    amount: 10,
    type: "limit",
    price: 50000
  }
)
```

## Architecture

ZenWebsocket follows a modular architecture with clear separation of concerns:

```
ZenWebsocket.Client              # Main client interface
ZenWebsocket.Config              # Configuration management
ZenWebsocket.Frame               # WebSocket frame handling
ZenWebsocket.Reconnection        # Automatic reconnection logic
ZenWebsocket.MessageHandler      # Message parsing and routing
ZenWebsocket.ErrorHandler        # Error categorization
ZenWebsocket.RateLimiter         # API rate limiting
ZenWebsocket.JsonRpc             # JSON-RPC 2.0 protocol
ZenWebsocket.HeartbeatManager    # Heartbeat lifecycle management
ZenWebsocket.SubscriptionManager # Subscription tracking and restoration
ZenWebsocket.RequestCorrelator   # Request/response correlation tracking
ZenWebsocket.Recorder            # Session recording (pure functions)
ZenWebsocket.RecorderServer      # Async file I/O for recording
ZenWebsocket.PoolRouter          # Health-based connection pool routing
ZenWebsocket.Testing             # Consumer-facing test utilities
```

## Platform Integration

The library includes a complete Deribit adapter as a reference implementation. To integrate with other platforms:

1. Create an adapter module following the Deribit pattern
2. Implement platform-specific authentication
3. Handle platform message formats
4. Add comprehensive tests against the real API

See `lib/zen_websocket/examples/deribit_adapter.ex` for a complete example.

## Documentation

Comprehensive guides are available in the `docs/guides/` directory:

| Guide | Description |
|-------|-------------|
| [Building Adapters](docs/guides/building_adapters.md) | Create platform adapters with heartbeat, auth, and reconnection patterns |
| [Performance Tuning](docs/guides/performance_tuning.md) | Configure timeouts, rate limiting, and memory for your use case |
| [Troubleshooting Reconnection](docs/guides/troubleshooting_reconnection.md) | Debug connection issues and reconnection logic |
| [AGENTS.md](AGENTS.md) | Guide for AI coding agents contributing to this project |

See the full [HexDocs documentation](https://hexdocs.pm/zen_websocket) for API reference and module documentation.

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `url` | WebSocket endpoint URL | required |
| `headers` | Custom headers for connection | `[]` |
| `timeout` | Connection timeout in milliseconds | `5000` |
| `retry_count` | Maximum reconnection attempts | `3` |
| `retry_delay` | Initial retry delay in milliseconds | `1000` |
| `heartbeat_interval` | Ping interval in milliseconds | `30000` |
| `reconnect_on_error` | Enable automatic reconnection | `true` |
| `restore_subscriptions` | Restore subscriptions after reconnect | `true` |
| `record_to` | Path to JSONL file for session recording | `nil` |
| `debug` | Enable verbose debug logging | `false` |

### Debug Logging

Debug logging is disabled by default to keep library output quiet. Enable it for troubleshooting connection issues:

```elixir
# Enable debug logging for troubleshooting
{:ok, client} = ZenWebsocket.Client.connect("wss://example.com", debug: true)
```

When enabled, you'll see detailed logs for connection establishment, WebSocket upgrades, frame handling, heartbeats, and reconnection attempts.

**Using Debug in Custom Adapters:**

If you're building a custom adapter or extension, use `ZenWebsocket.Debug.log/2` with the Config struct:

```elixir
alias ZenWebsocket.Debug

# Always pass the Config struct (not the full state map)
Debug.log(config, "Custom adapter initialized")
Debug.log(state.config, "Processing message: #{inspect(msg)}")
```

The function is a no-op when `debug: false` (the default), so you can leave debug statements in production code without performance impact.

## Testing Your Application

ZenWebsocket provides test utilities for testing your own WebSocket clients:

```elixir
defmodule MyApp.WebSocketTest do
  use ExUnit.Case

  alias ZenWebsocket.Testing

  setup do
    {:ok, server} = Testing.start_mock_server()
    on_exit(fn -> Testing.stop_server(server) end)
    {:ok, server: server}
  end

  test "client sends expected message", %{server: server} do
    # Connect your client to the mock server
    {:ok, client} = ZenWebsocket.Client.connect(server.url)

    # Send a message
    ZenWebsocket.Client.send_message(client, ~s({"type": "ping"}))

    # Assert the server received it (supports string, regex, map, or function matchers)
    assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

    ZenWebsocket.Client.close(client)
  end

  test "client handles server messages", %{server: server} do
    {:ok, client} = ZenWebsocket.Client.connect(server.url)

    # Inject a message from the server
    Testing.inject_message(server, ~s({"type": "notification", "data": "hello"}))

    # Your client should receive it
    assert_receive {:websocket_message, msg}, 1000
    assert String.contains?(msg, "notification")

    ZenWebsocket.Client.close(client)
  end

  test "client handles disconnection", %{server: server} do
    {:ok, client} = ZenWebsocket.Client.connect(server.url, reconnect_on_error: false)

    # Simulate server disconnect
    Testing.simulate_disconnect(server, :going_away)

    # Verify client detected disconnect
    Process.sleep(100)
    refute Process.alive?(client.server_pid)
  end
end
```

## Testing Philosophy

This library uses **real API testing exclusively**. No mocks or stubs - every test runs against actual WebSocket endpoints or local test servers. This ensures the library handles real-world conditions including network latency, connection drops, and API quirks.

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run quality checks
mix check
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests using real APIs (no mocks)
4. Ensure all quality checks pass (`mix check`)
5. Commit your changes
6. Push to the branch
7. Open a Pull Request

## Development Commands

```bash
mix compile           # Compile the project
mix test             # Run test suite
mix lint             # Run Credo analysis
mix typecheck        # Run Dialyzer
mix docs             # Generate documentation
mix check            # Run all quality checks
```

## License

This project is licensed under the MIT License.

## Links

- [Documentation](https://hexdocs.pm/zen_websocket)
- [Hex Package](https://hex.pm/packages/zen_websocket)
- [GitHub Repository](https://github.com/ZenHive/zen_websocket)

## Acknowledgments

Built for the Elixir community by [ZenHive](https://github.com/ZenHive).