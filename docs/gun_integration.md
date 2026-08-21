# Gun Integration Guide

This guide covers the integration of the [Gun](https://github.com/ninenines/gun) HTTP/WebSocket client in ZenWebsocket, focusing on connection management, process monitoring, and ownership transfer.

## Table of Contents
- [Overview](#overview)
- [Process Monitoring vs. Linking](#process-monitoring-vs-linking)
- [Using Gun's Await Functions](#using-guns-await-functions)
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

## Using Gun's Await Functions

Gun provides await functions for synchronous operations, but they require careful handling of the monitor reference.

### The Monitor Reference Requirement

Gun's await functions check that the calling process has a monitor on the Gun connection:

```elixir
# Client does not :gun.await the WebSocket upgrade. Reconnection opens Gun,
# then Client completes the upgrade asynchronously:
def handle_info(
      {:gun_upgrade, gun_pid, stream_ref, ["websocket"], _headers},
      %{gun_pid: gun_pid, stream_ref: stream_ref} = state
    ) do
  new_state =
    state
    |> Map.merge(%{state: :connected, retry_count: 0})
    |> HeartbeatManager.start_timer()

  {:noreply, new_state}
end
```

### Common Pitfalls

1. **Missing Monitor Reference**: Calling await without the monitor reference will fail
2. **Wrong Monitor Reference**: Using a monitor reference from a different connection
3. **Monitor After Connect**: The monitor must be established before calling await functions

## Ownership Transfer

One of Gun's most powerful features is the ability to transfer connection ownership between processes. The Client GenServer owns the connection so Gun messages land in the process that routes heartbeats and user frames.

### When to Transfer Ownership

Ownership transfer is useful when:
- Client GenServer needs to receive Gun messages for integrated heartbeat processing
- Reconnection creates a new Gun process that needs proper ownership
- Moving connections between supervision trees

### Implementation for Integrated Heartbeat

```elixir
defmodule ZenWebsocket.Client do
  use GenServer
  
  # Client GenServer owns the Gun connection
  def init(config) do
    {:ok, gun_pid} = :gun.open(host, port, opts)
    monitor_ref = Process.monitor(gun_pid)
    
    # Client GenServer (self()) owns the connection
    # All Gun messages come to this process
    
    state = %{
      gun_pid: gun_pid,
      monitor_ref: monitor_ref,
      heartbeat_manager: nil,
      # ...
    }
    
    {:ok, state}
  end
  
  # Route Gun messages through MessageHandler, then Client's data-frame router
  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    case MessageHandler.decode_and_handle_control({:gun_ws, gun_pid, stream_ref, frame}) do
      {:ok, {:data, decoded_frame}} ->
        {:noreply, route_data_frame(decoded_frame, state)}

      {:ok, :control_frame_handled} ->
        {:noreply, state}

      {:error, {:protocol_error, _} = error} ->
        handle_frame_error(state, error)
    end
  end
end
```

### Reconnection Flow with Ownership

```elixir
def handle_info({:DOWN, ref, :process, pid, reason}, %{gun_pid: pid, monitor_ref: ref} = state) do
  # Connection lost — Client classifies the error and may retry
  handle_connection_error(state, {:connection_down, reason})
end

# Reconnection.establish_connection/1 runs inside the Client GenServer
# so the new Gun process sends messages to this process.
defp start_gun_attempt(state) do
  case Reconnection.establish_connection(state.config) do
    {:ok, gun_pid, stream_ref, monitor_ref} ->
      {:noreply, begin_attempt(state, gun_pid, stream_ref, monitor_ref)}

    {:error, reason} ->
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

```elixir
# In Client GenServer
def handle_info({:DOWN, ref, :process, pid, reason}, %{gun_pid: pid, monitor_ref: ref} = state) do
  handle_connection_error(state, {:connection_down, reason})
end
```

### 3. Client GenServer Owns Gun Connection

The Client GenServer must own the Gun connection to receive messages:

```elixir
defmodule ZenWebsocket.Client do
  use GenServer

  # Gun messages come to the GenServer process
  def handle_info({:gun_ws, gun_pid, stream_ref, frame} = msg, state) do
    case MessageHandler.decode_and_handle_control(msg) do
      {:ok, {:data, decoded_frame}} ->
        {:noreply, route_data_frame(decoded_frame, state)}

      {:ok, :control_frame_handled} ->
        {:noreply, state}

      {:error, {:protocol_error, _} = error} ->
        handle_frame_error(state, error)
    end
  end
end
```

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