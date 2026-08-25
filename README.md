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
- **Real WebSocket Testing** - Local real-stack servers plus opt-in live endpoint checks
- **Simple API** - connect, send, subscribe, monitor, and reconnect
- **Comprehensive Error Handling** - Categorized errors with recovery strategies
- **Rate Limiting** - Standalone token bucket you drive from your own code
- **JSON-RPC 2.0** - Full protocol support with correlation tracking
- **Pool Load Balancing** - Health-based routing with automatic failover
- **Session Recording** - JSONL message recording for debugging and replay
- **Test Utilities** - Consumer-facing test helpers with mock server
- **Self-Describing API** - Progressive discovery via `describe/0-2` for MCP tools and agents

## Installation

Add `zen_websocket` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zen_websocket, "~> 0.8"}
  ]
end
```

## Quick Start

### Basic Connection

```elixir
# Connect to a WebSocket endpoint (use your actual endpoint).
# Heartbeats are off unless you pass `heartbeat_config`.
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws", [
  timeout: 5000,
  heartbeat_config: %{type: :ping_pong, interval: 30_000}
])

# Send a message (must be binary — use Jason.encode!/1 for maps)
:ok = ZenWebsocket.Client.send_message(client, Jason.encode!(%{action: "ping"}))

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

ZenWebsocket tracks Deribit-dialect JSON-RPC subscriptions and restores them after reconnection:

```elixir
# Subscribe via Deribit's public/subscribe (no request id — tracked at send time)
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws")
:ok = ZenWebsocket.Client.subscribe(client, ["ticker.BTC", "trades.BTC"])

# On reconnect, tracked Deribit-dialect subscriptions are restored automatically
```

**What the library handles:**
- Tracking `public/subscribe` / `public/unsubscribe` via `SubscriptionManager`
- `Client.subscribe/2` tracking is optimistic (applied at send; a server rejection stays in the restore set)
- Automatic restoration after reconnection (when `restore_subscriptions: true`, the default)
- Building restore messages as Deribit `public/subscribe`

**What your client needs to handle:**
- Subscription state and reconnect replay for non-Deribit dialects
- Processing subscription data messages (sent to your handler callback)
- Deribit unsubscription requests (`public/unsubscribe` updates tracking)
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

See the [Examples Guide](https://hexdocs.pm/zen_websocket/examples.html) for an index of every in-tree example module and its test suite.

### Session Recording

Record WebSocket sessions for debugging and replay:

```elixir
# Enable recording when connecting
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws",
  record_to: "/tmp/session.jsonl"
)

# Use the connection normally - all messages are recorded
ZenWebsocket.Client.send_message(client, Jason.encode!(%{action: "subscribe", channel: "trades"}))

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
# Supply `handler:` when user code needs unsolicited inbound frames
opts = [handler: fn msg -> send(MyApp.Consumer, {:ws, msg}) end]

{:ok, _client1} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws", opts)
{:ok, _client2} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws", opts)
{:ok, _client3} = ZenWebsocket.ClientSupervisor.start_client("wss://api.example.com/ws", opts)

message = Jason.encode!(%{method: "public/test"})

# Send messages with automatic load balancing
# Routes to healthiest connection based on: pending requests, latency, errors
:ok = ZenWebsocket.ClientSupervisor.send_balanced(message)

# Automatic failover on connection failure (max 3 attempts by default)
:ok = ZenWebsocket.ClientSupervisor.send_balanced(message, max_attempts: 5)

# Check pool health
health = ZenWebsocket.PoolRouter.pool_health(ZenWebsocket.ClientSupervisor.list_clients())
# => [%{pid: #PID<0.123.0>, health: 95}, %{pid: #PID<0.124.0>, health: 87}, ...]
```

### Rate Limiting

`ZenWebsocket.RateLimiter` is a standalone token bucket backed by a named ETS
table. `Client` never consults it — call it from your own code before sending.

```elixir
alias ZenWebsocket.RateLimiter

# All four config keys are required; a missing `:tokens` raises KeyError.
{:ok, :deribit_limiter} = RateLimiter.init(:deribit_limiter, %{
  tokens: 100,
  refill_rate: 10,
  refill_interval: 1_000,
  request_cost: &RateLimiter.deribit_cost/1
})

request = %{"method" => "public/test"}

case RateLimiter.consume(:deribit_limiter, request) do
  :ok -> ZenWebsocket.Client.send_message(client, Jason.encode!(request))
  {:error, :rate_limited} -> {:error, :rate_limited}
end

{:ok, %{tokens: tokens}} = RateLimiter.status(:deribit_limiter)

# ETS tables are not reclaimed on process exit — free it explicitly
:ok = RateLimiter.shutdown(:deribit_limiter)
```

`init/2` schedules refills with `Process.send_after/3` against the **calling**
process. That process must handle `{:refill, name}` or refills stop permanently:

```elixir
def handle_info({:refill, name}, state) do
  ZenWebsocket.RateLimiter.refill(name)
  {:noreply, state}
end
```

### Deribit Integration

`DeribitGenServerAdapter` is the recommended supervised entry point.
`ZenWebsocket.Examples.DeribitAdapter` is the functional/struct-based variant:
`connect/1` returns a struct you thread through `authenticate/1`, `subscribe/2`,
`unsubscribe/2`, and `send_request/2,3`.

```elixir
# Configure Deribit credentials. Opts are a keyword list; the endpoint is
# selected with `:url` (it defaults to test.deribit.com when omitted).
config = [
  client_id: System.get_env("DERIBIT_CLIENT_ID"),
  client_secret: System.get_env("DERIBIT_CLIENT_SECRET"),
  url: "wss://test.deribit.com/ws/api/v2"
]

# Start the supervised adapter
{:ok, adapter} = ZenWebsocket.Examples.DeribitGenServerAdapter.start_link(config)

# Authenticate before any private/* request. The adapter does not authenticate
# on first connect - it only re-authenticates after a reconnect.
:ok = ZenWebsocket.Examples.DeribitGenServerAdapter.authenticate(adapter)

# Subscribe to market data
:ok = ZenWebsocket.Examples.DeribitGenServerAdapter.subscribe(
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
ZenWebsocket.Reconnection        # Internal reconnection helper (not in describe/0)
ZenWebsocket.MessageHandler      # Message parsing and routing
ZenWebsocket.ErrorHandler        # Error categorization
ZenWebsocket.RateLimiter         # API rate limiting
ZenWebsocket.JsonRpc             # JSON-RPC 2.0 protocol
ZenWebsocket.HeartbeatManager    # Internal heartbeat manager (not in describe/0)
ZenWebsocket.SubscriptionManager # Internal subscription tracking (not in describe/0)
ZenWebsocket.RequestCorrelator   # Internal request correlation (not in describe/0)
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

Two Deribit adapters ship as reference implementations:

- `ZenWebsocket.Examples.DeribitGenServerAdapter` (`lib/zen_websocket/examples/deribit_genserver_adapter.ex`)
  — the recommended supervised entry point: `start_link/1` plus `authenticate/1`,
  `subscribe/2`, `send_request/2,3`, `get_state/1`, with reconnect handling in the GenServer.
- `ZenWebsocket.Examples.DeribitAdapter` (`lib/zen_websocket/examples/deribit_adapter.ex`)
  — the functional/struct-based variant: `connect/0,1` returns a struct you thread
  through `authenticate/1`, `subscribe/2`, `unsubscribe/2`, `send_request/2,3`.

## Documentation

Comprehensive guides are available in the `docs/guides/` directory:

| Guide | Description |
|-------|-------------|
| [Building Adapters](docs/guides/building_adapters.md) | Create platform adapters with heartbeat, auth, and reconnection patterns |
| [Performance Tuning](docs/guides/performance_tuning.md) | Configure timeouts, rate limiting, and memory for your use case |
| [Troubleshooting Reconnection](docs/guides/troubleshooting_reconnection.md) | Debug connection issues and reconnection logic |
| [Deployment Considerations](docs/guides/deployment_considerations.md) | Latency, geography, architecture, and monitoring questions for trading apps |
| [AGENTS.md](https://github.com/ZenHive/zen_websocket/blob/main/AGENTS.md) | Guide for AI coding agents contributing to this project |

See the full [HexDocs documentation](https://hexdocs.pm/zen_websocket) for API reference and module documentation.

Shipped `elixir` / `iex` fences are checked against the public API. Mark a
deliberately incomplete fragment `elixir illustrative`, or start it with
`# illustrative`, so the checker leaves it alone.

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `url` | WebSocket endpoint URL | required |
| `headers` | Custom headers for connection | `[]` |
| `timeout` | Connection timeout in milliseconds | `5000` |
| `retry_count` | Maximum reconnection attempts | `3` |
| `retry_delay` | Initial retry delay in milliseconds | `1000` |
| `heartbeat_config` | Heartbeat mode (see below); heartbeats are off until you set it | `:disabled` |
| `heartbeat_interval` | Fallback interval used when `heartbeat_config` omits `:interval` | `30000` |
| `reconnect_on_error` | Enable automatic reconnection | `true` |
| `restore_subscriptions` | Restore tracked Deribit subscriptions after reconnect | `true` |
| `record_to` | Path to JSONL file for session recording | `nil` |
| `debug` | Enable verbose debug logging | `false` |

### Heartbeat Configuration

`heartbeat_config` is either the atom `:disabled` (the default — no heartbeat is
ever sent) or a map with a `:type`:

| `type` | Behavior |
|--------|----------|
| `:ping_pong` | Sends a WebSocket ping frame each interval and measures the pong round trip |
| `:deribit` | Sends Deribit's `public/set_heartbeat` dialect and answers `test_request` |
| `:binance` | Inbound-only: incoming heartbeat messages are consumed, nothing is sent outbound |

```elixir
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws",
  heartbeat_config: %{type: :ping_pong, interval: 30_000}
)
```

`:interval` falls back to the `heartbeat_interval` option when omitted.

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

    ref = Process.monitor(client.server_pid)

    # Simulate server disconnect
    Testing.simulate_disconnect(server, :going_away)

    # Verify client detected disconnect
    assert_receive {:DOWN, ^ref, :process, _, _}, 1000
    refute Process.alive?(client.server_pid)
  end
end
```

## Testing Philosophy

Pure logic is unit-tested without sockets. Integration tests exercise either the
local real WebSocket stack or opt-in live provider endpoints; exchange responses,
authentication, and provider behavior are never simulated.

```bash
# Quick test health check
mix test.json --quiet --summary-only

# Iterate on failures
mix test.json --quiet --failed --first-failure

# Include integration tests
mix test --include integration
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write unit tests and real-stack integration tests; do not simulate exchange behavior
4. Ensure the verification workflow passes (see Development Commands below)
5. Commit your changes
6. Push to the branch
7. Open a Pull Request

## Development Commands

```bash
mix compile           # Compile the project
mix test.json --quiet --summary-only   # Quick test health check
mix test.json --quiet --failed --first-failure # Iterate on failures
mix dialyzer.json --quiet              # Type checking
mix credo --strict --format json       # Static analysis
mix security                           # Sobelow security scan
mix docs             # Generate documentation
mix test --include integration         # Full test suite with integration
```

## License

This project is licensed under the MIT License.

## Links

- [Documentation](https://hexdocs.pm/zen_websocket)
- [Hex Package](https://hex.pm/packages/zen_websocket)
- [GitHub Repository](https://github.com/ZenHive/zen_websocket)

## Acknowledgments

Built for the Elixir community by [ZenHive](https://github.com/ZenHive).
