defmodule ZenWebsocket.Client.Retry do
  @moduledoc """
  Connection-error retry state machine for `ZenWebsocket.Client`.

  Attempt-identity timers live in `ZenWebsocket.Client.Connection`; this module
  decides whether to reconnect immediately, schedule backoff, or stop.
  """

  alias ZenWebsocket.Client.Connection
  alias ZenWebsocket.Client.Frames
  alias ZenWebsocket.Debug
  alias ZenWebsocket.Reconnection

  @doc """
  Handles a failed open by cleaning up and maybe scheduling a retry.
  """
  @spec continue_failed(map(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def continue_failed(state, reason) do
    state
    |> Map.put(:state, :disconnected)
    |> Connection.cleanup_failed_connection()
    |> maybe_retry_open(reason)
  end

  @doc """
  Logs a Gun stream error and runs the retry state machine.
  """
  @spec handle_gun_error(map(), pid(), reference(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_gun_error(state, gun_pid, stream_ref, reason) do
    Debug.log(state.config, "❌ [GUN ERROR] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state.config, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(state.config, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🔄 Triggering connection error handling...")

    handle_connection_error(state, {:gun_error, gun_pid, stream_ref, reason})
  end

  @doc """
  Logs a Gun down event and runs the retry state machine.
  """
  @spec handle_gun_down(map(), pid(), term(), term(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_gun_down(state, gun_pid, protocol, reason, killed_streams) do
    Debug.log(state.config, "📉 [GUN DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state.config, "   🌐 Protocol: #{inspect(protocol)}")
    Debug.log(state.config, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🚫 Killed Streams: #{inspect(killed_streams)}")
    Debug.log(state.config, "   🔄 Connection lost, triggering error handling...")

    handle_connection_error(state, {:gun_down, gun_pid, protocol, reason, killed_streams})
  end

  @doc """
  Logs a monitored Gun process exit and runs the retry state machine.
  """
  @spec handle_process_down(map(), pid(), reference(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_process_down(state, gun_pid, ref, reason) do
    Debug.log(state.config, "💀 [PROCESS DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)} (monitored process)")
    Debug.log(state.config, "   📍 Monitor Ref: #{inspect(ref)}")
    Debug.log(state.config, "   💥 Exit Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🔄 Process terminated, triggering connection error handling...")

    handle_connection_error(state, {:connection_down, reason})
  end

  @doc """
  Times out the in-flight connection attempt when the attempt identity matches.
  """
  @spec handle_connection_timeout(map()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_connection_timeout(state) do
    Debug.log(state.config, "⏰ [CONNECTION TIMEOUT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔄 State: :connecting (timeout)")
    Debug.log(state.config, "   🔄 Triggering connection error handling...")

    handle_connection_error(%{state | connection_timer: nil}, :timeout)
  end

  @doc """
  Handles a scheduled reconnect tick, stopping when retries are exhausted.
  """
  @spec handle_retry_reconnect(map()) ::
          {:noreply, map()} | {:noreply, map(), {:continue, :reconnect}} | {:stop, term(), map()}
  def handle_retry_reconnect(%{config: config} = state) do
    current_retries = Map.get(state, :retry_count, 0)

    Debug.log(state.config, "🔄 [RETRY RECONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔢 Current Retries: #{current_retries}")
    Debug.log(state.config, "   🔢 Max Retries: #{config.retry_count}")

    if Reconnection.max_retries_exceeded?(current_retries, config.retry_count) do
      Debug.log(state.config, "   🚫 Max reconnection attempts exceeded")
      Debug.log(state.config, "   🛑 Stopping GenServer with reason: :max_reconnection_attempts")
      stop_with_error(state, :max_reconnection_attempts)
    else
      Debug.log(state.config, "   ✅ Retries within limit, attempting reconnection...")
      {:noreply, state, {:continue, :reconnect}}
    end
  end

  @doc """
  True when the current error should open a new Gun attempt immediately or later.
  """
  @spec retry_now?(map(), term()) :: boolean()
  def retry_now?(state, reason) do
    state.config.reconnect_on_error and
      Reconnection.should_reconnect?(reason) and
      not Reconnection.max_retries_exceeded?(state.retry_count, state.config.retry_count)
  end

  @doc """
  Unwraps nested Gun/shutdown error tuples to the inner reason.
  """
  @spec normalize_error(term()) :: term()
  def normalize_error({:error, reason}), do: normalize_error(reason)
  def normalize_error({:shutdown, reason}), do: normalize_error(reason)
  def normalize_error({:gun_error, _pid, _stream, reason}), do: reason
  def normalize_error({:gun_error, _pid, reason}), do: reason
  def normalize_error(reason), do: reason

  # Handles connection errors and triggers internal reconnection when appropriate.
  # This maintains Gun ownership by reconnecting from within the same GenServer.
  @spec handle_connection_error(map(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  defp handle_connection_error(state, reason) do
    conn_state = state.state
    retry? = retry_now?(state, reason)
    state = Connection.cleanup_failed_connection(state)

    cond do
      retry? and conn_state == :connected ->
        {:noreply, state, {:continue, :reconnect}}

      retry? ->
        schedule_retry(state)

      true ->
        stop_with_error(state, reason)
    end
  end

  @spec maybe_retry_open(map(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  defp maybe_retry_open(state, reason) do
    retry? =
      state.config.reconnect_on_error and
        not Reconnection.max_retries_exceeded?(state.retry_count, state.config.retry_count)

    if retry?, do: schedule_retry(state), else: stop_with_error(state, reason)
  end

  @spec schedule_retry(map()) :: {:noreply, map()} | {:stop, term(), map()}
  defp schedule_retry(state) do
    count = state.retry_count + 1
    state = %{state | retry_count: count}

    if Reconnection.max_retries_exceeded?(count, state.config.retry_count) do
      stop_with_error(state, :max_reconnection_attempts)
    else
      delay = Reconnection.calculate_backoff(count - 1, state.config.retry_delay, state.config.max_backoff)
      Process.send_after(self(), :retry_reconnect, delay)
      {:noreply, state}
    end
  end

  @spec stop_with_error(map(), term()) :: {:stop, term(), map()}
  defp stop_with_error(state, reason) do
    reason = normalize_error(reason)
    Frames.maybe_stop_recorder(state.recorder_pid)
    {:stop, reason, reply_awaiting(state, {:error, reason})}
  end

  @spec reply_awaiting(map(), term()) :: map()
  defp reply_awaiting(state, reply) do
    case Map.pop(state, :awaiting_connection) do
      {nil, state} ->
        state

      {from, state} ->
        GenServer.reply(from, reply)
        state
    end
  end
end
