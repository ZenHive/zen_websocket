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

      # Start managed connections. `handler:` is required here — the supervised
      # path has no default that forwards frames to the caller.
      {:ok, client} =
        ZenWebsocket.ClientSupervisor.start_client("wss://example.com/ws",
          handler: fn msg -> send(MyApp.Consumer, {:ws, msg}) end
        )

      # Route to healthiest connection
      :ok = ZenWebsocket.ClientSupervisor.send_balanced(message)

  ## Key Modules

  ### Client API
  * `ZenWebsocket.Client` — `connect/2`, `send_message/2`, `close/1`, `subscribe/2`,
    `get_state/1`, plus monitoring (`get_heartbeat_health/1`, `get_state_metrics/1`,
    `get_latency_stats/1`) and `reconnect/1`. GenServer callbacks stay on Client;
    responsibility-scoped `Client.*` modules hold call wrapping, Gun lifecycle,
    retry policy, frame routing, correlation, recording, and callback bodies.
  * `ZenWebsocket.ClientSupervisor` — supervised connection pool with `send_balanced/2`
  * `ZenWebsocket.Config` — connection configuration and validation

  ### Infrastructure
  * `ZenWebsocket.RateLimiter` — token bucket rate limiting
  * `ZenWebsocket.PoolRouter` — health-based connection routing
  * `ZenWebsocket.ConnectionRegistry` — opt-in ETS connection lookup utility

  ### Internal (not in `describe/0`)
  * `ZenWebsocket.Reconnection` — exponential backoff; called only from the Client GenServer
  * `ZenWebsocket.HeartbeatManager` — keepalive lifecycle; operates on Client-owned state
  * `ZenWebsocket.SubscriptionManager` — subscription tracking; operates on Client-owned state
  * `ZenWebsocket.RequestCorrelator` — JSON-RPC correlation; operates on Client-owned state

  ### Observability
  * `ZenWebsocket.ErrorHandler` — error categorization with `explain/1`
  * `ZenWebsocket.LatencyStats` — connection latency tracking (p50/p99)
  * `ZenWebsocket.Recorder` — pure JSONL session recording/replay functions
  * `ZenWebsocket.RecorderServer` — async file I/O behind `Recorder` recordings
  * `ZenWebsocket.Testing` — mock-server test helpers for consumers
    (`start_mock_server/1`, `simulate_disconnect/2`, `inject_message/2`)

  ### Protocol
  * `ZenWebsocket.Frame` — WebSocket frame encoding/decoding
  * `ZenWebsocket.JsonRpc` — JSON-RPC 2.0 message formatting
  * `ZenWebsocket.MessageHandler` — message parsing and routing

  ## Platform Examples

  See `ZenWebsocket.Examples.DeribitGenServerAdapter` for a production-ready
  supervised adapter demonstrating authentication, subscription management, and
  monitored auto-reconnect. For a simpler unsupervised example, see
  `ZenWebsocket.Examples.DeribitAdapter`.

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
      ZenWebsocket.RateLimiter,
      ZenWebsocket.PoolRouter,
      ZenWebsocket.ConnectionRegistry,
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
