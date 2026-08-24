# Gun Integration Guide

This guide covers the integration of the [Gun](https://github.com/ninenines/gun) HTTP/WebSocket client in ZenWebsocket, focusing on connection management, process monitoring, and ownership transfer.

## Table of Contents
- [Overview](#overview)
- [Process Monitoring vs. Linking](#process-monitoring-vs-linking)
- [Waiting for the Gun Connection to Come Up](#waiting-for-the-gun-connection-to-come-up)
- [Ownership Transfer](#ownership-transfer)
- [Best Practices](#best-practices)

## Overview

ZenWebsocket uses Gun as its underlying transport layer for WebSocket connections. Gun provides robust HTTP and WebSocket protocol implementation with features like:
- HTTP/1.1, HTTP/2, and WebSocket support
- Automatic reconnection capabilities
- Comprehensive TLS options
- Message streaming and multiplexing

The `ZenWebsocket.Client` module is a GenServer that owns the Gun connection and manages message routing.

## Process Monitoring vs. Linking

Gun gives developers the choice between using process links and monitors for tracking connection processes:

### Why ZenWebsocket Uses Monitors

ZenWebsocket uses Erlang's process monitoring (`Process.monitor/1`) instead of process linking for tracking Gun connections for several reasons:

1. **Resilience**: If a Gun process crashes, the monitoring process receives a message rather than crashing itself
2. **Control**: More granular control over error handling and recovery
3. **Ownership Transfers**: Easier to manage process relationships during ownership changes

### Current Implementation in Client

```elixir
# In ZenWebsocket.Client.connect/2
{:ok, gun_pid} = :gun.open(host_charlist, port, gun_opts)
monitor_ref = Process.monitor(gun_pid)

%Client{
  gun_pid: gun_pid,
  monitor_ref: monitor_ref,
  state: :connecting,
  # ...
}
```

## Waiting for the Gun Connection to Come Up

ZenWebsocket never calls `:gun.await/2,3,4` or `:gun.await_up/1,2,3` — there are
no call sites anywhere in `lib/`; the name appears only in a comment in
`ZenWebsocket.Reconnection`. Instead,
`Reconnection.establish_connection/1` opens Gun, sets up its own
`Process.monitor/1`, and blocks on a hand-written `receive` that matches every
relevant transport message:

```elixir
# lib/zen_websocket/reconnection.ex
# Waits for Gun to come up, matching connection-level errors that :gun.await_up/2
# does not surface (e.g. :nxdomain delivered as {:gun_error, pid, reason}).
defp await_gun_up(gun_pid, timeout) do
  receive do
    {:gun_up, ^gun_pid, protocol} -> {:ok, protocol}
    {:gun_error, ^gun_pid, reason} -> {:error, reason}
    {:gun_error, ^gun_pid, _stream, reason} -> {:error, reason}
    {:gun_down, ^gun_pid, _proto, reason, _killed} -> {:error, reason}
    {:DOWN, _ref, :process, ^gun_pid, reason} -> {:error, reason}
  after
    timeout -> {:error, :timeout}
  end
end
```

`await_transport/2` calls `Process.monitor(gun_pid)` and then `await_gun_up(gun_pid,
config.timeout)` — the monitor ref is not passed in. It does not need to be: the
monitor is installed by the same process that then blocks in `await_gun_up/2`'s
`receive`, so the `{:DOWN, _ref, :process, ^gun_pid, reason}` clause fires if the
Gun process dies before `:gun_up` arrives. The ref is kept only to hand back on
success and to demonitor on the failure path.

### Why a raw `receive` instead of `:gun.await_up/2`

Per Gun's source (`await_up/1,2,3`, fetched from
[`ninenines/gun/src/gun.erl`](https://github.com/ninenines/gun/blob/master/src/gun.erl)),
`:gun.await_up/3` — the arity `await_up/1` and `await_up/2` both funnel into —
matches only two message shapes: `{gun_up, ServerPid, Protocol}` and the
monitor's own `{'DOWN', MRef, process, ServerPid, Reason}`. It has no clause for
`gun_error` or `gun_down` at all, and it is not scoped to a stream — it never
takes a `StreamRef`. A connection-level failure such as `:nxdomain`, delivered as
a bare `{:gun_error, ServerPid, Reason}`, simply falls through `:gun.await_up`'s
`receive` and is only surfaced once the full `Timeout` elapses. `await_gun_up/2`
matches that shape directly, so DNS/TCP-level failures during the initial
handshake surface as `{:error, reason}` instead of waiting out the full timeout.

Gun's own `await_up/2` and `await_up/3` (called with a `Timeout`, not an explicit
`MonitorRef`) do **not** require a monitor set up beforehand — each one creates
its own and demonitors it (with `[:flush]`) before returning:

```erlang
% src/gun.erl
await_up(ServerPid) ->
	MRef = monitor(process, ServerPid),
	Res = await_up(ServerPid, 5000, MRef),
	demonitor(MRef, [flush]),
	Res.

await_up(ServerPid, MRef) when is_reference(MRef) ->
	await_up(ServerPid, 5000, MRef);
await_up(ServerPid, Timeout) ->
	MRef = monitor(process, ServerPid),
	Res = await_up(ServerPid, Timeout, MRef),
	demonitor(MRef, [flush]),
	Res.

await_up(ServerPid, Timeout, MRef) ->
	receive
		{gun_up, ServerPid, Protocol} ->
			{ok, Protocol};
		{'DOWN', MRef, process, ServerPid, Reason} ->
			{error, {down, Reason}}
	after Timeout ->
		{error, timeout}
	end.
```

ZenWebsocket doesn't call any `:gun.await*` function, so this isn't something it
relies on — but the source confirms `await_up` has no clause matching a bare
`gun_error` or `gun_down` message, which is exactly the gap `await_gun_up/2`
closes. ZenWebsocket's own `monitor_ref` (in the client state) is set up
separately, in `await_transport/2`, and lives for the whole connection rather
than being scoped to a single await call.

## Ownership Transfer

One of Gun's most powerful features is the ability to transfer connection ownership between processes. The Client GenServer owns the connection so Gun messages land in the process that routes heartbeats and user frames.

### When to Transfer Ownership

Ownership transfer is useful when:
- Client GenServer needs to receive Gun messages for integrated heartbeat processing
- Reconnection creates a new Gun process that needs proper ownership
- Moving connections between supervision trees

### Routing Gun Frames Through Callbacks and Frames

`init/1` still opens Gun and monitors it directly on the Client GenServer, so all
Gun messages land on the process that owns the connection. But message routing
itself is no longer inlined in `Client` — `handle_info/2` is a one-line delegate:

```elixir
# lib/zen_websocket/client.ex
def handle_info(msg, state), do: Callbacks.handle_info(msg, state)
```

`Client.Callbacks.handle_info/2` tries transport-message routing first, falling
back to timer/correlation routing:

```elixir
# lib/zen_websocket/client/callbacks.ex
def handle_info(msg, state) do
  case transport_info(msg, state) do
    :unhandled -> timer_info(msg, state)
    result -> result
  end
end

defp transport_info(
       {:gun_ws, gun_pid, stream_ref, frame},
       %{gun_pid: gun_pid, stream_ref: stream_ref} = state
     ) do
  Frames.handle_ws(state, gun_pid, stream_ref, frame)
end
```

`Client.Frames.handle_ws/4` does the actual decode-and-dispatch work: heartbeat
tracking, control-frame classification via
`MessageHandler.decode_and_handle_control/1`, then routing data frames to the
user handler, JSON-RPC correlation, or the subscription/heartbeat managers:

```elixir
# lib/zen_websocket/client/frames.ex
def handle_ws(state, gun_pid, stream_ref, frame) do
  # ...debug logging omitted...
  heartbeat_state = track_heartbeat_frame(frame, state)

  case MessageHandler.decode_and_handle_control({:gun_ws, gun_pid, stream_ref, frame}) do
    {:ok, {:data, decoded_frame}} ->
      new_state = route_data_frame(decoded_frame, heartbeat_state)
      {:noreply, new_state}

    {:ok, :control_frame_handled} ->
      {:noreply, heartbeat_state}

    {:error, {:protocol_error, _} = error} ->
      handle_frame_error(heartbeat_state, error)
  end
end
```

### Reconnection Flow with Ownership

The monitored `:DOWN` message is handled by `Client.Callbacks.transport_info/2`,
which delegates to `Client.TransportErrors.handle_process_down/4` — not by a
function on `Client` itself:

```elixir
# lib/zen_websocket/client/callbacks.ex
defp transport_info(
       {:DOWN, ref, :process, gun_pid, reason},
       %{gun_pid: gun_pid, monitor_ref: ref} = state
     ) do
  TransportErrors.handle_process_down(state, gun_pid, ref, reason)
end
```

```elixir
# lib/zen_websocket/client/transport_errors.ex
def handle_process_down(state, gun_pid, ref, reason) do
  # ...debug logging omitted...
  Retry.handle_connection_error(state, {:connection_down, reason})
end
```

There is no bare `handle_connection_error/2` anywhere in the tree — the retry
decision lives in `ZenWebsocket.Client.Retry.handle_connection_error/2`, reached
only through `TransportErrors`.

`Reconnection.establish_connection/1` runs inside the Client GenServer so the new
Gun process sends messages to this process. `Client.Connection` (a private
helper module, not `Client` directly) wraps it for both the initial connect and
reconnect paths:

```elixir
# lib/zen_websocket/client/connection.ex
defp start_gun_attempt(state) do
  state = %{state | connect_start_time: System.monotonic_time(:millisecond)}

  case Reconnection.establish_connection(state.config) do
    {:ok, gun_pid, stream_ref, monitor_ref} ->
      Debug.log(state.config, "   ✅ Gun connection established")
      {:noreply, begin_attempt(state, gun_pid, stream_ref, monitor_ref)}

    {:error, reason} ->
      Debug.log(state.config, "   ❌ Gun connection failed: #{inspect(reason)}")
      {:noreply, %{state | state: :disconnected}, {:continue, {:connection_failed, reason}}}
  end
end
```

## Best Practices

### 1. Always Use Monitors

```elixir
# Good - ZenWebsocket.Client pattern
{:ok, gun_pid} = :gun.open(host, port, opts)
monitor_ref = Process.monitor(gun_pid)

# Bad - no visibility into connection failures
{:ok, gun_pid} = :gun.open(host, port, opts)
```

### 2. Handle Monitor Messages

See ["Reconnection Flow with Ownership"](#reconnection-flow-with-ownership) above
for the real `:DOWN` handling chain: `Client.Callbacks.transport_info/2` →
`Client.TransportErrors.handle_process_down/4` → `Client.Retry.handle_connection_error/2`.

### 3. Client GenServer Owns Gun Connection

The Client GenServer must own the Gun connection to receive messages — see
["Routing Gun Frames Through Callbacks and Frames"](#routing-gun-frames-through-callbacks-and-frames)
above for the real `:gun_ws` delegation chain (`Client` → `Callbacks` → `Frames`).

### 4. Clean Reconnection

```elixir
defp start_gun_attempt(state) do
  case Reconnection.establish_connection(state.config) do
    {:ok, gun_pid, stream_ref, monitor_ref} ->
      {:noreply, begin_attempt(state, gun_pid, stream_ref, monitor_ref)}

    {:error, reason} ->
      {:noreply, %{state | state: :disconnected}, {:continue, {:connection_failed, reason}}}
  end
end
```

### 5. Test Connection Failures

Always test how your application handles:
- Gun process crashes during active trading
- Network disconnections during heartbeat sequences
- Reconnection with subscription restoration
- Message routing after reconnection

## Summary

Gun's process monitoring and ownership features are critical for ZenWebsocket's architecture. By having the Client GenServer own the Gun connection, we enable:
- Integrated heartbeat processing and user message handling
- Seamless reconnection with state preservation
- Reliable heartbeat handling for financial trading
- Clean separation of concerns between modules

The key insight is that Gun sends messages to the process that owns the connection, which is why the Client GenServer must open (or re-open) Gun itself.
