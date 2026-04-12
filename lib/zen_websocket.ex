defmodule ZenWebsocket do
  @moduledoc """
  A robust WebSocket client library for Elixir, built on Gun transport.

  Designed for financial APIs (cryptocurrency exchanges like Deribit) but
  works with any WebSocket endpoint. Provides automatic reconnection,
  heartbeat management, rate limiting, and request/response correlation.

  ## Quick Start

      # Connect to a WebSocket endpoint
      {:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")

      # Send a message
      :ok = ZenWebsocket.Client.send_message(client, Jason.encode!(%{method: "public/test"}))

      # Subscribe to channels
      :ok = ZenWebsocket.Client.subscribe(client, ["trades.BTC-PERPETUAL.raw"])

      # Check connection state
      :connected = ZenWebsocket.Client.get_state(client)

      # Close when done
      :ok = ZenWebsocket.Client.close(client)

  ## Supervised Connections

  For production use, `ZenWebsocket.ClientSupervisor` manages connection pools
  with health-based load balancing:

      # Start the supervisor (add to your application supervision tree)
      ZenWebsocket.ClientSupervisor.start_link([])

      # Start managed connections
      {:ok, client} = ZenWebsocket.ClientSupervisor.start_client("wss://example.com/ws")

      # Route to healthiest connection
      :ok = ZenWebsocket.ClientSupervisor.send_balanced(message)

  ## Key Modules

  ### Client API
  * `ZenWebsocket.Client` — 5-function public API: `connect/2`, `send_message/2`,
    `close/1`, `subscribe/2`, `get_state/1`
  * `ZenWebsocket.ClientSupervisor` — supervised connection pool with `send_balanced/2`
  * `ZenWebsocket.Config` — connection configuration and validation

  ### Infrastructure
  * `ZenWebsocket.Reconnection` — exponential backoff retry logic
  * `ZenWebsocket.HeartbeatManager` — keepalive lifecycle management
  * `ZenWebsocket.SubscriptionManager` — subscription tracking and restoration
  * `ZenWebsocket.RequestCorrelator` — JSON-RPC request/response correlation
  * `ZenWebsocket.RateLimiter` — token bucket rate limiting
  * `ZenWebsocket.PoolRouter` — health-based connection routing

  ### Observability
  * `ZenWebsocket.ErrorHandler` — error categorization with `explain/1`
  * `ZenWebsocket.LatencyStats` — connection latency tracking (p50/p99)
  * `ZenWebsocket.Recorder` — session recording for debugging (JSONL format)
  * `ZenWebsocket.Testing` — test utilities with `MockWebSockServer` helpers

  ### Protocol
  * `ZenWebsocket.Frame` — WebSocket frame encoding/decoding
  * `ZenWebsocket.JsonRpc` — JSON-RPC 2.0 message formatting
  * `ZenWebsocket.MessageHandler` — message parsing and routing

  ## Platform Examples

  See `ZenWebsocket.Examples.DeribitAdapter` for a production-ready adapter
  demonstrating authentication, subscription management, and heartbeat handling.

  ## Self-Describing API

  All public modules are annotated with `descripex` for progressive discovery:

      ZenWebsocket.describe()                        # Library overview
      ZenWebsocket.describe(:client)                 # Client functions
      ZenWebsocket.describe(:client, :connect)       # Full connect details
  """

  use Descripex.Discoverable,
    modules: [
      # Client API
      ZenWebsocket.Client,
      ZenWebsocket.Config,
      ZenWebsocket.ClientSupervisor,
      # Infrastructure
      ZenWebsocket.Reconnection,
      ZenWebsocket.HeartbeatManager,
      ZenWebsocket.SubscriptionManager,
      ZenWebsocket.RequestCorrelator,
      ZenWebsocket.RateLimiter,
      ZenWebsocket.PoolRouter,
      # Observability
      ZenWebsocket.ErrorHandler,
      ZenWebsocket.LatencyStats,
      ZenWebsocket.Recorder,
      ZenWebsocket.RecorderServer,
      ZenWebsocket.Testing,
      # Protocol
      ZenWebsocket.Frame,
      ZenWebsocket.JsonRpc,
      ZenWebsocket.MessageHandler
    ]
end
