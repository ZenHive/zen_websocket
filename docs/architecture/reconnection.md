# Reconnection Architecture Guide

## Overview

ZenWebsocket implements a dual-layer reconnection architecture that provides both network-level and process-level reliability. This design leverages Gun's flexible process ownership model to ensure robust connection management for financial trading systems.

## Dual-Layer Design Rationale

### Layer 1: Client-Level Reconnection (Network Recovery)
The `ZenWebsocket.Client` GenServer provides built-in reconnection for network-level failures:
- Handles temporary network outages
- Manages WebSocket protocol errors
- Preserves connection state during recovery
- Configurable via `reconnect_on_error` option (default: true)

### Layer 2: Adapter-Level Supervision (Process Recovery)
Platform adapters like `DeribitGenServerAdapter` provide process-level supervision:
- Monitors Client process health
- Handles complete process crashes
- Restores authentication state
- Re-establishes subscriptions
- Always sets `reconnect_on_error: false` to prevent duplicate attempts

## Gun Process Ownership Model

Gun creates a dedicated process for each WebSocket connection with flexible ownership:

```
┌─────────────────┐
│   Client        │
│  GenServer      │─── owns ──→ ┌─────────────┐
└─────────────────┘             │ Gun Process │
                                └─────────────┘
```

**Key Features:**
1. The process that creates the Gun connection owns it initially
2. Gun sends all messages to the owning process
3. Ownership can be transferred between processes if needed
4. If owner dies, Gun process terminates
5. New connections require new Gun processes

This ownership model enables our Client GenServer to directly receive and handle all Gun messages, including WebSocket frames and heartbeats.

## When to Use Each Reconnection Mechanism

### Use Client-Level Reconnection (Standalone Pattern)
For simple use cases without complex state requirements:

```elixir
# Client handles its own reconnection
{:ok, client} = Client.connect(url)  # reconnect_on_error: true (default)
```

**Characteristics:**
- Network failures trigger automatic reconnection
- Connection state preserved
- No authentication restoration
- No subscription restoration
- Suitable for read-only market data

### Use Adapter-Level Supervision (Supervised Pattern)
For production trading systems requiring full state restoration:

```elixir
# Adapter disables client reconnection
connect_opts = [
  reconnect_on_error: false,  # Client stops cleanly on errors
  heartbeat_config: %{...}    # Other options preserved
]
```

**Characteristics:**
- Adapter monitors Client process
- Full state restoration on crashes
- Authentication automatically restored
- Subscriptions re-established
- Cancel-on-disconnect protection maintained

## Message and Failure Flows

### Normal Operation Flow
```
User Request
    ↓
Adapter GenServer
    ↓
Client GenServer
    ↓
Gun Process ←──── WebSocket ────→ Exchange
    ↓
Client GenServer (receives Gun messages directly)
    ↓
Adapter GenServer
    ↓
User Response
```

### Network Failure with Client Reconnection
```
Network Failure Detected
    ↓
Gun Process notifies Client GenServer
    ↓
Client checks reconnect_on_error
    ↓
If true: Exponential backoff retry
    ↓
Create new Gun process (Client owns it)
    ↓
Re-establish WebSocket
    ↓
Resume message flow
```

### Process Crash with Adapter Supervision
```
Client Process Crash
    ↓
Adapter receives {:DOWN, ...}
    ↓
Adapter initiates reconnection
    ↓
Create new Client (reconnect_on_error: false)
    ↓
New Client creates Gun process (owns it)
    ↓
Restore authentication
    ↓
Re-establish subscriptions
    ↓
Resume trading operations
```

## Architecture Decision Records

### ADR-001: Dual-Layer Reconnection
**Context:** Different use cases require different reconnection strategies.
**Decision:** Implement reconnection at both Client and Adapter layers.
**Consequences:** Clear separation of concerns, no duplicate attempts, flexible deployment.

### ADR-002: Configuration-Based Behavior
**Context:** Need to prevent duplicate reconnection attempts in supervised scenarios.
**Decision:** Use `reconnect_on_error` flag to control Client behavior.
**Consequences:** Backward compatibility maintained, explicit configuration required.

### ADR-003: Client GenServer Owns Gun Connection
**Context:** Gun sends messages to the owning process; integrated heartbeat needs these messages.
**Decision:** Client GenServer always owns the Gun connection it creates.
**Consequences:** Direct message handling, simplified architecture, no message forwarding needed.

### ADR-004: Adapter Ownership of Reconnection Logic
**Context:** Production systems need full state restoration beyond network recovery.
**Decision:** Adapters always disable Client reconnection and handle it themselves.
**Consequences:** Consistent pattern, predictable behavior, simplified debugging.

## Performance Considerations

1. **Connection Pooling**: Each reconnection creates a new Gun process. Consider connection pooling for high-frequency reconnection scenarios.

2. **Exponential Backoff**: Both layers implement exponential backoff to prevent thundering herd problems.

3. **State Restoration Cost**: Adapter-level reconnection has higher overhead due to authentication and subscription restoration.

4. **Memory Usage**: Failed Gun processes are garbage collected. Monitor process count during extended outages.

5. **Message Routing**: Client GenServer owns Gun connection, eliminating message forwarding overhead.

## Best Practices

1. **Always use supervised pattern for production trading**
2. **Monitor both Client and Adapter processes**
3. **Implement circuit breakers for persistent failures**
4. **Log reconnection attempts with correlation IDs**
5. **Test reconnection scenarios in staging environments**
6. **Set appropriate timeout values for your latency requirements**
7. **Ensure Client GenServer owns Gun connection for direct message handling**

## Implementation Details

### Client Configuration
```elixir
defmodule ZenWebsocket.Config do
  defstruct [
    # ... other fields ...
    reconnect_on_error: true,  # Default: enabled for standalone use
    # ... other fields ...
  ]
end
```

### Adapter Pattern
```elixir
# In adapter's do_connect function
connect_opts = [
  heartbeat_config: %{
    type: :deribit,
    interval: heartbeat_interval
  },
  reconnect_on_error: false  # Critical: prevents duplicate reconnection
]

{:ok, client} = Client.connect(url, connect_opts)
```

### Monitor Pattern
```elixir
# Adapter monitors Client for process-level failures
ref = Process.monitor(client.server_pid)

# Handle Client death
def handle_info({:DOWN, ^ref, :process, _pid, reason}, state) do
  # Initiate adapter-level reconnection with full state restoration
end
```

## Related Documentation

- [Building Adapters Guide](../guides/building_adapters.md)
- [Troubleshooting Reconnection](../guides/troubleshooting_reconnection.md)
- [Gun Integration Guide](../gun_integration.md)
- `ZenWebsocket.Client` — the client module itself
- `ZenWebsocket.Examples.DeribitGenServerAdapter` — supervised adapter example
