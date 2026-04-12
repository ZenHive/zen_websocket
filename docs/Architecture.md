# ZenWebsocket Architecture

## Overview

ZenWebsocket is a production-grade WebSocket client library built on top of Gun. It provides a simple, reliable interface for WebSocket communications with a focus on financial trading systems.

## Core Design Principles

1. **Simplicity First** - Target 5 functions per new module, 15 lines per function (existing core modules may exceed this)
2. **Real-World Testing** - No mocks, only real API testing
3. **Financial-Grade Reliability** - Built for high-frequency trading systems
4. **Minimal Abstraction** - Direct Gun API usage, no unnecessary wrappers

## Architecture Layers

### 1. Transport Layer (Gun)
- Direct integration with Gun for WebSocket connections
- HTTP/1.1 ALPN negotiation for WSS upgrades (avoids Cloudflare HTTP/2 stripping of Connection: Upgrade)
- Connection monitoring and lifecycle management

### 2. Core Modules

#### Client (`client.ex`)
The main interface for WebSocket operations:
- `connect/2` - Establish WebSocket connection
- `send_message/2` - Send binary messages to server
- `close/1` - Close connection gracefully
- `subscribe/2` - Subscribe to data channels
- `get_state/1` - Retrieve connection state (`:connecting`, `:connected`, `:disconnected`)
- `get_latency_stats/1` - Get p50/p99 latency percentiles
- `get_heartbeat_health/1` - Get heartbeat health metrics
- `get_state_metrics/1` - Get detailed connection metrics
- `reconnect/1` - Explicitly reconnect

#### Config (`config.ex`)
Configuration struct and validation:
- `new/2`, `new!/2` - Create and validate configuration
- Supports: url, headers, timeout, retry_count, retry_delay, heartbeat_interval, max_backoff, reconnect_on_error, restore_subscriptions, request_timeout, debug, latency_buffer_size, record_to

#### Frame (`frame.ex`)
WebSocket frame handling:
- `text/1`, `binary/1` - Encode text/binary frames
- `ping/0`, `pong/1` - Control frames
- `decode/1` - Decode incoming frames

#### Reconnection (`reconnection.ex`)
Automatic reconnection with exponential backoff:
- `establish_connection/1` - Establish Gun connection
- `calculate_backoff/3` - Exponential backoff calculation
- `should_reconnect?/1` - Error-based reconnection decision
- `max_retries_exceeded?/2` - Retry limit check

#### Message Handler (`message_handler.ex`)
Message routing and processing:
- `handle_message/2` - Route incoming Gun messages
- `decode_and_handle_control/1` - Decode and handle control frames
- `create_handler/1` - Create callback handler for message types

#### Error Handler (`error_handler.ex`)
Comprehensive error management:
- `categorize_error/1` - Classify as `:recoverable` or `:fatal`
- `handle_error/1` - Return `:reconnect` or `:stop` action
- `explain/1` - Human-readable error with suggestion and docs URL

### 3. Protocol Support

#### JSON-RPC (`json_rpc.ex`)
JSON-RPC 2.0 support:
- `build_request/2` - Build JSON-RPC request
- `match_response/1` - Match response/notification/error
- `defrpc/2` - Macro for generating RPC method functions

#### Request Correlator (`request_correlator.ex`)
Request/response correlation tracking:
- `track/4` - Track pending request with timeout
- `resolve/2` - Resolve response by ID
- `timeout/2` - Handle request timeout
- Telemetry events for tracking, resolution, and timeout

### 4. Infrastructure Modules

#### Connection Registry (`connection_registry.ex`)
ETS-based connection tracking:
- Fast connection lookups via `get/1`
- Process monitoring with `register/2`
- Automatic cleanup via `cleanup_dead/1`

#### Rate Limiter (`rate_limiter.ex`)
Token bucket rate limiting:
- Exchange-specific cost functions (`deribit_cost/1`, `binance_cost/1`, `simple_cost/1`)
- Queue-based backpressure with pressure levels
- Configurable refill rate and max queue size

#### Heartbeat Manager (`heartbeat_manager.ex`)
Heartbeat lifecycle management:
- Platform-specific heartbeat types (`:deribit`, `:ping_pong`, `:binance`)
- RTT tracking via telemetry
- Timer management

#### Subscription Manager (`subscription_manager.ex`)
Subscription tracking and restoration:
- Track confirmed subscriptions
- Build restore messages for reconnection
- Telemetry events for add/remove/restore

#### Latency Stats (`latency_stats.ex`)
Bounded circular buffer for latency tracking:
- `add/2` - Record latency sample
- `summary/1` - Get p50/p99/last/count

#### Debug (`debug.ex`)
Debug logging utility:
- `log/2` - Log when debug mode enabled (no-op otherwise)

### 5. Session Recording

#### Recorder (`recorder.ex`)
Pure functions for session recording:
- `format_entry/3` - Format frame as JSONL line
- `replay/3` - Replay recorded session
- `metadata/1` - Get session statistics

#### Recorder Server (`recorder_server.ex`)
Async file I/O for recording:
- Buffered writes with periodic flush
- Non-blocking `record/3` via send

### 6. Pool Management

#### Client Supervisor (`client_supervisor.ex`)
DynamicSupervisor for connection pools:
- `start_client/2` - Start supervised client
- `send_balanced/2` - Health-based load balancing with failover
- Custom client discovery via `:client_discovery` option
- Lifecycle callbacks (`:on_connect`, `:on_disconnect`)

#### Pool Router (`pool_router.ex`)
Health-based connection routing:
- Health scoring (0-100) based on pending requests, latency, errors, pressure
- Round-robin fallback for equal health
- Error recording with 60s decay

### 7. Testing

#### Testing (`testing.ex`)
Consumer-facing test utilities:
- `start_mock_server/1` - Start mock WebSocket server
- `inject_message/2` - Send message from server to client
- `assert_message_sent/3` - Verify client sent expected message
- `simulate_disconnect/2` - Trigger disconnect scenarios

### 8. Platform Adapters

#### Deribit Adapter (`examples/deribit_adapter.ex`)
Reference implementation for exchange integration:
- Authentication flow
- Heartbeat management
- Subscription handling
- Cancel-on-disconnect protection

## Data Flow

```
User Code
    |
    v
Client API (connect, send, subscribe, close, monitoring)
    |
    +---> RequestCorrelator (track/resolve/timeout)
    |
    v
Message Handler <---> JSON-RPC
    |                    |
    v                    v
Frame Encoder      Rate Limiter
    |                    |
    v                    v
Gun Transport <---> WebSocket Server
    |
    +---> HeartbeatManager (ping/pong, RTT tracking)
    +---> SubscriptionManager (track, restore on reconnect)
    +---> LatencyStats (p50/p99 circular buffer)
    +---> Recorder/RecorderServer (JSONL session capture)
    |
    v
Error Handler --> Reconnection

ClientSupervisor ---> PoolRouter (health scoring, failover)
                 ---> ConnectionRegistry (ETS lookup)
```

## State Management

### Connection State
- Managed by Client GenServer
- Includes: connection status, subscriptions, pending requests
- Preserved across reconnections

### Registry State
- ETS table for O(1) lookups
- Stores: PID to connection mappings
- Automatic cleanup on process termination

### Rate Limiter State
- Token bucket per connection
- Configurable refill rates
- Burst capacity tracking

## Error Handling Strategy

1. **Connection Errors**: Trigger automatic reconnection
2. **Protocol Errors**: Log and notify user callback
3. **Authentication Errors**: Halt and require user intervention
4. **Application Errors**: Pass through to user code

## Supervision Strategy

### Client Supervisor
- Simple one-for-one strategy
- Restart clients on failure
- Configurable restart intensity

### Adapter Supervision
- Platform adapters handle their own supervision
- Separation of concerns between transport and business logic
- Clean restart semantics

## Performance Considerations

1. **ETS for Fast Lookups**: Connection registry uses ETS
2. **Direct Gun API**: No abstraction overhead
3. **Efficient Frame Processing**: Minimal allocations
4. **Telemetry Integration**: Observable performance metrics

## Extension Points

### Custom Adapters
1. Implement authentication for your platform
2. Handle platform-specific message formats
3. Add custom subscription logic
4. Integrate with platform features

### Custom Protocols
1. Extend message handler for new formats
2. Add protocol-specific frame handling
3. Implement custom correlation strategies

## Testing Architecture

### Unit Tests
- Test individual modules in isolation
- Use local mock servers (not mocks!)
- Verify edge cases and error conditions

### Integration Tests
- Test against real APIs (test.deribit.com)
- Verify end-to-end functionality
- Test reconnection scenarios
- Measure real-world performance

### Stability Tests
- Long-running connection tests
- High-frequency message testing
- Network interruption simulation
- Memory leak detection

## Security Considerations

1. **TLS by Default**: All connections use TLS
2. **Credential Management**: Environment variables for secrets
3. **No Credential Logging**: Sensitive data never logged
4. **Secure Frame Masking**: Client-side frame masking

## Monitoring and Observability

### Telemetry Events
- Connection lifecycle events
- Message send/receive metrics
- Error occurrence tracking
- Performance measurements

### Health Checks
- Connection state monitoring
- Heartbeat status
- Rate limit utilization
- Queue depth tracking