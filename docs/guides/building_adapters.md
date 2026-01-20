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
        type: :custom,  # or :deribit, :standard
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
    
    case Client.send_message(state.client, auth_msg) do
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
        Client.send_message(state.client, sub_msg)
      end)
    end

    {:ok, state}
  end
  
  # Monitor handling - CRITICAL for reconnection
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{client_ref: ref} = state) do
    Logger.warn("Client process down: #{inspect(reason)}, initiating reconnection")
    
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

## Heartbeat Configuration

ZenWebsocket supports different heartbeat types via `heartbeat_config`:

| Type | Description | Use Case |
|------|-------------|----------|
| `:deribit` | JSON-RPC test_request/heartbeat | Deribit API |
| `:ping_pong` | WebSocket ping/pong frames | Standard WebSocket |
| `:binance` | Frame-level pings (handled by Gun) | Binance APIs |
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
    Client.send_message(state.client, heartbeat_msg)

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
# From lib/zen_websocket/examples/deribit_genserver_adapter.ex

defp do_connect(state) do
  # Parse URL for testnet/mainnet
  url = state.url || @default_url
  
  # Configure connection
  connect_opts = [
    heartbeat_config: %{
      type: :deribit,
      interval: heartbeat_interval
    },
    reconnect_on_error: false  # Critical!
  ]
  
  # Connect and monitor
  case Client.connect(url, connect_opts) do
    {:ok, client} ->
      ref = Process.monitor(client.server_pid)
      
      new_state = %{state | 
        client: client, 
        monitor_ref: ref,
        connected: true,
        connecting: false
      }
      
      # Authenticate if we have credentials
      if state.client_id && state.client_secret do
        case authenticate(new_state) do
          {:ok, auth_state} ->
            restore_subscriptions(auth_state)
          {:error, reason} ->
            {:error, reason}
        end
      else
        {:ok, new_state}
      end
  end
end
```

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

  case Client.send_message(state.client, auth_params) do
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

  Client.send_message(state.client, auth_msg)
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
      Client.send_message(state.client, auth_msg)
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
    Client.send_message(state.client, subscribe_message)
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

Binance uses a different pattern than Deribit:
- No JSON-RPC (plain JSON messages)
- HMAC signature authentication
- Combined streams via stream names

```elixir
defmodule Binance.SpotAdapter do
  use GenServer
  require Logger

  alias ZenWebsocket.Client

  @base_url "wss://stream.binance.com:9443/ws"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def subscribe(adapter, streams) when is_list(streams) do
    GenServer.call(adapter, {:subscribe, streams})
  end

  @impl true
  def init(opts) do
    state = %{
      api_key: opts[:api_key],
      api_secret: opts[:api_secret],
      client: nil,
      client_ref: nil,
      subscriptions: MapSet.new(),
      request_id: 1
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    # Binance uses ping/pong frames at WebSocket level
    connect_opts = [
      heartbeat_config: %{type: :ping_pong, interval: 30_000},
      reconnect_on_error: false
    ]

    case Client.connect(@base_url, connect_opts) do
      {:ok, client} ->
        ref = Process.monitor(client.server_pid)
        new_state = %{state | client: client, client_ref: ref}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, streams}, _from, state) do
    # Binance subscription format (no JSON-RPC)
    msg = %{
      "method" => "SUBSCRIBE",
      "params" => streams,
      "id" => state.request_id
    }

    case Client.send_message(state.client, msg) do
      :ok ->
        new_subs = Enum.reduce(streams, state.subscriptions, &MapSet.put(&2, &1))
        {:reply, :ok, %{state | subscriptions: new_subs, request_id: state.request_id + 1}}

      error ->
        {:reply, error, state}
    end
  end

  # Signed request for user data stream
  def create_listen_key(adapter) do
    GenServer.call(adapter, :create_listen_key)
  end

  @impl true
  def handle_call(:create_listen_key, _from, state) do
    timestamp = System.system_time(:millisecond)
    query = "timestamp=#{timestamp}"

    signature =
      :crypto.mac(:hmac, :sha256, state.api_secret, query)
      |> Base.encode16(case: :lower)

    # Note: Listen key creation is via REST API, not WebSocket
    # This shows the HMAC pattern used by Binance
    {:reply, {:ok, signature}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{client_ref: ref} = state) do
    Logger.warning("Binance client down: #{inspect(reason)}")

    new_state = %{state | client: nil, client_ref: nil}
    Process.send_after(self(), :reconnect, 5_000)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    case do_connect(state) do
      {:ok, connected_state} ->
        restore_subscriptions(connected_state)
      {:error, _} ->
        Process.send_after(self(), :reconnect, 10_000)
        {:noreply, state}
    end
  end

  defp do_connect(state) do
    connect_opts = [
      heartbeat_config: %{type: :ping_pong, interval: 30_000},
      reconnect_on_error: false
    ]

    case Client.connect(@base_url, connect_opts) do
      {:ok, client} ->
        ref = Process.monitor(client.server_pid)
        {:ok, %{state | client: client, client_ref: ref}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp restore_subscriptions(state) do
    streams = MapSet.to_list(state.subscriptions)

    if streams != [] do
      msg = %{"method" => "SUBSCRIBE", "params" => streams, "id" => state.request_id}
      Client.send_message(state.client, msg)
    end

    {:noreply, %{state | request_id: state.request_id + 1}}
  end
end
```

**Key differences from Deribit:**
- Uses `"method" => "SUBSCRIBE"` instead of JSON-RPC
- Authentication via HMAC signatures (typically for REST, user data streams)
- Stream names like `"btcusdt@trade"` instead of channel objects
- Ping/pong heartbeats handled at WebSocket frame level

## Testing Your Adapter

### Unit Tests
```elixir
defmodule YourExchange.AdapterTest do
  use ExUnit.Case
  
  alias YourExchange.Adapter
  
  describe "reconnection handling" do
    test "reconnects on client process death" do
      {:ok, adapter} = Adapter.start_link(url: "wss://test.exchange.com")
      
      # Connect
      assert :ok = Adapter.connect(adapter)
      
      # Get client process
      state = :sys.get_state(adapter)
      client_pid = state.client.server_pid
      
      # Kill client process
      Process.exit(client_pid, :kill)
      
      # Adapter should reconnect
      :timer.sleep(100)
      
      new_state = :sys.get_state(adapter)
      assert new_state.client != nil
      assert new_state.client.server_pid != client_pid
    end
  end
end
```

### Integration Tests
```elixir
@tag :integration
test "maintains subscriptions across reconnection" do
  {:ok, adapter} = Adapter.start_link(
    url: "wss://test.exchange.com",
    api_key: "test_key",
    api_secret: "test_secret"
  )
  
  # Connect and subscribe
  :ok = Adapter.connect(adapter)
  :ok = Adapter.subscribe(adapter, ["trades.BTC-USD"])
  
  # Force disconnection
  state = :sys.get_state(adapter)
  Process.exit(state.client.server_pid, :kill)
  
  # Wait for reconnection
  :timer.sleep(1000)
  
  # Verify subscription restored
  assert subscription_active?(adapter, "trades.BTC-USD")
end
```

## Troubleshooting

### Common Issues

1. **Duplicate Reconnection Attempts**
   - Symptom: Multiple connection attempts, resource exhaustion
   - Solution: Ensure `reconnect_on_error: false` is set

2. **Lost Subscriptions**
   - Symptom: No data after reconnection
   - Solution: Track subscriptions in adapter state, restore after auth

3. **Authentication Failures**
   - Symptom: Can't restore authenticated state
   - Solution: Store credentials securely, handle auth errors gracefully

4. **Memory Leaks**
   - Symptom: Growing process count
   - Solution: Ensure old monitors are cleaned up, Gun processes terminate

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

- [Performance Tuning Guide](performance_tuning.md) - Optimize timeouts, reconnection, rate limiting, and memory usage
