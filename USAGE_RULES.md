# ZenWebsocket Usage Rules

<!-- This file follows the usage_rules convention for AI agents and developers -->

## Core Principles

1. **Start Simple**: Use direct connection for development, add supervision for production
2. **Public Client API**: connection lifecycle (`connect`, `send_message`, `subscribe`, `get_state`, `close`, `reconnect`) plus monitoring (`get_latency_stats`, `get_heartbeat_health`, `get_state_metrics`). `build_client_struct/2` is public but `@doc false` (ClientSupervisor).
3. **Real API Testing**: Always test against real endpoints, never mock WebSocket behavior

## Quick Start Pattern

```elixir
# Simplest possible usage - connect and send
{:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")
ZenWebsocket.Client.send_message(client, Jason.encode!(%{method: "public/test"}))
```

## Essential Functions

```elixir
# 1. Connect to WebSocket
{:ok, client} = ZenWebsocket.Client.connect(url, opts)

# 2. Send messages (must be binary — use Jason.encode!/1 for maps)
:ok = ZenWebsocket.Client.send_message(client, Jason.encode!(%{method: "public/test"}))

# 3. Subscribe to channels (Deribit public/subscribe; tracked at send time)
:ok = ZenWebsocket.Client.subscribe(client, channels)

# 4. Check connection state
state = ZenWebsocket.Client.get_state(client)  # :connected, :connecting, :disconnected

# 5. Close connection
:ok = ZenWebsocket.Client.close(client)

# 6. Reconnect using the stored connection contract
{:ok, new_client} = ZenWebsocket.Client.reconnect(client)
```

### Monitoring Functions

```elixir
# Latency percentiles (p50/p99/last/count — all integers in ms)
stats = ZenWebsocket.Client.get_latency_stats(client)

# Heartbeat health (active_heartbeats, last_heartbeat_at, failure_count, config, timer_active)
health = ZenWebsocket.Client.get_heartbeat_health(client)

# Connection metrics (subscriptions_size, pending_requests_size, state_memory, ...)
metrics = ZenWebsocket.Client.get_state_metrics(client)
```

## Common Patterns

### Pattern 1: Development/Testing (No Supervision)
```elixir
# Direct connection - crashes won't restart
{:ok, client} = ZenWebsocket.Client.connect(url)
# Use the client...
ZenWebsocket.Client.close(client)
```

### Pattern 2: Production with Dynamic Connections
```elixir
# Add to your supervision tree
children = [
  ZenWebsocket.ClientSupervisor,
  # ... other children
]

# Start connections dynamically. Supervised clients MUST pass `:handler`.
{:ok, client} =
  ZenWebsocket.ClientSupervisor.start_client(url,
    handler: fn msg -> send(MyApp.Consumer, {:ws, msg}) end
  )
```

### Pattern 3: Production with Fixed Connections
```elixir
# Add specific clients to supervision tree
children = [
  {ZenWebsocket.Client, [
    url: "wss://api.example.com/ws",
    id: :main_websocket,
    handler: &MyApp.Consumer.handle_ws/1,
    heartbeat_config: %{type: :ping_pong, interval: 30_000}
  ]}
]
```

**Handler rule (Patterns 2 and 3):** always pass `:handler`. The
parent-forwarding default that emits `{:websocket_message, _}` is installed
**only** by `ZenWebsocket.Client.connect/2`. Every other start path
(`ClientSupervisor.start_client/2`, a `child_spec` entry, `Client.start_link/2`)
defaults to `ZenWebsocket.MessageHandler.default_handler/1`, which returns `:ok`
and discards the frame — a supervised client without `:handler` silently drops
every inbound message.

## Configuration Options

```elixir
opts = [
  # Connection
  timeout: 5000,              # Connection timeout in ms
  headers: [],                # Additional headers
  debug: false,               # Enable verbose debug logging

  # Reconnection
  retry_count: 3,             # Max reconnection attempts
  retry_delay: 1000,          # Initial retry delay (exponential backoff)
  reconnect_on_error: true,   # Auto-reconnect on errors
  restore_subscriptions: true, # Restore tracked Deribit subscriptions after reconnect

  # Heartbeat. Omit the key entirely for `:disabled` (the default — nothing is sent).
  heartbeat_config: %{
    type: :ping_pong,         # :ping_pong and :deribit send outbound heartbeats.
                              # :binance is inbound-only — it consumes heartbeat
                              # messages and has no outbound send clause.
    interval: 30_000          # Falls back to `heartbeat_interval` when omitted
  },

  # Session Recording
  record_to: "/tmp/session.jsonl",  # Enable message recording (nil to disable)

  # Latency Monitoring
  latency_buffer_size: 100    # Samples for p50/p99 calculations
]
```

## Custom Client Discovery (Distributed Applications)

For distributed applications using `:pg`, `Horde`, or other registries, ZenWebsocket provides hooks to integrate with your registry of choice.

### Lifecycle Callbacks

Register clients with your registry using `on_connect`/`on_disconnect`:

```elixir
{:ok, client} = ZenWebsocket.ClientSupervisor.start_client(
  "wss://api.example.com/ws",
  handler: fn msg -> send(MyApp.Consumer, {:ws, msg}) end,
  on_connect: fn pid -> :pg.join(:ws_pool, pid) end,
  on_disconnect: fn pid -> :pg.leave(:ws_pool, pid) end
)
```

**Important:** `on_disconnect` is called during `terminate/2`, which requires a graceful shutdown. It will NOT be called if the process is killed with `:kill` signal.

### Custom Discovery for Load Balancing

Use `client_discovery` to route messages across nodes:

```elixir
ZenWebsocket.ClientSupervisor.send_balanced(
  message,
  client_discovery: fn -> :pg.get_members(:ws_pool) end
)
```

Without `client_discovery`, `send_balanced/2` defaults to `list_clients/0` (local connections only).

### Example: Multi-Node Setup with pg

```elixir
# Node A and Node B both run:
:pg.start_link()

# Define callbacks once
defmodule MyApp.WSCallbacks do
  def on_connect(pid), do: :pg.join(:ws_pool, pid)
  def on_disconnect(pid), do: :pg.leave(:ws_pool, pid)
end

# Start clients with pg callbacks
{:ok, _} = ZenWebsocket.ClientSupervisor.start_client(url,
  on_connect: &MyApp.WSCallbacks.on_connect/1,
  on_disconnect: &MyApp.WSCallbacks.on_disconnect/1
)

# Route to any healthy client across all nodes
ZenWebsocket.ClientSupervisor.send_balanced(msg,
  client_discovery: fn -> :pg.get_members(:ws_pool) end
)
```

### Example: Horde Registry

```elixir
# With Horde for distributed process registry
{:ok, _} = ZenWebsocket.ClientSupervisor.start_client(url,
  on_connect: fn pid ->
    Horde.Registry.register(MyApp.WSRegistry, {:ws_client, pid}, pid)
  end,
  on_disconnect: fn pid ->
    Horde.Registry.unregister(MyApp.WSRegistry, {:ws_client, pid})
  end
)

# Custom discovery using Horde
ZenWebsocket.ClientSupervisor.send_balanced(msg,
  client_discovery: fn ->
    Horde.Registry.select(MyApp.WSRegistry, [{{{:ws_client, :_}, :_, :"$1"}, [], [:"$1"]}])
  end
)
```

### Callback Error Handling

Callback errors are caught and logged - they won't crash the client or prevent connection/termination:

```elixir
# This won't crash the client
opts = [on_connect: fn _pid -> raise "intentional error" end]
# Warning logged: "Lifecycle callback error: %RuntimeError{message: \"intentional error\"}"
```

## Session Recording

Pass `record_to: "/tmp/debug.jsonl"` to `connect/2` to record every frame.

- Always `Client.close/1` — the remaining buffer is flushed on close.
- Read back with `ZenWebsocket.Recorder.metadata/1` (`{:ok, map}`) and
  `ZenWebsocket.Recorder.replay/2`.
- Format is JSONL, one JSON object per line. Binary frames are base64-encoded.

See the README's Session Recording section for the runnable example.

## Platform-Specific Rules

### Deribit Integration
Use `DeribitGenServerAdapter` — it is the recommended supervised entry point.

```elixir
alias ZenWebsocket.Examples.DeribitGenServerAdapter

{:ok, adapter} =
  DeribitGenServerAdapter.start_link(
    name: MyApp.Deribit,
    url: "wss://test.deribit.com/ws/api/v2",
    client_id: System.get_env("DERIBIT_CLIENT_ID"),
    client_secret: System.get_env("DERIBIT_CLIENT_SECRET")
  )

:ok = DeribitGenServerAdapter.authenticate(adapter)
:ok = DeribitGenServerAdapter.subscribe(adapter, ["trades.BTC-PERPETUAL.raw"])
{:ok, response} = DeribitGenServerAdapter.send_request(adapter, "public/test", %{})
{:ok, state} = DeribitGenServerAdapter.get_state(adapter)
```

`authenticate/1` and `subscribe/2` return bare `:ok`, not `{:ok, _}`. The adapter
handles the authentication flow, heartbeat/`test_request`, subscription tracking,
and re-authentication after reconnect.

`ZenWebsocket.Examples.DeribitAdapter` is the functional/struct-based variant —
it has no `start_link/1`. `connect/0,1` returns `{:ok, %DeribitAdapter{}}` that
you thread through `authenticate/1`, `subscribe/2`, `unsubscribe/2`, and
`send_request/2,3`. Its `:heartbeat_interval` option is in **seconds** (default
`30`), unlike every millisecond-valued option elsewhere in this library.

```elixir
{:ok, adapter} =
  ZenWebsocket.Examples.DeribitAdapter.connect(
    url: "wss://test.deribit.com/ws/api/v2",
    client_id: System.get_env("DERIBIT_CLIENT_ID"),
    client_secret: System.get_env("DERIBIT_CLIENT_SECRET"),
    heartbeat_interval: 30
  )

{:ok, adapter} = ZenWebsocket.Examples.DeribitAdapter.authenticate(adapter)
```

## Reconnection Behavior

ZenWebsocket supports two reconnect paths with different preservation semantics.

### Automatic Reconnect (`reconnect_on_error: true`)

When a connection drops and `reconnect_on_error: true` (the default), the same
Client GenServer reconnects with exponential backoff.

#### Preserved Across Automatic Reconnect

| State | Details |
|-------|---------|
| **Config struct** | Full validated `ZenWebsocket.Config` struct |
| **Handler callback** | Same function reference — no need to re-register |
| **Heartbeat config** | Timer restarted with original interval after reconnect |
| **Subscriptions** | Deribit-dialect channels restored if `restore_subscriptions: true` (default). See "Subscription tracking" below. |
| **Latency stats** | Historical measurements accumulate across reconnects |
| **Session recorder** | Continues recording to the same file |
| **on_disconnect callback** | Same function reference |

#### Reset on Automatic Reconnect

| State | Details |
|-------|---------|
| **Runtime retry counter** | `state.retry_count` resets to 0 after successful reconnect; config `retry_count` stays unchanged |
| **Heartbeat failures** | Counter reset to 0 |
| **Heartbeat timer** | Cancelled on disconnect, restarted on reconnect |
| **Gun PID / stream ref** | New connection process and stream |
| **Pending requests** | Failed with `{:error, :disconnected}` and cleared; not replayed |

#### Pending Requests on Automatic Reconnect

Pending RPC requests are **failed immediately on disconnect**, not carried
across the reconnect. `RequestCorrelator.fail_all/2` replies `{:error,
:disconnected}` to every caller blocked in `GenServer.call`, cancels their
timeout timers, and clears `pending_requests` to `%{}` — so a caller gets a
prompt error rather than a timeout, and no response on the new connection can
be mismatched against a stale request id. Each failed request emits
`[:zen_websocket, :request_correlator, :fail_all]`.

Callers must therefore handle `{:error, :disconnected}` from any in-flight
request when the connection drops, and re-issue it themselves if they want it
retried — the library does not replay it.

### Subscription tracking

`SubscriptionManager` auto-tracks Deribit-dialect JSON-RPC only:
`public/subscribe` and `public/unsubscribe` with `params.channels`, plus
id-keyed confirmations and rejections. Other venues' subscribe shapes are
not inferred or automatically restored; adapters for those venues must manage
their own subscription state and reconnect replay. Restore payloads from
`SubscriptionManager` are always Deribit `public/subscribe`.

`Client.subscribe/2` sends no JSON-RPC `id`, so channels are recorded at
send time. A server-side rejection is not observed and those channels stay
in the reconnect restore set. Send an id-carrying `public/subscribe` via
`send_message/2` to wait for confirmation.

### Explicit Reconnect (`Client.reconnect/1`)

`Client.reconnect/1` starts a fresh Client process using the stored connection
contract from the original client struct returned by `connect/2` or
`ClientSupervisor.start_client/2`.

If the original client was started under `ClientSupervisor.start_client/2`,
explicit reconnect goes back through `ClientSupervisor.start_client/2` so the
replacement client stays supervised and reruns `:on_connect`.

#### Preserved Across Explicit Reconnect

| State | Details |
|-------|---------|
| **Config struct** | Full validated `ZenWebsocket.Config` struct, including headers/timeouts/retry settings |
| **Handler callback** | Same function reference |
| **Heartbeat config** | Same heartbeat configuration for the new client |
| **Supervision mode** | Supervised clients reconnect as supervised clients; direct clients reconnect directly |
| **on_connect callback** | Rerun for supervised reconnect so registries can re-register the new PID |
| **on_disconnect callback** | Same function reference |

#### Reset on Explicit Reconnect

| State | Details |
|-------|---------|
| **Subscriptions** | Fresh client state — resubscribe after reconnect if needed |
| **Pending requests** | Fresh client state — in-flight requests from the old client do not carry over |
| **Latency stats / heartbeat state** | Fresh client state with new counters and timers |
| **Server / Gun PIDs** | New Client GenServer, Gun process, and stream ref |

## Error Handling

```elixir
# All functions return tagged tuples
case ZenWebsocket.Client.connect(url) do
  {:ok, client} ->
    # Success path
    client

  {:error, reason} ->
    # Get human-readable explanation with fix suggestion
    explanation = ZenWebsocket.ErrorHandler.explain(reason)
    Logger.error("#{explanation.message}. #{explanation.suggestion}")
    # Errors are passed raw from Gun/WebSocket
    # Common errors: :timeout, :connection_refused, :protocol_error
end
```

## Handler Message Reference

Your `handler` function (passed via `connect/2` as `:handler`) receives one of the tuple shapes below. This section is the complete contract — matched against `t:ZenWebsocket.Client.handler_message/0`.

### Input Shapes

The tuples delivered to your handler:

| Shape | When emitted | Payload |
|-------|--------------|---------|
| `{:message, map}` | Decoded JSON frame (including subscription updates) | Decoded map |
| `{:message, binary}` | Text frame that did not decode as JSON | Raw text binary |
| `{:binary, binary}` | WebSocket binary frame | Raw bytes |
| `{:unmatched_response, map}` | JSON-RPC response whose `"id"` did not match any pending request | Decoded response map |
| `{:protocol_error, reason}` | Fatal, unrecoverable frame error (client will stop) | Unwrapped reason |

Ping/pong/close control frames are handled transparently by the client and never reach your handler. Any frame decode error is fatal — `{:protocol_error, _}` is the only error shape you receive.

### Custom Handler Example

A pattern-matching handler that distinguishes every shape:

```elixir
handler = fn
  {:message, %{} = json} ->
    # Decoded JSON frame (subscription update or general message)
    MyApp.Router.route(json)

  {:message, text} when is_binary(text) ->
    # Text frame that was not valid JSON
    MyApp.TextStream.receive(text)

  {:binary, bin} ->
    MyApp.BinaryStream.receive(bin)

  {:unmatched_response, response} ->
    # Late reply after RequestCorrelator already timed it out, or an ID collision
    Logger.warning("unmatched response: #{inspect(response)}")

  {:protocol_error, reason} ->
    Logger.error("fatal protocol error: #{inspect(reason)}")
end

{:ok, client} = ZenWebsocket.Client.connect(url, handler: handler)
```

Handler return values are ignored.

### Default Handler Translation

If you do not pass `:handler` **to `ZenWebsocket.Client.connect/2`**, a default handler forwards messages to the calling process as `{:websocket_*, _}` tuples. This applies to `connect/2` only — `ClientSupervisor.start_client/2`, a `child_spec` entry, and `Client.start_link/2` all default to `ZenWebsocket.MessageHandler.default_handler/1`, which discards the frame. The translation:

| Input shape | Message sent to parent |
|-------------|------------------------|
| `{:message, data}` | `{:websocket_message, data}` |
| `{:binary, data}` | `{:websocket_message, data}` *(same tag)* |
| `{:unmatched_response, response}` | `{:websocket_unmatched_response, response}` |
| `{:protocol_error, reason}` | `{:websocket_protocol_error, reason}` |

Note that `{:message, _}` and `{:binary, _}` both collapse to `:websocket_message`, so the default handler cannot distinguish text from binary frames. If you need to tell them apart, supply a custom handler.

## Testing Rules

```elixir
# Use the Testing module for controlled tests
alias ZenWebsocket.Testing

# Start a mock server
{:ok, server} = Testing.start_mock_server()
{:ok, client} = ZenWebsocket.Client.connect(server.url)

# Inject messages from server to client
Testing.inject_message(server, ~s({"type": "hello"}))

# Assert client sent expected message (supports string, regex, map, or function matchers)
assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

# Simulate disconnects for error handling tests
Testing.simulate_disconnect(server, :going_away)

# Cleanup
Testing.stop_server(server)
```

### ExUnit Integration Pattern
```elixir
defmodule MyTest do
  use ExUnit.Case
  alias ZenWebsocket.Testing

  setup do
    {:ok, server} = Testing.start_mock_server()
    on_exit(fn -> Testing.stop_server(server) end)
    {:ok, server: server}
  end

  test "client handles server message", %{server: server} do
    {:ok, client} = ZenWebsocket.Client.connect(server.url)
    Testing.inject_message(server, ~s({"type": "pong"}))
    assert_receive {:websocket_message, _}, 1000
    ZenWebsocket.Client.close(client)
  end
end
```

### Real API Testing
```elixir
# For integration tests against real endpoints
@tag :integration
test "real WebSocket behavior" do
  {:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")
  # Test against real API...
end
```

## DO NOT

1. **Don't create wrapper modules** - Use the Client functions directly
2. **Don't mock WebSocket behavior** - Test against real endpoints or use Testing module
3. **Don't add custom reconnection** - Use built-in retry options
4. **Don't transform errors** - Handle raw Gun/WebSocket errors
5. **Don't avoid GenServers** - Client uses GenServer appropriately for state

## Architecture Notes

- **Gun Transport**: Built on Gun for HTTP/2 and WebSocket
- **GenServer State**: Client maintains connection state in GenServer
- **ETS Registry**: Fast connection lookups via ETS
- **Exponential Backoff**: Smart reconnection with backoff
- **Real API Testing**: All tests use real APIs or Testing module (no mocks)

## Monitoring and Observability

### Latency Statistics
```elixir
# Get latency metrics (p50/p99/last/count — all integers in ms)
stats = ZenWebsocket.Client.get_latency_stats(client)
# => %{p50: 12, p99: 45, last: 10, count: 100}
```

### Heartbeat Health
```elixir
# Check heartbeat status
health = ZenWebsocket.Client.get_heartbeat_health(client)
# => %{active_heartbeats: [], last_heartbeat_at: nil, failure_count: 0, config: :disabled, timer_active: false}
# `last_heartbeat_at` stays nil until the first pong is acknowledged; after that it
# is a monotonic timestamp (System.monotonic_time(:millisecond)), not a wall clock.
```

### State Metrics
```elixir
# Get connection state metrics
metrics = ZenWebsocket.Client.get_state_metrics(client)
# => %{subscriptions_size: 12, pending_requests_size: 5, state_memory: 1024, ...}
```

### Rate Limiter

`RateLimiter` is a standalone token bucket over a named ETS table. `Client` never
consults it — call `consume/2` yourself before sending. `status/1`, `consume/2`,
`refill/1`, and `shutdown/1` all take the limiter **name atom**, read ETS
directly, and raise if `init/2` was never called for that name.

```elixir
alias ZenWebsocket.RateLimiter

# All four config keys are required. A missing `:tokens` raises KeyError.
{:ok, :deribit_limiter} =
  RateLimiter.init(:deribit_limiter, %{
    tokens: 100,
    refill_rate: 10,
    refill_interval: 1_000,
    request_cost: &RateLimiter.deribit_cost/1
  })

:ok = RateLimiter.consume(:deribit_limiter, %{"method" => "public/test"})
# {:error, :rate_limited} when the bucket is empty

# Queue/pressure keys stay at compatibility defaults — this limiter never retains requests.
{:ok, status} = RateLimiter.status(:deribit_limiter)
# => %{tokens: 99, queue_size: 0, pressure_level: :none, suggested_delay_ms: 0}

# ETS tables are not reclaimed on process exit
:ok = RateLimiter.shutdown(:deribit_limiter)
```

`init/2` schedules refills with `Process.send_after/3` against the **calling**
process. That process MUST handle `{:refill, name}`, or refills stop permanently:

```elixir
def handle_info({:refill, name}, state) do
  ZenWebsocket.RateLimiter.refill(name)
  {:noreply, state}
end
```

Cost functions shipped: `simple_cost/1` (always 1), `deribit_cost/1`
(credit-based), `binance_cost/1` (weight-based).

### Key Telemetry Events

| Event | Measurements | When |
|-------|--------------|------|
| `[:zen_websocket, :connection, :upgrade]` | `connect_time_ms` | WebSocket upgrade complete |
| `[:zen_websocket, :heartbeat, :pong]` | `rtt_ms` | Heartbeat response received |
| `[:zen_websocket, :rate_limiter, :consume]` | `tokens_remaining`, `cost` | Token consumed |
| `[:zen_websocket, :rate_limiter, :refill]` | `tokens_before`, `tokens_after`, `refill_rate` | Bucket refilled |
| `[:zen_websocket, :request_correlator, :track]` | `count` | Request tracked |
| `[:zen_websocket, :request_correlator, :resolve]` | `count`, `round_trip_ms` | Response correlated |
| `[:zen_websocket, :request_correlator, :timeout]` | `count` | Request timed out |
| `[:zen_websocket, :request_correlator, :fail_all]` | `count` | Pending request failed on disconnect (metadata: `id`, `reason`) |
| `[:zen_websocket, :subscription_manager, :add]` | `count` | Subscription added |
| `[:zen_websocket, :subscription_manager, :remove]` | `count` | Subscription removed |
| `[:zen_websocket, :subscription_manager, :restore]` | `channel_count` | Subscriptions restored |
| `[:zen_websocket, :pool, :route]` | `health`, `pool_size` | Connection selected |
| `[:zen_websocket, :pool, :health]` | `pool_size`, `avg_health` | Pool health snapshot |
| `[:zen_websocket, :pool, :failover]` | `attempt` | Failover triggered |

See [Performance Tuning Guide](docs/guides/performance_tuning.md) for complete telemetry reference.

```elixir
# Attach to telemetry events
:telemetry.attach(
  "websocket-logger",
  [:zen_websocket, :connection, :upgrade],
  fn _event, measurements, _metadata, _config ->
    Logger.info("WebSocket connected in #{measurements.connect_time_ms}ms")
  end,
  nil
)
```

## Module Limits

Each module follows strict simplicity rules:
- Maximum 5 public functions per new module (existing core modules may exceed this)
- Maximum 15 lines per function
- Real API testing only (no mocks)

## Getting Help

- **Examples**: See `lib/zen_websocket/examples/` directory
- **Tests**: Review `test/` for usage patterns
- **Deribit**: See `DeribitGenServerAdapter` (recommended, supervised) or `DeribitAdapter` (functional/struct-based)
- **Guides**: See `docs/guides/` for performance tuning and adapter building
- **Verification workflow**:

```bash
mix test.json --quiet --summary-only        # test health
mix test.json --quiet --failed --first-failure
mix dialyzer.json --quiet                   # type checking
mix credo --strict --format json            # static analysis
mix security                                # Sobelow scan
mix docs                                    # generate docs
```

## Self-Describing API (`ZenWebsocket.describe/0,1,2`)

Progressive discovery for agents and MCP tools. Three arities only — there is no
`describe/3`. Short names are accepted as either **strings or atoms**:
`describe(:client)` and `describe("client")` both work. Raises `ArgumentError` for
an unknown short name like `:internal` (not because it is an atom, but because the
name does not exist).

```elixir
# 0. Every annotated module: %{module, short_name, namespace, description,
#    function_count, annotated?}
ZenWebsocket.describe()

# 1. Functions in one module (short name string): %{name, arity, description,
#    spec, defaults}
ZenWebsocket.describe("rate_limiter")

# 2. One function in full: adds %{params, returns, errors, opts, defaults,
#    returns_example, composes_with}
ZenWebsocket.describe("rate_limiter", :consume)
```

Available short names: `client`, `config`, `client_supervisor`, `reconnection`,
`heartbeat_manager`, `subscription_manager`, `request_correlator`,
`rate_limiter`, `pool_router`, `connection_registry`, `error_handler`,
`latency_stats`, `recorder`, `recorder_server`, `testing`, `frame`, `json_rpc`,
`message_handler`.

## Common Mistakes to Avoid

1. **Creating abstractions too early** - Start with direct usage
2. **Mocking in tests** - Always use real WebSocket endpoints or Testing module
3. **Custom error types** - Handle raw Gun/WebSocket errors
4. **Complex supervision** - Use provided patterns (1, 2, or 3)
5. **Ignoring heartbeats** - `heartbeat_config` defaults to `:disabled`; set it explicitly for long-lived connections (`heartbeat_interval` alone does nothing)

## Migration from Other Libraries

### From Websockex
```elixir
# Old (Websockex with callbacks)
defmodule MyClient do
  use WebSockex
  def handle_frame({:text, msg}, state), do: {:ok, state}
end

# New (ZenWebsocket - simpler)
{:ok, client} = ZenWebsocket.Client.connect(url, handler: fn msg -> handle(msg) end)
# Messages are delivered to the `:handler` function
```

### From Gun directly
```elixir
# You're already using the right approach!
# ZenWebsocket is a thin, focused layer over Gun
```

## Reconnection Backoff

`Reconnection.calculate_backoff/3` is `retry_delay * 2^attempt`, capped at
`max_backoff` (default 30_000 ms). With the defaults (`retry_delay: 1000`):
1s, 2s, 4s, 8s, 16s, 30s, 30s...

For timeout, buffer, and pool sizing guidance see
[Performance Tuning](docs/guides/performance_tuning.md). This repo ships no
benchmark suite — measure your own workload rather than assuming figures.

## Required Environment Variables

For platform integrations:
```bash
# Deribit
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

## Best Practices Summary

1. Start with Pattern 1 (direct) for development
2. Move to Pattern 2 or 3 for production
3. Configure heartbeats for long-lived connections
4. Test against real endpoints or use Testing module
5. Handle raw errors with pattern matching
6. Use telemetry for monitoring
7. Enable `record_to` for debugging production issues
8. Keep it simple - use Client directly (connect, send, subscribe, monitor, reconnect)
