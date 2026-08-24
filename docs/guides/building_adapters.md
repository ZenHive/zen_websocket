# Building Exchange Adapters Guide

## Overview

This guide explains how to build exchange adapters for ZenWebsocket. Exchange adapters provide platform-specific functionality on top of the core WebSocket client, including authentication, subscription management, and state restoration.

## When to Use What

Choose your adapter pattern based on complexity:

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **Plain Client** | Simple scripts, one-off connections, no state restoration needed | Quick data fetch |
| **Struct Adapter** | Stateless operations, functional pipelines, no reconnection logic | Data transformation |
| **GenServer Adapter** | Production use, state management, reconnection, subscription tracking | Trading bots |

**Decision tree:**

```
Need automatic reconnection?
  └─ No → Plain Client or Struct Adapter
  └─ Yes → Need to restore state after reconnection?
             └─ No → Plain Client with reconnect_on_error: true
             └─ Yes → GenServer Adapter (recommended for production)
```

## Receiving Messages

Sending is only half of an adapter. Inbound frames reach you through the
`:handler` function passed to `Client.connect/2` — nothing is delivered
automatically.

**`Client.connect/2` installs a default handler only when you omit `:handler`.**
It is added by `ZenWebsocket.Client.CallFacade.with_default_handler/2`, and it
targets **the process that called `connect/2`**. For a GenServer adapter that is
the adapter process itself, provided the adapter calls `Client.connect/2` from
inside one of its own callbacks. The shapes it sends:

| Message | Sent when | Payload |
|---------|-----------|---------|
| `{:websocket_message, data}` | a text **or** binary frame arrived and was not intercepted (see below) — both collapse to this tag | decoded map for a JSON text frame; raw binary for a non-JSON text frame or a binary frame |
| `{:websocket_unmatched_response, response}` | a JSON-RPC response arrived whose `"id"` matched no pending request | decoded map |
| `{:websocket_protocol_error, reason}` | a frame could not be decoded (fatal — the client stops) | reason term |

**The client decodes JSON for you on the inbound path**, so do not call
`Jason.decode/1` on `data` — for a valid JSON text frame it is already a map.

**Two classes of text frame never reach your handler at all**, so do not write
clauses for them:

- **JSON-RPC replies carrying an `"id"`** are correlated and returned as the
  `{:ok, response}` reply to the `Client.send_message/2` that issued them. Only
  uncorrelated replies surface, as `{:websocket_unmatched_response, _}`.
- **Frames whose decoded body matches `%{"method" => "heartbeat"}`** are routed
  straight to `ZenWebsocket.HeartbeatManager.handle_message/2` by
  `ZenWebsocket.Client.Frames.route_data_frame/2`. The client answers them
  itself; a `handle_info({:websocket_message, %{"method" => "heartbeat"}}, _)`
  clause in your adapter can never fire. Observe heartbeat health through
  `Client.get_heartbeat_health/1` instead.

Market-data notifications (`%{"method" => "subscription"}`) *are* delivered
normally, as are any other decoded maps and non-JSON text frames.

Handle them in the adapter's `handle_info/2`:

```elixir
@impl true
def handle_info({:websocket_message, %{"method" => "subscription", "params" => params}}, state) do
  {:noreply, dispatch_market_data(state, params)}
end

def handle_info({:websocket_message, %{} = msg}, state) do
  Logger.debug("Unhandled JSON message: #{inspect(msg)}")
  {:noreply, state}
end

def handle_info({:websocket_message, text}, state) when is_binary(text) do
  # Text frame that was not valid JSON, or a binary frame
  {:noreply, handle_raw_frame(state, text)}
end

def handle_info({:websocket_unmatched_response, response}, state) do
  # Usually a late reply after RequestCorrelator already timed the request out.
  Logger.warning("Unmatched response: #{inspect(response)}")
  {:noreply, state}
end

def handle_info({:websocket_protocol_error, reason}, state) do
  Logger.error("Protocol error: #{inspect(reason)}")
  {:noreply, state}
end
```

**Supervised clients must pass `:handler` explicitly.**
`ClientSupervisor.start_client/2` starts the client through
`DynamicSupervisor.start_child/2` → `Client.start_link/2`, which never runs
`with_default_handler/2`. With no `:handler` in the options the client falls
back to `ZenWebsocket.MessageHandler.default_handler/1`, which accepts and
**discards** every message — a supervised adapter that forgets `:handler` sees a
healthy connection and no data.

```elixir
adapter = self()

{:ok, client} =
  ClientSupervisor.start_client(url,
    handler: fn
      {:message, data} -> send(adapter, {:websocket_message, data})
      {:binary, data} -> send(adapter, {:websocket_message, data})
      {:unmatched_response, r} -> send(adapter, {:websocket_unmatched_response, r})
      {:protocol_error, reason} -> send(adapter, {:websocket_protocol_error, reason})
      _other -> :ok
    end
  )
```

The complete set of tuple shapes a custom handler receives is documented in
`USAGE_RULES.md`, section **"Handler Message Reference"**.

## Adapter Template

Here's a minimal template for building an exchange adapter:

```elixir
defmodule YourExchange.Adapter do
  use GenServer
  require Logger
  
  alias ZenWebsocket.Client
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  def connect(adapter) do
    GenServer.call(adapter, :connect)
  end
  
  def subscribe(adapter, channels) do
    GenServer.call(adapter, {:subscribe, channels})
  end
  
  def send_order(adapter, order_params) do
    GenServer.call(adapter, {:send_order, order_params})
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    state = %{
      url: opts[:url] || "wss://your-exchange.com/ws",
      client: nil,
      client_ref: nil,
      api_key: opts[:api_key],
      api_secret: opts[:api_secret],
      subscriptions: MapSet.new(),
      authenticated: false,
      reconnecting: false
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:connect, _from, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Private Functions
  
  defp do_connect(state) do
    # CRITICAL: Always set reconnect_on_error: false
    connect_opts = [
      reconnect_on_error: false,  # Adapter handles reconnection
      heartbeat_config: %{
        # Valid types: :deribit, :ping_pong, :binance, :disabled (see table below)
        type: :ping_pong,
        interval: 30_000
      }
    ]
    
    case Client.connect(state.url, connect_opts) do
      {:ok, client} ->
        # Monitor the client process
        ref = Process.monitor(client.server_pid)
        
        new_state = %{state | 
          client: client, 
          client_ref: ref,
          reconnecting: false
        }
        
        # Authenticate if credentials provided
        case authenticate(new_state) do
          {:ok, auth_state} ->
            # Restore subscriptions if any
            restore_subscriptions(auth_state)
          error ->
            error
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp authenticate(state) when is_nil(state.api_key) do
    {:ok, state}  # No authentication needed
  end
  
  defp authenticate(state) do
    # Exchange-specific authentication
    auth_msg = build_auth_message(state.api_key, state.api_secret)
    
    case Client.send_message(state.client, Jason.encode!(auth_msg)) do
      :ok ->
        # Wait for auth response (simplified)
        {:ok, %{state | authenticated: true}}
      error ->
        error
    end
  end
  
  defp restore_subscriptions(%{subscriptions: subs} = state) do
    unless Enum.empty?(subs) do
      Enum.each(subs, fn channel ->
        sub_msg = build_subscription_message(channel)
        Client.send_message(state.client, Jason.encode!(sub_msg))
      end)
    end

    {:ok, state}
  end
  
  # Monitor handling - CRITICAL for reconnection
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{client_ref: ref} = state) do
    Logger.warning("Client process down: #{inspect(reason)}, initiating reconnection")
    
    new_state = %{state | 
      client: nil, 
      client_ref: nil,
      reconnecting: true,
      authenticated: false
    }
    
    # Attempt immediate reconnection
    case do_connect(new_state) do
      {:ok, connected_state} ->
        Logger.info("Successfully reconnected")
        {:noreply, connected_state}
      {:error, reason} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")
        # Schedule retry
        Process.send_after(self(), :retry_connect, 5_000)
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info(:retry_connect, state) do
    case do_connect(state) do
      {:ok, connected_state} ->
        {:noreply, connected_state}
      {:error, _} ->
        # Exponential backoff could be implemented here
        Process.send_after(self(), :retry_connect, 10_000)
        {:noreply, state}
    end
  end
  
  # Exchange-specific message builders
  
  defp build_auth_message(api_key, api_secret) do
    # Exchange-specific auth format
    timestamp = System.system_time(:millisecond)

    %{
      "method" => "auth",
      "params" => %{
        "api_key" => api_key,
        "timestamp" => timestamp,
        # Exchange-specific signature - this is a placeholder
        # Real implementation depends on exchange requirements
        "signature" => generate_signature(api_secret, timestamp)
      }
    }
  end

  # Placeholder - implement based on exchange documentation
  defp generate_signature(api_secret, timestamp) do
    :crypto.mac(:hmac, :sha256, api_secret, "#{timestamp}")
    |> Base.encode16(case: :lower)
  end
  
  defp build_subscription_message(channel) do
    # Exchange-specific subscription format
    %{
      "method" => "subscribe",
      "params" => %{
        "channel" => channel
      }
    }
  end
end
```

## Critical Implementation Rules

### 1. Always Set `reconnect_on_error: false`

This is the most critical rule. Your adapter MUST disable the Client's internal reconnection:

```elixir
connect_opts = [
  reconnect_on_error: false,  # REQUIRED for adapters
  # ... other options
]
```

**Why?** This prevents duplicate reconnection attempts. The adapter handles all reconnection logic.

### 2. Monitor the Client Process

Always monitor the Client process to detect failures:

```elixir
{:ok, client} = Client.connect(url, opts)
ref = Process.monitor(client.server_pid)
```

### 3. Handle Process DOWN Messages

Implement proper handling for client process termination:

```elixir
def handle_info({:DOWN, ref, :process, _pid, reason}, %{client_ref: ref} = state) do
  # Client died - initiate reconnection
  # This is your ONLY reconnection trigger
end
```

### 4. Encode Payloads Yourself

`Client.send_message/2` takes a `binary()` and writes it to the socket as a
text frame unchanged — there is no JSON encoding step in the send path. Passing
a map raises inside Gun. Encode before sending:

```elixir
Client.send_message(client, Jason.encode!(%{"method" => "subscribe"}))
```

Correlation reads the JSON-RPC `"id"` out of that binary, so a request you want
correlated must be valid JSON carrying an `"id"`.

## Heartbeat Configuration

ZenWebsocket supports these heartbeat types via `heartbeat_config`. **The list is
closed:** `heartbeat_config` is stored on the client state without validation
(`ZenWebsocket.Client.Connection`), and `HeartbeatManager.send_heartbeat/1`
falls through to a no-op clause for anything it does not recognize — so an
invented type such as `:custom` produces a timer that fires and sends nothing,
with no error.

| Type | Description | Use Case |
|------|-------------|----------|
| `:deribit` | JSON-RPC test_request/heartbeat | Deribit API |
| `:ping_pong` | WebSocket ping/pong frames | Standard WebSocket |
| `:binance` | Inbound-only: no outbound send clause exists, so the timer sends nothing. Binance's server-initiated pings are answered by Gun at frame level | Binance APIs |
| `:disabled` | No heartbeats | Custom handling |

### Configuring Heartbeats

```elixir
# Deribit-style JSON-RPC heartbeats
connect_opts = [
  heartbeat_config: %{
    type: :deribit,
    interval: 15_000  # 15 seconds
  }
]

# Standard WebSocket ping/pong frames
connect_opts = [
  heartbeat_config: %{
    type: :ping_pong,
    interval: 30_000
  }
]

# Disable heartbeats (adapter handles manually)
connect_opts = [
  heartbeat_config: :disabled
]
```

### Custom Heartbeat Handler

For exchanges with unique heartbeat patterns, disable built-in heartbeats and implement your own:

```elixir
defmodule MyExchange.Adapter do
  use GenServer

  @heartbeat_interval 20_000

  def init(opts) do
    state = %{
      heartbeat_timer: nil,
      # ... other state
    }
    {:ok, state}
  end

  # Start heartbeat after connection established
  defp start_heartbeat(state) do
    timer = Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    %{state | heartbeat_timer: timer}
  end

  def handle_info(:send_heartbeat, state) do
    # Exchange-specific heartbeat format
    heartbeat_msg = %{"op" => "ping", "ts" => System.system_time(:millisecond)}
    Client.send_message(state.client, Jason.encode!(heartbeat_msg))

    timer = Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    {:noreply, %{state | heartbeat_timer: timer}}
  end

  # Handle heartbeat response
  def handle_info({:websocket_message, %{"op" => "pong"}}, state) do
    # Heartbeat acknowledged
    {:noreply, state}
  end
end
```

## State Restoration Pattern

After reconnection, restore your application state in order:

1. **Re-establish connection** (creates new Gun process)
2. **Authenticate** (if required by exchange)
3. **Restore subscriptions** (market data, account updates)
4. **Resume operations** (re-enable trading, etc.)

```elixir
defp restore_connection_state(state) do
  with {:ok, connected_state} <- establish_connection(state),
       {:ok, auth_state} <- authenticate(connected_state),
       {:ok, sub_state} <- restore_subscriptions(auth_state),
       {:ok, final_state} <- resume_operations(sub_state) do
    {:ok, final_state}
  end
end
```

## Example: Deribit Adapter

Study the production-ready Deribit adapter for a complete implementation:

```elixir
# From lib/zen_websocket/examples/deribit_genserver_adapter.ex (handle_info/2)

def handle_info(:connect, state) do
  opts = [
    heartbeat_config: %{type: :deribit, interval: (state.opts[:heartbeat_interval] || 30) * 1000},
    reconnect_on_error: false
  ]

  opts = if h = state.opts[:handler], do: Keyword.put(opts, :handler, h), else: opts

  case Client.connect(state.url, opts) do
    {:ok, client} ->
      ref = Process.monitor(client.server_pid)
      new_state = %{state | client: client, monitor_ref: ref}

      if state.was_authenticated or MapSet.size(state.subscriptions) > 0 do
        send(self(), :restore_state)
      end

      {:noreply, new_state}

    {:error, reason} ->
      Logger.warning("Connect failed: #{inspect(reason)}")
      Process.send_after(self(), :connect, @reconnect_delay)
      {:noreply, state}
  end
end
```

Two things to note, because they differ from what a first reading might assume:

- **Connecting is message-driven, not a helper call.** `init/1` sets the state
  and does `send(self(), :connect)`, so the socket opens outside `init/1` and a
  failed connect reschedules itself rather than crashing the GenServer.
- **The adapter does not authenticate on first connect.** `was_authenticated`
  starts `false`, so `:restore_state` — which is what calls `authenticate/1` —
  only fires on a *re*-connect. A fresh process must call
  `DeribitGenServerAdapter.authenticate/1` before any `private/*` request.

## Authentication Patterns

Different exchanges use different authentication schemes:

### 1. API Key + Secret (Deribit, JSON-RPC)

```elixir
defp authenticate(state) do
  auth_params = %{
    "jsonrpc" => "2.0",
    "method" => "public/auth",
    "params" => %{
      "grant_type" => "client_credentials",
      "client_id" => state.client_id,
      "client_secret" => state.client_secret
    },
    "id" => generate_id()
  }

  case Client.send_message(state.client, Jason.encode!(auth_params)) do
    :ok ->
      {:ok, %{state | authenticating: true}}
    error ->
      error
  end
end
```

### 2. HMAC Signature (Binance, Coinbase)

```elixir
defp authenticate(state) do
  timestamp = System.system_time(:millisecond)

  # Build signature payload
  payload = "timestamp=#{timestamp}"
  signature = :crypto.mac(:hmac, :sha256, state.api_secret, payload)
               |> Base.encode16(case: :lower)

  auth_msg = %{
    "method" => "auth",
    "params" => %{
      "apiKey" => state.api_key,
      "timestamp" => timestamp,
      "signature" => signature
    }
  }

  Client.send_message(state.client, Jason.encode!(auth_msg))
end
```

### 3. OAuth Token Flow

```elixir
defp authenticate(state) do
  # Exchange auth code for access token (via HTTP, not WebSocket)
  case exchange_token(state.auth_code) do
    {:ok, access_token} ->
      auth_msg = %{
        "type" => "auth",
        "token" => access_token
      }
      Client.send_message(state.client, Jason.encode!(auth_msg))
      {:ok, %{state | access_token: access_token}}

    {:error, reason} ->
      {:error, reason}
  end
end

defp exchange_token(auth_code) do
  case Req.post("https://api.exchange.com/oauth/token",
         form: [grant_type: "authorization_code", code: auth_code]
       ) do
    {:ok, %{status: 200, body: %{"access_token" => token}}} ->
      {:ok, token}

    {:ok, %{status: status, body: body}} ->
      {:error, {:token_exchange_failed, status, body}}

    {:error, reason} ->
      {:error, {:http_error, reason}}
  end
end
```

## Common Patterns

### Subscription Management
```elixir
defp track_subscription(state, channel) do
  new_subs = MapSet.put(state.subscriptions, channel)
  %{state | subscriptions: new_subs}
end

defp restore_subscriptions(state) do
  Enum.each(state.subscriptions, fn channel ->
    subscribe_message = build_subscribe_message(channel)
    Client.send_message(state.client, Jason.encode!(subscribe_message))
  end)
  
  {:ok, state}
end
```

### Cancel-on-Disconnect
```elixir
defp handle_connection_loss(state) do
  if state.cancel_on_disconnect do
    # Cancel all open orders
    cancel_all_orders(state)
  end
  
  # Proceed with reconnection
  initiate_reconnection(state)
end
```

## Example: Binance Spot Adapter

The connect / monitor / reconnect scaffolding is identical to the template
above — only the exchange-specific pieces differ. Those pieces:

```elixir
defmodule Binance.SpotAdapter do
  use GenServer
  require Logger

  alias ZenWebsocket.Client

  @base_url "wss://stream.binance.com:9443/ws"

  # Binance answers server-initiated pings at the WebSocket frame level,
  # so :ping_pong is the right heartbeat type.
  @connect_opts [
    heartbeat_config: %{type: :ping_pong, interval: 30_000},
    reconnect_on_error: false
  ]

  # Plain JSON, not JSON-RPC: a "method"/"params"/"id" envelope where
  # params is a flat list of stream names.
  @impl true
  def handle_call({:subscribe, streams}, _from, state) do
    msg = %{"method" => "SUBSCRIBE", "params" => streams, "id" => state.request_id}

    case Client.send_message(state.client, Jason.encode!(msg)) do
      :ok ->
        new_subs = Enum.reduce(streams, state.subscriptions, &MapSet.put(&2, &1))
        {:reply, :ok, %{state | subscriptions: new_subs, request_id: state.request_id + 1}}

      error ->
        {:reply, error, state}
    end
  end

  # HMAC-SHA256 over the query string. Binance uses this for REST endpoints
  # (listen-key creation for the user data stream), not for WebSocket frames.
  def sign(secret, query) do
    :hmac
    |> :crypto.mac(:sha256, secret, query)
    |> Base.encode16(case: :lower)
  end
end
```

**Key differences from Deribit:**
- Uses `"method" => "SUBSCRIBE"` instead of JSON-RPC
- Authentication via HMAC signatures (typically for REST, user data streams)
- Stream names like `"btcusdt@trade"` instead of channel objects
- Ping/pong heartbeats handled at WebSocket frame level

## Testing Your Adapter

Test against a real socket. `ZenWebsocket.Testing` starts an in-process
cowboy/websock mock server, so no exchange behavior is stubbed. Synchronize on
messages and process monitors — this repo bans `:timer.sleep/1` as a
synchronization primitive.

| Helper | Signature | Purpose |
|--------|-----------|---------|
| `start_mock_server/1` | `(keyword()) :: {:ok, server}` | `server` is `%{pid:, port:, url:, message_agent:}`; `port: 0` (default) picks a free port |
| `stop_server/1` | `(server) :: :ok` | Teardown; call from `on_exit/1` |
| `inject_message/2` | `(server, binary()) :: :ok` | Push a text frame to every connected client |
| `assert_message_sent/3` | `(server, expected, timeout_ms) :: boolean()` | Poll captured client→server messages; `expected` may be a string, regex, map, or 1-arity function |
| `simulate_disconnect/2` | `(server, :normal \| :going_away \| {:code, n}) :: :ok` | Close from the server side |

### Unit Tests

```elixir
defmodule YourExchange.AdapterTest do
  use ExUnit.Case, async: false

  alias YourExchange.Adapter
  alias ZenWebsocket.Testing

  setup do
    {:ok, server} = Testing.start_mock_server()
    on_exit(fn -> Testing.stop_server(server) end)
    {:ok, server: server}
  end

  @tag :integration
  @tag :local_network
  test "reconnects on client process death", %{server: server} do
    {:ok, adapter} = start_supervised({Adapter, url: server.url})
    assert :ok = Adapter.connect(adapter)

    client_pid = :sys.get_state(adapter).client.server_pid
    ref = Process.monitor(client_pid)

    Process.exit(client_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^client_pid, :killed}, 1_000

    # The adapter re-subscribes on reconnect; the mock server sees that frame.
    assert Testing.assert_message_sent(server, ~r/"subscribe"/, 2_000)

    refute :sys.get_state(adapter).client.server_pid == client_pid
  end

  @tag :integration
  @tag :local_network
  test "routes injected messages into adapter state", %{server: server} do
    {:ok, adapter} = start_supervised({Adapter, url: server.url})
    assert :ok = Adapter.connect(adapter)

    Testing.inject_message(server, ~s({"method":"subscription","params":{"channel":"trades"}}))

    # Adapter forwards market data to its caller; assert on that, not on a sleep.
    assert_receive {:market_data, %{"channel" => "trades"}}, 1_000
  end
end
```

### Integration Tests

```elixir
@tag :integration
@tag :local_network
test "maintains subscriptions across a server-side disconnect", %{server: server} do
  {:ok, adapter} = start_supervised({Adapter, url: server.url})
  :ok = Adapter.connect(adapter)
  :ok = Adapter.subscribe(adapter, ["trades.BTC-USD"])

  assert Testing.assert_message_sent(server, ~r/trades\.BTC-USD/, 1_000)

  client_pid = :sys.get_state(adapter).client.server_pid
  ref = Process.monitor(client_pid)

  Testing.simulate_disconnect(server, :going_away)
  assert_receive {:DOWN, ^ref, :process, ^client_pid, _reason}, 2_000

  # Subscription is resent after the adapter reconnects.
  assert Testing.assert_message_sent(server, ~r/trades\.BTC-USD/, 5_000)
end
```

Tests that open a socket must carry `@tag :integration` (plus `:local_network`
for mock-server tests) — default `mix test` excludes them.

## Troubleshooting

Adapter reconnection problems — duplicate reconnection attempts, lost
subscriptions, authentication that does not survive a reconnect, and Gun
processes that leak — are diagnosed in
[Troubleshooting Reconnection](troubleshooting_reconnection.md), with symptoms,
root causes, and fixes for each.

## Best Practices

1. **Use Supervisors**: Always run adapters under a Supervisor
2. **Log Transitions**: Log all state changes for debugging
3. **Implement Backoff**: Use exponential backoff for reconnection attempts
4. **Monitor Health**: Add telemetry for connection health metrics
5. **Test Failures**: Test with real network failures and process crashes
6. **Handle Partial State**: Be prepared for partial message delivery

## Summary

Building a robust exchange adapter requires:
- Disabling Client reconnection (`reconnect_on_error: false`)
- Monitoring Client process for failures
- Implementing complete state restoration
- Testing reconnection scenarios thoroughly

Follow the patterns in this guide and study the Deribit adapter example for a production-ready implementation.

## Related Guides

- [Troubleshooting Reconnection](troubleshooting_reconnection.md) - Diagnose duplicate reconnects, lost subscriptions, auth loss, and Gun process leaks
- [Performance Tuning Guide](performance_tuning.md) - Optimize timeouts, reconnection, rate limiting, and memory usage
- [Deployment Considerations](deployment_considerations.md) - Supervision, pooling, and production trade-offs for adapters
