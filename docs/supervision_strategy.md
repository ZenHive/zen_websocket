# ZenWebsocket Supervision Strategy

## Overview

ZenWebsocket provides optional supervision for WebSocket client connections, ensuring resilience and automatic recovery from failures. This is critical for financial trading systems where connection stability directly impacts order execution and risk management.

**Important**: As a library, ZenWebsocket does not start any supervisors automatically. You must explicitly add supervision to your application's supervision tree when needed.

## Architecture

```
Your Application Supervisor
    ├── ZenWebsocket.ClientSupervisor (Optional DynamicSupervisor)
    │       ├── Client GenServer 1
    │       ├── Client GenServer 2
    │       └── Client GenServer N
    └── Your other children...
```

## Key Components

### 1. ClientSupervisor (`ZenWebsocket.ClientSupervisor`)
- DynamicSupervisor for managing client connections
- Restart strategy: `:one_for_one` (isolated failures)
- Maximum 10 restarts in 60 seconds (configurable)
- Each client runs independently

### 2. Client GenServer (`ZenWebsocket.Client`)
- Manages individual WebSocket connections
- Handles Gun process ownership and message routing
- Integrated heartbeat handling
- Automatic reconnection on network failures

## Usage Patterns

### Pattern 1: No Supervision (Simple/Testing)

```elixir
# Direct connection without supervision
{:ok, client} = ZenWebsocket.Client.connect("wss://example.com")

# Use the client
ZenWebsocket.Client.send_message(client, "Hello")

# Clean up when done
ZenWebsocket.Client.close(client)
```

### Pattern 2: Using ClientSupervisor

First, add the supervisor to your application:

```elixir
defmodule MyApp.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Add the ZenWebsocket supervisor
      ZenWebsocket.ClientSupervisor,
      # Your other children...
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Then create supervised connections:

```elixir
# Basic supervised connection
{:ok, client} = ZenWebsocket.ClientSupervisor.start_client("wss://example.com")

# With configuration
{:ok, client} = ZenWebsocket.ClientSupervisor.start_client("wss://example.com",
  retry_count: 10,
  heartbeat_config: %{type: :deribit, interval: 30_000}
)
```

### Pattern 3: Direct Client Supervision

Add individual clients directly to your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Supervise individual clients
      {ZenWebsocket.Client, [
        url: "wss://exchange1.com",
        id: :exchange1_client,
        heartbeat_config: %{type: :deribit, interval: 30_000}
      ]},
      {ZenWebsocket.Client, [
        url: "wss://exchange2.com", 
        id: :exchange2_client
      ]},
      # Your other children...
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Restart Behavior

The restart strategy depends on which pattern started the client — the two
differ, and the difference matters when you shut a client down deliberately.

### Pattern 2 — transient (`ClientSupervisor.start_client/2`)
`ClientSupervisor` builds its child spec with `restart: :transient`:
- Clients are restarted only if they exit abnormally
- Normal shutdowns (via `Client.close/1`) don't trigger restart
- Crashes and connection failures trigger automatic restart

### Pattern 3 — permanent (`{ZenWebsocket.Client, opts}` in your own tree)
`Client.child_spec/1` sets `restart: :permanent`, so a client added directly to
a supervision tree is restarted on **every** exit, including a clean
`Client.close/1`. If you want transient semantics here, override it yourself:

```elixir
Supervisor.child_spec({ZenWebsocket.Client, url: "wss://exchange1.com"},
  restart: :transient
)
```

### Failure Scenarios

1. **Network Disconnection**
   - Client detects connection loss
   - Attempts internal reconnection (configurable retries)
   - If max retries exceeded, GenServer exits
   - Supervisor restarts the client

2. **Process Crash**
   - Supervisor immediately detects exit
   - Starts new client process
   - Connection re-established from scratch

3. **Heartbeat Failure**
   - Client tracks heartbeat failures
   - Closes connection after threshold
   - Supervisor restarts for fresh connection

## Production Considerations

### 1. Resource Management
- Each supervised client consumes:
  - 1 Erlang process (Client GenServer)
  - 1 Gun connection process
  - Associated memory for state and buffers

### 2. Restart Limits
- Default: 10 restarts in 60 seconds
- Prevents restart storms
- Adjust based on expected failure patterns

### 3. Monitoring
```elixir
# List all supervised clients
clients = ZenWebsocket.ClientSupervisor.list_clients()

# Check client health
health = ZenWebsocket.Client.get_heartbeat_health(client)
```

### 4. Graceful Shutdown
```elixir
# Stop a specific client
ZenWebsocket.ClientSupervisor.stop_client(pid)

# Client won't be restarted (normal termination)
```

## Best Practices

1. **Use Supervision for Production**
   - Always use `ClientSupervisor.start_client/2` for production
   - Direct connections only for testing/development

2. **Configure Appropriate Timeouts**
   - Set heartbeat intervals based on exchange requirements
   - Configure retry counts for network conditions

3. **Monitor Client Health**
   - Implement health checks using `get_heartbeat_health/1`
   - Set up alerts for excessive restarts

4. **Handle Restart Events**
   - Subscriptions may need re-establishment
   - Authentication may need renewal
   - Order state should be reconciled

## Example: Production Deribit Connection

```elixir
defmodule TradingSystem.DeribitConnection do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Start supervised connection
    url = "wss://test.deribit.com/ws/api/v2"
    config = [
      heartbeat_config: %{type: :deribit, interval: 30_000},
      retry_count: 10,
      retry_delay: 1000
    ]
    
    {:ok, client} = ZenWebsocket.ClientSupervisor.start_client(url, config)
    
    # Create adapter with supervised client
    adapter = %ZenWebsocket.Examples.DeribitAdapter{
      client: client,
      authenticated: false,
      subscriptions: MapSet.new(),
      client_id: opts[:client_id],
      client_secret: opts[:client_secret]
    }
    
    # Authenticate and subscribe
    {:ok, adapter} = ZenWebsocket.Examples.DeribitAdapter.authenticate(adapter)
    {:ok, adapter} = ZenWebsocket.Examples.DeribitAdapter.subscribe(adapter, [
      "book.BTC-PERPETUAL.raw",
      "trades.BTC-PERPETUAL.raw",
      "user.orders.BTC-PERPETUAL.raw"
    ])
    
    {:ok, %{adapter: adapter}}
  end
  
  # Handle reconnection events
  def handle_info({:gun_down, _, _, _, _}, state) do
    # Log disconnection
    Logger.warn("Deribit connection lost, supervisor will restart")
    {:noreply, state}
  end
end
```

## Supervision Tree Visualization

```
YourApp.Supervisor
    ├── ZenWebsocket.ClientSupervisor
    │       ├── Client_1 (Deribit Production)
    │       ├── Client_2 (Deribit Test)
    │       └── Client_3 (Binance)
    └── YourApp.TradingEngine
```

ZenWebsocket is a library: `application/0` declares no `mod:`. Start `ClientSupervisor` in the host application's supervision tree.

The supervision strategy ensures that WebSocket connections remain stable and automatically recover from failures, critical for 24/7 financial trading operations.
