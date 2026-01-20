# Performance Tuning Guide

## Overview

This guide covers performance tuning for ZenWebsocket connections. Each parameter affects latency, throughput, memory usage, or reliability—understanding these tradeoffs helps optimize for your specific use case.

## Configuration Parameters

### Timeout Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | 5000ms | Connection establishment timeout |
| `request_timeout` | 30000ms | Timeout for correlated request/response |
| `heartbeat_interval` | 30000ms | Interval between heartbeat pings |

**Tuning guidance:**

```elixir
# Low-latency trading (fast fail, quick detection)
{:ok, client} = Client.connect(url,
  timeout: 3000,           # Fail fast on connection issues
  request_timeout: 5000,   # Don't wait long for responses
  heartbeat_interval: 10_000  # Detect disconnects quickly
)

# High-latency networks (more tolerance)
{:ok, client} = Client.connect(url,
  timeout: 15_000,          # Allow for slow networks
  request_timeout: 60_000,  # Accommodate slow API responses
  heartbeat_interval: 60_000  # Reduce overhead
)
```

### Reconnection Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `retry_count` | 3 | Maximum reconnection attempts |
| `retry_delay` | 1000ms | Base delay for exponential backoff |
| `max_backoff` | 30000ms | Maximum delay between attempts |
| `reconnect_on_error` | true | Enable automatic reconnection |
| `restore_subscriptions` | true | Restore subscriptions after reconnect |

**Exponential backoff formula:**

```
delay = min(retry_delay * 2^attempt, max_backoff)

Attempt 0: 1000ms
Attempt 1: 2000ms
Attempt 2: 4000ms
Attempt 3: 8000ms (capped at 30000ms if max_backoff: 30_000)
```

**Tuning guidance:**

```elixir
# Production trading (aggressive reconnection)
{:ok, client} = Client.connect(url,
  retry_count: 10,         # Many attempts before giving up
  retry_delay: 500,        # Start with short delays
  max_backoff: 10_000,     # Cap at 10 seconds
  reconnect_on_error: true,
  restore_subscriptions: true
)

# Adapter-managed reconnection (disable internal)
{:ok, client} = Client.connect(url,
  reconnect_on_error: false  # Adapter handles all reconnection
)
```

### Latency Monitoring

| Parameter | Default | Description |
|-----------|---------|-------------|
| `latency_buffer_size` | 100 | Samples retained for percentile calculations |

The `LatencyStats` module maintains a circular buffer of request latencies for p50/p99 calculations.

**Memory impact:** Each latency sample stores a microsecond integer (~8 bytes for the raw value). With Erlang term overhead, actual memory usage is higher—expect ~16-24 bytes per sample in practice. For 100 samples, budget ~2 KB per connection.

```elixir
# High-precision latency tracking
{:ok, client} = Client.connect(url,
  latency_buffer_size: 1000  # More samples for smoother percentiles
)

# Memory-constrained environment
{:ok, client} = Client.connect(url,
  latency_buffer_size: 25  # Minimal samples
)
```

**Retrieving latency stats:**

```elixir
{:ok, state} = Client.get_state(client)
# state.latency_stats contains the LatencyStats struct

# Get summary with p50, p99, last sample, count
summary = ZenWebsocket.LatencyStats.summary(state.latency_stats)
# => %{p50: 45, p99: 120, last: 52, count: 100}
```

## Rate Limiter Tuning

The `RateLimiter` module implements a token bucket algorithm supporting different exchange patterns.

### Configuration Options

```elixir
config = %{
  tokens: 100,              # Bucket capacity
  refill_rate: 10,          # Tokens added per interval
  refill_interval: 1000,    # Interval in milliseconds
  max_queue_size: 100,      # Maximum queued requests
  request_cost: &MyModule.cost_function/1
}

{:ok, limiter} = RateLimiter.init(:my_limiter, config)
```

### Exchange-Specific Cost Functions

Different exchanges use different rate limit models:

```elixir
# Deribit: Credit-based (methods have different costs)
config = %{
  tokens: 10_000,           # Deribit gives 10k credits
  refill_rate: 1000,        # Refills 1000/second
  refill_interval: 1000,
  request_cost: &RateLimiter.deribit_cost/1
}

# Built-in cost function:
# - public/* methods: 1 credit
# - private/get_* methods: 5 credits
# - private/set_* methods: 10 credits
# - private/buy, private/sell: 15 credits

# Binance: Weight-based
config = %{
  tokens: 1200,             # 1200 weight per minute
  refill_rate: 20,          # Refill 20 per second
  refill_interval: 1000,
  request_cost: &RateLimiter.binance_cost/1
}

# Simple fixed-rate (Coinbase, etc.)
config = %{
  tokens: 10,               # 10 requests
  refill_rate: 10,          # Full refill
  refill_interval: 1000,    # Per second
  request_cost: &RateLimiter.simple_cost/1
}
```

### Pressure Levels and Backpressure

The rate limiter tracks queue pressure and provides suggested delays:

| Pressure Level | Queue Fill | Suggested Delay |
|---------------|------------|-----------------|
| `:none` | < 25% | 0ms |
| `:low` | 25-50% | 1× refill_interval |
| `:medium` | 50-75% | 2× refill_interval |
| `:high` | 75%+ | 4× refill_interval |

**Using backpressure signals:**

```elixir
{:ok, status} = RateLimiter.status(:my_limiter)
# => %{tokens: 50, queue_size: 30, pressure_level: :medium, suggested_delay_ms: 2000}

if status.suggested_delay_ms > 0 do
  Process.sleep(status.suggested_delay_ms)
end
```

## Telemetry Events

ZenWebsocket emits telemetry events for monitoring. Attach handlers for observability.

### Available Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:zen_websocket, :rate_limiter, :consume]` | `tokens_remaining`, `cost` | `name` |
| `[:zen_websocket, :rate_limiter, :refill]` | `tokens_before`, `tokens_after`, `refill_rate` | `name` |
| `[:zen_websocket, :rate_limiter, :queue]` | `queue_size`, `cost` | `name` |
| `[:zen_websocket, :rate_limiter, :queue_full]` | `queue_size` | `name` |
| `[:zen_websocket, :rate_limiter, :pressure]` | `queue_size`, `ratio` | `name`, `level`, `previous_level` |
| `[:zen_websocket, :request, :start]` | `system_time` | `method`, `id` |
| `[:zen_websocket, :request, :complete]` | `duration_ms` | `method`, `id`, `result` |
| `[:zen_websocket, :request, :timeout]` | `timeout_ms` | `method`, `id` |
| `[:zen_websocket, :subscription, :add]` | `count` | `channel` |
| `[:zen_websocket, :subscription, :remove]` | `count` | `channel` |
| `[:zen_websocket, :heartbeat, :send]` | `timestamp` | `type` |

### Setting Up Telemetry Handlers

**Important:** Call `setup/0` in your application's `start/2` callback to attach handlers before any connections are made:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  MyApp.TelemetryHandler.setup()

  children = [
    # ... your supervision tree
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

```elixir
defmodule MyApp.TelemetryHandler do
  require Logger

  def setup do
    events = [
      [:zen_websocket, :rate_limiter, :pressure],
      [:zen_websocket, :request, :complete],
      [:zen_websocket, :request, :timeout]
    ]

    :telemetry.attach_many(
      "my-app-zen-websocket",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:zen_websocket, :rate_limiter, :pressure], measurements, metadata, _config) do
    Logger.warning("Rate limiter pressure: #{metadata.level}, queue: #{measurements.queue_size}")
  end

  def handle_event([:zen_websocket, :request, :complete], measurements, metadata, _config) do
    if measurements.duration_ms > 1000 do
      Logger.warning("Slow request: #{metadata.method} took #{measurements.duration_ms}ms")
    end
  end

  def handle_event([:zen_websocket, :request, :timeout], measurements, metadata, _config) do
    Logger.error("Request timeout: #{metadata.method} after #{measurements.timeout_ms}ms")
  end
end
```

## Memory Characteristics

### Per-Connection Baseline

| Component | Memory |
|-----------|--------|
| Client GenServer state | ~1-2 KB |
| Gun connection | ~2-3 KB |
| LatencyStats buffer (100 samples) | ~2 KB |
| SubscriptionManager (10 channels) | ~500 bytes |
| RequestCorrelator (empty) | ~200 bytes |
| **Total idle connection** | **~6-8 KB** |

### Variable Memory Components

| Component | Growth Factor |
|-----------|--------------|
| RequestCorrelator | ~200 bytes per pending request |
| RateLimiter queue | ~100 bytes per queued request |
| SubscriptionManager | ~50 bytes per subscription |
| LatencyStats | 8 bytes per sample up to buffer_size |

### Memory Optimization

```elixir
# Memory-constrained configuration
{:ok, client} = Client.connect(url,
  latency_buffer_size: 25,    # Smaller latency buffer
  request_timeout: 10_000     # Shorter timeout = fewer pending requests
)

# Initialize rate limiter with smaller queue
RateLimiter.init(:my_limiter, %{
  tokens: 100,
  refill_rate: 10,
  refill_interval: 1000,
  max_queue_size: 25,  # Smaller queue, fail faster
  request_cost: &RateLimiter.simple_cost/1
})
```

## Common Tuning Scenarios

### High-Frequency Trading

Optimize for lowest latency, fast failure detection:

```elixir
{:ok, client} = Client.connect(url,
  timeout: 2000,
  request_timeout: 3000,
  heartbeat_interval: 5000,
  retry_count: 3,
  retry_delay: 100,
  max_backoff: 1000,
  latency_buffer_size: 500
)
```

### Market Data Collection

Optimize for reliability, handle reconnection gracefully:

```elixir
{:ok, client} = Client.connect(url,
  timeout: 10_000,
  request_timeout: 30_000,
  heartbeat_interval: 30_000,
  retry_count: 20,
  retry_delay: 1000,
  max_backoff: 60_000,
  restore_subscriptions: true
)
```

### Resource-Constrained Environment

Minimize memory and CPU overhead:

```elixir
{:ok, client} = Client.connect(url,
  heartbeat_interval: 60_000,   # Less frequent heartbeats
  latency_buffer_size: 10,      # Minimal latency tracking
  retry_count: 3                # Limited retries
)
```

## Debugging Performance Issues

### Enable Debug Logging

```elixir
{:ok, client} = Client.connect(url, debug: true)
```

This logs detailed connection lifecycle events including Gun operations, WebSocket upgrades, and message timing.

### Check Connection State

```elixir
{:ok, state} = Client.get_state(client)

# Get latency metrics
latency = LatencyStats.summary(state.latency_stats)
# => %{p50: 45, p99: 120, last: 52, count: 100}

# Check active subscriptions
subscriptions = SubscriptionManager.list(state.subscription_manager)
# => ["ticker.BTC", "trades.BTC"]
```

### Monitor Rate Limiter

```elixir
{:ok, status} = RateLimiter.status(:my_limiter)
IO.inspect(status)
# => %{tokens: 85, queue_size: 5, pressure_level: :low, suggested_delay_ms: 1000}
```

## Summary

| Goal | Key Parameters |
|------|----------------|
| Lower latency | Reduce `timeout`, `request_timeout`, `heartbeat_interval` |
| Higher reliability | Increase `retry_count`, `max_backoff` |
| Less memory | Reduce `latency_buffer_size`, `max_queue_size` |
| Better observability | Attach telemetry handlers, enable `debug: true` |
| Prevent rate limits | Configure appropriate `request_cost` function, monitor pressure |

## Related Guides

- [Building Exchange Adapters](building_adapters.md) - Build production adapters with reconnection and state restoration

