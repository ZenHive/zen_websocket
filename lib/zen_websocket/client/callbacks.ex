defmodule ZenWebsocket.Client.Callbacks do
  @moduledoc """
  `handle_call/3` and `handle_info/2` clause bodies for `ZenWebsocket.Client`.

  The GenServer callbacks stay on Client so supervision and message ownership
  do not change; this module holds the pattern-matched routing those callbacks
  previously inlined.
  """

  alias ZenWebsocket.Client.Connection
  alias ZenWebsocket.Client.Frames
  alias ZenWebsocket.Client.Retry
  alias ZenWebsocket.HeartbeatManager

  @doc """
  Routes Client `handle_call/3` requests. Clause order matches the original Client.
  """
  @spec handle_call(term(), GenServer.from(), map()) ::
          {:reply, term(), map()} | {:noreply, map()}
  def handle_call(:await_connection, _from, %{state: :connected} = state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:await_connection, from, state) do
    {:noreply, Map.put(state, :awaiting_connection, from)}
  end

  def handle_call({:send_message, message}, from, %{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected} = state) do
    Frames.send_text(state, gun_pid, stream_ref, message, from)
  end

  def handle_call({:send_message, _message}, _from, %{state: conn_state} = state) do
    {:reply, {:error, {:not_connected, conn_state}}, state}
  end

  def handle_call(:get_state, _from, %{state: conn_state} = state) do
    {:reply, conn_state, state}
  end

  def handle_call(:get_state_internal, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_heartbeat_health, _from, state) do
    {:reply, HeartbeatManager.get_health(state), state}
  end

  def handle_call(:get_state_metrics, _from, state) do
    {:reply, Connection.metrics(state), state}
  end

  def handle_call(:get_latency_stats, _from, state) do
    {:reply, Connection.latency_summary(state), state}
  end

  @doc """
  Routes Client `handle_info/2` messages. Pins and fall-through match the original Client.
  """
  @spec handle_info(term(), map()) ::
          {:noreply, map()}
          | {:noreply, map(), {:continue, term()}}
          | {:stop, term(), map()}
  def handle_info(msg, state) do
    case transport_info(msg, state) do
      :unhandled -> timer_info(msg, state)
      result -> result
    end
  end

  @spec transport_info(term(), map()) ::
          :unhandled
          | {:noreply, map()}
          | {:noreply, map(), {:continue, term()}}
          | {:stop, term(), map()}
  defp transport_info(
         {:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers},
         %{gun_pid: gun_pid, stream_ref: stream_ref} = state
       ) do
    Connection.handle_upgrade(state, headers)
  end

  defp transport_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    Retry.handle_gun_error(state, gun_pid, stream_ref, reason)
  end

  defp transport_info({:gun_down, gun_pid, protocol, reason, killed_streams}, %{gun_pid: gun_pid} = state) do
    Retry.handle_gun_down(state, gun_pid, protocol, reason, killed_streams)
  end

  defp transport_info({:DOWN, ref, :process, gun_pid, reason}, %{gun_pid: gun_pid, monitor_ref: ref} = state) do
    Retry.handle_process_down(state, gun_pid, ref, reason)
  end

  defp transport_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    Frames.handle_ws(state, gun_pid, stream_ref, frame)
  end

  defp transport_info(_msg, _state), do: :unhandled

  @spec timer_info(term(), map()) ::
          {:noreply, map()}
          | {:noreply, map(), {:continue, term()}}
          | {:stop, term(), map()}
  defp timer_info({:connection_timeout, attempt}, %{state: :connecting, connection_attempt: attempt} = state) do
    Retry.handle_connection_timeout(state)
  end

  defp timer_info({:connection_timeout, _attempt}, state) do
    {:noreply, state}
  end

  defp timer_info(:retry_reconnect, state), do: Retry.handle_retry_reconnect(state)

  defp timer_info(:send_heartbeat, %{state: :connected, heartbeat_config: config} = state) when is_map(config) do
    Connection.tick_heartbeat(state, config)
  end

  defp timer_info(:send_heartbeat, state) do
    {:noreply, state}
  end

  defp timer_info({:timeout, _timeout_ref, {:correlation_timeout, _request_id}} = msg, state) do
    Frames.handle_timeout_message(state, msg)
  end

  defp timer_info({:correlation_timeout, _request_id} = msg, state) do
    Frames.handle_timeout_message(state, msg)
  end

  defp timer_info(_msg, state) do
    {:noreply, state}
  end
end
