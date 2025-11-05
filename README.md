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
# Connect to a WebSocket endpoint
{:ok, client} = ZenWebsocket.Client.connect("wss://echo.websocket.org", [
  timeout: 5000,
  heartbeat_interval: 30000
])

# Send a message
{:ok, _} = ZenWebsocket.Client.send_message(client, "Hello, WebSocket!")

# Receive messages in your process
receive do
  {:websocket_message, message} -> IO.inspect(message)
end

# Close the connection
:ok = ZenWebsocket.Client.close(client)
```

For more detailed examples, see our working examples with fully tested implementations:
- **Basic Usage** - Connection management and messaging
- **Error Handling** - Robust error recovery patterns  
- **JSON-RPC Client** - JSON-RPC 2.0 protocol usage
- **Subscription Management** - Channel subscription patterns

See the [Examples Guide](https://hexdocs.pm/zen_websocket/Examples.html) for complete code samples and usage patterns.

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
ZenWebsocket.Client         # Main client interface
ZenWebsocket.Config         # Configuration management
ZenWebsocket.Frame          # WebSocket frame handling
ZenWebsocket.Reconnection   # Automatic reconnection logic
ZenWebsocket.MessageHandler # Message parsing and routing
ZenWebsocket.ErrorHandler   # Error categorization
ZenWebsocket.RateLimiter   # API rate limiting
ZenWebsocket.JsonRpc       # JSON-RPC 2.0 protocol
```

## Platform Integration

The library includes a complete Deribit adapter as a reference implementation. To integrate with other platforms:

1. Create an adapter module following the Deribit pattern
2. Implement platform-specific authentication
3. Handle platform message formats
4. Add comprehensive tests against the real API

See `lib/zen_websocket/examples/deribit_adapter.ex` for a complete example.

## Configuration Options

- `url` - WebSocket endpoint URL
- `headers` - Custom headers for connection
- `timeout` - Connection timeout in milliseconds (default: 5000)
- `retry_count` - Maximum reconnection attempts (default: 3)
- `retry_delay` - Initial retry delay in milliseconds (default: 1000)
- `heartbeat_interval` - Ping interval in milliseconds (default: 30000)
- `reconnect_on_error` - Enable automatic reconnection (default: true)

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