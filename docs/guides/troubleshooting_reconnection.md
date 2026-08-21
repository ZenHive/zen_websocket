# Troubleshooting Reconnection Guide

## Overview

This guide helps diagnose and resolve common reconnection issues in ZenWebsocket. It covers debugging techniques, performance considerations, and monitoring strategies for production deployments.

## Common Reconnection Issues

### 1. Duplicate Reconnection Attempts

**Symptoms:**
- Multiple connection attempts in logs
- Resource exhaustion (too many processes)
- Rapid connection/disconnection cycles

**Root Cause:**
Both Client and Adapter attempting reconnection independently.

**Solution:**
```elixir
# In your adapter's do_connect function
connect_opts = [
  reconnect_on_error: false,  # MUST be false for adapters
  heartbeat_config: %{...}
]
```

**Verification:**
```elixir
# Check client configuration. `Client.get_state/1` returns only the connection
# state atom (:connecting | :connected | :disconnected); the config lives on the
# client struct that `connect/2` handed back.
IO.inspect(client.config.reconnect_on_error)  # Should be false
IO.inspect(Client.get_state(client))          # :connected | :connecting | :disconnected
```

### 2. Lost Subscriptions After Reconnection

**Symptoms:**
- No market data after reconnection
- Missing account updates
- Silent connection (no data flow)

**Root Cause:**
Adapter not tracking or restoring subscriptions.

**Solution:**
```elixir
defmodule YourAdapter do
  # Track subscriptions in state
  defstruct [..., subscriptions: MapSet.new()]
  
  def handle_call({:subscribe, channels}, _from, state) do
    # Send subscription request
    Client.send_message(state.client, build_sub_msg(channels))
    
    # Track in state
    new_subs = MapSet.union(state.subscriptions, MapSet.new(channels))
    {:reply, :ok, %{state | subscriptions: new_subs}}
  end
  
  # Restore after reconnection
  defp restore_subscriptions(state) do
    Enum.each(state.subscriptions, fn channel ->
      Client.send_message(state.client, build_sub_msg([channel]))
    end)
  end
end
```

### 3. Authentication Failures on Reconnection

**Symptoms:**
- Reconnection succeeds but authenticated endpoints fail
- "Unauthorized" errors after reconnection
- Orders rejected after reconnection

**Root Cause:**
Authentication state not restored after creating new connection.

**Solution:**
```elixir
# Store credentials securely
defmodule YourAdapter do
  defstruct [
    ...,
    client_id: nil,
    client_secret: nil,
    auth_token: nil,
    auth_expiry: nil
  ]
  
  defp do_connect(state) do
    with {:ok, client} <- Client.connect(url, opts),
         {:ok, auth_state} <- authenticate(client, state),
         {:ok, final_state} <- restore_subscriptions(auth_state) do
      {:ok, final_state}
    end
  end
  
  defp authenticate(client, state) do
    # Re-authenticate with stored credentials
    auth_msg = build_auth_message(state.client_id, state.client_secret)
    Client.send_message(client, auth_msg)
    # ... handle response
  end
end
```

### 4. Memory Leaks from Failed Connections

**Symptoms:**
- Growing process count
- Increasing memory usage
- Eventually: system out of memory

**Root Cause:**
Gun processes not being properly cleaned up.

**Solution:**
```elixir
# Always demonitor before creating new connection
defp cleanup_old_connection(state) do
  if state.monitor_ref do
    Process.demonitor(state.monitor_ref, [:flush])
  end
  
  %{state | client: nil, monitor_ref: nil}
end

defp do_connect(state) do
  # Clean up first
  clean_state = cleanup_old_connection(state)
  
  # Then connect
  case Client.connect(url, opts) do
    {:ok, client} ->
      ref = Process.monitor(client.server_pid)
      %{clean_state | client: client, monitor_ref: ref}
  end
end
```

### 5. Reconnection Storms

**Symptoms:**
- Hundreds of reconnection attempts
- Server rejecting connections
- Rate limiting or IP bans

**Root Cause:**
No backoff strategy or circuit breaker.

**Solution:**
```elixir
defmodule YourAdapter do
  defstruct [
    ...,
    reconnect_attempts: 0,
    last_reconnect: nil,
    max_attempts: 10
  ]
  
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if state.reconnect_attempts >= state.max_attempts do
      Logger.error("Max reconnection attempts reached, giving up")
      {:stop, :max_reconnections_exceeded, state}
    else
      # Exponential backoff
      delay = calculate_backoff(state.reconnect_attempts)
      Process.send_after(self(), :reconnect, delay)
      
      {:noreply, %{state | 
        reconnect_attempts: state.reconnect_attempts + 1,
        last_reconnect: DateTime.utc_now()
      }}
    end
  end
  
  defp calculate_backoff(attempts) do
    # 1s, 2s, 4s, 8s, 16s, 32s, 60s max
    min(1000 * :math.pow(2, attempts), 60_000)
  end
end
```

## Debugging Connection Failures

### Enable Detailed Logging

```elixir
# In your config/config.exs
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function, :line]

# Add logging to your adapter
defmodule YourAdapter do
  require Logger
  
  defp do_connect(state) do
    Logger.debug("Attempting connection to #{state.url}")
    
    case Client.connect(state.url, opts) do
      {:ok, client} ->
        Logger.info("Successfully connected")
        {:ok, client}
      {:error, reason} ->
        Logger.error("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

### Use Telemetry Events

```elixir
# Emit telemetry events
:telemetry.execute(
  [:your_app, :websocket, :reconnection, :attempt],
  %{count: state.reconnect_attempts},
  %{url: state.url, reason: reason}
)

# Monitor in another process
:telemetry.attach(
  "websocket-reconnection-monitor",
  [:your_app, :websocket, :reconnection, :attempt],
  fn _event, measurements, metadata, _config ->
    IO.puts("Reconnection attempt #{measurements.count} for #{metadata.url}")
  end,
  nil
)
```

### Inspect Process State

```elixir
# During runtime debugging
state = :sys.get_state(your_adapter_pid)
IO.inspect(state, label: "Adapter state")

# Check if client is alive
if state.client do
  client_state = Client.get_state(state.client)
  IO.inspect(client_state, label: "Client state")
end

# List all Gun connections
:gun.info()
|> Enum.each(fn {pid, info} ->
  IO.inspect({pid, info}, label: "Gun connection")
end)
```

## Performance Considerations

### 1. Connection Pooling

For high-frequency reconnection scenarios:

```elixir
defmodule ConnectionPool do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_connection() do
    GenServer.call(__MODULE__, :get_connection)
  end
  
  def init(opts) do
    # Pre-create connections
    connections = for _ <- 1..opts[:size] do
      {:ok, client} = Client.connect(opts[:url], reconnect_on_error: false)
      client
    end
    
    {:ok, %{connections: connections, available: connections}}
  end
end
```

### 2. Circuit Breaker Pattern

Prevent cascading failures:

```elixir
defmodule CircuitBreaker do
  defstruct [
    state: :closed,  # :closed, :open, :half_open
    failure_count: 0,
    failure_threshold: 5,
    timeout: 60_000,
    last_failure: nil
  ]
  
  def call(breaker, fun) do
    case breaker.state do
      :open ->
        if time_to_retry?(breaker) do
          try_half_open(breaker, fun)
        else
          {:error, :circuit_open}
        end
      
      :closed ->
        execute_with_breaker(breaker, fun)
      
      :half_open ->
        execute_with_breaker(breaker, fun)
    end
  end
end
```

### 3. Resource Monitoring

Monitor system resources:

```elixir
defmodule ResourceMonitor do
  def check_resources() do
    %{
      process_count: :erlang.system_info(:process_count),
      memory: :erlang.memory(:total),
      gun_connections: length(:gun.info()),
      ets_tables: length(:ets.all())
    }
  end
  
  def alert_if_high() do
    resources = check_resources()
    
    if resources.process_count > 10_000 do
      Logger.error("High process count: #{resources.process_count}")
    end
    
    if resources.gun_connections > 100 do
      Logger.error("High Gun connection count: #{resources.gun_connections}")
    end
  end
end
```

## Monitoring Recommendations

### 1. StatsD/Prometheus Metrics

```elixir
defmodule Metrics do
  def record_reconnection(reason) do
    :telemetry.execute(
      [:websocket, :reconnection],
      %{count: 1},
      %{reason: reason}
    )
  end
  
  def record_connection_duration(start_time) do
    duration = System.monotonic_time() - start_time
    
    :telemetry.execute(
      [:websocket, :connection, :duration],
      %{duration: duration},
      %{}
    )
  end
end
```

### 2. Health Checks

```elixir
defmodule HealthCheck do
  def check_websocket_health(adapter) do
    case GenServer.call(adapter, :get_state, 5000) do
      {:ok, state} when state.connected ->
        {:ok, "WebSocket connected"}
      
      {:ok, state} ->
        {:error, "WebSocket disconnected", state}
      
      {:error, :timeout} ->
        {:error, "Adapter not responding"}
    end
  end
end
```

### 3. Alerting Rules

Set up alerts for:
- Connection failure rate > 10% over 5 minutes
- Average reconnection time > 30 seconds
- Process count growth > 1000 per hour
- Memory usage growth > 100MB per hour

## Testing Reconnection Scenarios

### Simulate Network Failures

```elixir
defmodule NetworkSimulator do
  def drop_connection(client) do
    # The Gun pid is on the client struct, not on `get_state/1` (which returns
    # a bare state atom). Note it is a snapshot from connect time: after a
    # reconnect the client struct you hold points at the previous Gun process.
    Process.exit(client.gun_pid, :kill)
  end
  
  def block_traffic(duration) do
    # Use iptables or similar to block traffic
    System.cmd("sudo", ["iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "443", "-j", "DROP"])
    :timer.sleep(duration)
    System.cmd("sudo", ["iptables", "-D", "OUTPUT", "-p", "tcp", "--dport", "443", "-j", "DROP"])
  end
end
```

### Load Testing

```elixir
defmodule LoadTest do
  def stress_reconnection(adapter, iterations) do
    for i <- 1..iterations do
      Task.start(fn ->
        # Force disconnection
        state = :sys.get_state(adapter)
        Process.exit(state.client.server_pid, :kill)
        
        # Wait for reconnection
        :timer.sleep(1000)
        
        # Verify reconnected
        new_state = :sys.get_state(adapter)
        assert new_state.connected
      end)
      
      :timer.sleep(100)  # Stagger disconnections
    end
  end
end
```

## Quick Diagnosis Checklist

When experiencing reconnection issues:

1. **Check Configuration**
   ```elixir
   # Is reconnect_on_error set correctly?
   IO.inspect(state.config.reconnect_on_error)
   ```

2. **Verify Process Monitoring**
   ```elixir
   # Is the monitor ref valid?
   IO.inspect(Process.info(self(), :monitors))
   ```

3. **Check Gun Processes**
   ```elixir
   # How many Gun connections exist?
   IO.inspect(length(:gun.info()))
   ```

4. **Review Logs**
   ```bash
   grep -i "reconnect\|connection\|gun" app.log | tail -100
   ```

5. **Monitor Resources**
   ```elixir
   # Check system resources
   IO.inspect(:erlang.memory())
   IO.inspect(:erlang.system_info(:process_count))
   ```

## Summary

Successful reconnection troubleshooting requires:
1. Understanding the dual-layer architecture
2. Proper configuration (`reconnect_on_error: false` for adapters)
3. Comprehensive logging and monitoring
4. Testing failure scenarios
5. Resource management and cleanup

Follow this guide's patterns to build robust, production-ready WebSocket connections for financial trading systems.