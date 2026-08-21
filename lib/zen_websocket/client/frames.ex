defmodule ZenWebsocket.Client.Frames do
  @moduledoc """
  Inbound frame routing, JSON-RPC correlation, and session recording for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.Debug
  alias ZenWebsocket.HeartbeatManager
  alias ZenWebsocket.LatencyStats
  alias ZenWebsocket.MessageHandler
  alias ZenWebsocket.Recorder
  alias ZenWebsocket.RecorderServer
  alias ZenWebsocket.RequestCorrelator
  alias ZenWebsocket.SubscriptionManager

  require Logger

  @doc """
  Routes a Gun WebSocket frame: heartbeat tracking, control-frame decode, then data dispatch.
  """
  @spec handle_ws(map(), pid(), reference(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_ws(state, gun_pid, stream_ref, frame) do
    # Log WebSocket frame details
    case frame do
      {:text, _} ->
        Debug.log(state.config, "📨 [GUN WS TEXT] #{DateTime.to_string(DateTime.utc_now())}")

      {:binary, data} ->
        Debug.log(state.config, "📦 [GUN WS BINARY] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state.config, "   📏 Size: #{byte_size(data)} bytes")

      {:ping, payload} ->
        Debug.log(state.config, "🏓 [GUN WS PING] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state.config, "   📦 Payload: #{inspect(payload)}")

      {:pong, payload} ->
        Debug.log(state.config, "🏓 [GUN WS PONG] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state.config, "   📦 Payload: #{inspect(payload)}")

      {:close, code, reason} ->
        Debug.log(state.config, "🔒 [GUN WS CLOSE] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state.config, "   🔢 Code: #{code}")
        Debug.log(state.config, "   📝 Reason: #{inspect(reason)}")

      other ->
        Debug.log(state.config, "❓ [GUN WS OTHER] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state.config, "   🔍 Frame: #{inspect(other)}")
    end

    heartbeat_state = track_heartbeat_frame(frame, state)

    # Decode the frame. Control frames are classified only — Gun already
    # answered inbound pings. Uses decode_and_handle_control (not
    # handle_message) to avoid double handler delivery; route_data_frame
    # dispatches user callbacks.
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

  @doc """
  Sends a text frame, correlating JSON-RPC requests that carry an id.
  """
  @spec send_text(map(), pid(), reference(), binary(), GenServer.from()) ::
          {:noreply, map()} | {:reply, term(), map()}
  def send_text(state, gun_pid, stream_ref, message, from) do
    case RequestCorrelator.extract_id(message) do
      {:ok, id} ->
        case RequestCorrelator.track(state, id, from, state.config.request_timeout) do
          {:ok, new_state} ->
            new_state = track_subscription_outbound(new_state, message)
            :gun.ws_send(gun_pid, stream_ref, {:text, message})
            maybe_record(new_state.recorder_pid, :out, {:text, message})
            {:noreply, new_state}

          {:error, :duplicate_id, state} ->
            {:reply, {:error, :duplicate_request_id}, state}
        end

      :no_id ->
        state = track_subscription_outbound(state, message)
        result = :gun.ws_send(gun_pid, stream_ref, {:text, message})
        maybe_record(state.recorder_pid, :out, {:text, message})
        {:reply, result, state}
    end
  end

  @doc """
  Applies the pending-request pin checks for Erlang and legacy correlation timeouts.
  """
  @spec handle_timeout_message(map(), term()) :: {:noreply, map()}
  def handle_timeout_message(state, {:timeout, timeout_ref, {:correlation_timeout, request_id}}) do
    case Map.get(state.pending_requests, request_id) do
      {_from, ^timeout_ref, _start_time} ->
        handle_correlation_timeout(state, request_id)

      _other ->
        {:noreply, state}
    end
  end

  def handle_timeout_message(state, {:correlation_timeout, request_id}) do
    case Map.get(state.pending_requests, request_id) do
      {_from, _timeout_ref, _start_time} ->
        handle_correlation_timeout(state, request_id)

      _other ->
        {:noreply, state}
    end
  end

  @doc """
  Replies `{:error, :timeout}` to the caller waiting on `request_id`.
  """
  @spec handle_correlation_timeout(map(), term()) :: {:noreply, map()}
  def handle_correlation_timeout(state, request_id) do
    case RequestCorrelator.timeout(state, request_id) do
      {nil, state} ->
        {:noreply, state}

      {{from, _timeout_ref, _start_time}, new_state} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, new_state}
    end
  end

  @doc """
  Restores subscriptions after reconnection if configured.
  """
  @spec maybe_restore_subscriptions(map()) :: map()
  def maybe_restore_subscriptions(state) do
    case SubscriptionManager.build_restore_message(state) do
      nil ->
        state

      message ->
        Debug.log(state.config, "   📡 Restoring subscriptions...")
        :gun.ws_send(state.gun_pid, state.stream_ref, {:text, message})
        state
    end
  end

  @doc """
  Starts a session recorder when `record_to` is a path.
  """
  @spec maybe_start_recorder(String.t() | nil) :: pid() | nil
  def maybe_start_recorder(nil), do: nil

  def maybe_start_recorder(path) when is_binary(path) do
    case RecorderServer.start_link(path) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        Logger.warning("Failed to start session recorder: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Stops a session recorder if it is still alive.
  """
  @spec maybe_stop_recorder(pid() | nil) :: :ok
  def maybe_stop_recorder(nil), do: :ok

  def maybe_stop_recorder(recorder_pid) do
    if Process.alive?(recorder_pid) do
      RecorderServer.stop(recorder_pid)
    end

    :ok
  end

  @doc """
  Routes data frames to heartbeat, subscription, JSON-RPC, or the user handler.
  """
  @spec route_data_frame(term(), map()) :: map()
  def route_data_frame(frame, state) do
    # Record inbound frame
    maybe_record(state.recorder_pid, :in, frame)

    case frame do
      {:text, json_data} ->
        # Parse JSON and route based on message type
        case Jason.decode(json_data) do
          {:ok, %{"method" => "heartbeat"} = msg} ->
            # Handle heartbeat directly
            Debug.log(state.config, "💓 [HEARTBEAT DETECTED] #{DateTime.to_string(DateTime.utc_now())}")
            Debug.log(state.config, "   Heartbeat message: #{inspect(msg, pretty: true)}")
            HeartbeatManager.handle_message(msg, state)

          {:ok, %{"method" => "subscription"} = msg} ->
            # Market-data notifications are not subscribe confirmations.
            state.handler.({:message, msg})
            state

          {:ok, %{"id" => id} = msg} when is_integer(id) or is_binary(id) ->
            # JSON-RPC response - route to pending request
            handle_rpc_response(msg, state)

          {:ok, msg} ->
            # General message - forward to handler
            state.handler.({:message, msg})
            state

          {:error, _} ->
            # Non-JSON text frame
            state.handler.({:message, json_data})
            state
        end

      {:binary, data} ->
        # Binary frame
        state.handler.({:binary, data})
        state
    end
  end

  @spec maybe_record(pid() | nil, Recorder.direction(), term()) :: :ok
  defp maybe_record(nil, _direction, _frame), do: :ok

  defp maybe_record(recorder_pid, direction, frame) do
    RecorderServer.record(recorder_pid, direction, frame)
  end

  defp track_heartbeat_frame({:pong, payload}, %{heartbeat_config: %{type: :ping_pong}} = state) do
    HeartbeatManager.handle_message({:pong, payload}, state)
  end

  defp track_heartbeat_frame(_frame, state), do: state

  @spec handle_rpc_response(map(), map()) :: map()
  defp handle_rpc_response(%{"id" => id} = response, state) do
    state = SubscriptionManager.handle_message(response, state)

    case RequestCorrelator.resolve(state, id) do
      {nil, state} ->
        state.handler.({:unmatched_response, response})
        state

      {{from, _timeout_ref, start_time}, new_state} ->
        GenServer.reply(from, {:ok, response})

        # Update latency stats with round-trip time
        round_trip_ms = System.monotonic_time(:millisecond) - start_time
        updated_latency_stats = LatencyStats.add(new_state.latency_stats, round_trip_ms)
        %{new_state | latency_stats: updated_latency_stats}
    end
  end

  # Handles frame decode errors. Only :protocol_error is reachable —
  # ErrorHandler classifies every {:bad_frame, _} as fatal.
  @spec handle_frame_error(map(), {:protocol_error, term()}) :: {:stop, term(), map()}
  defp handle_frame_error(state, {:protocol_error, reason} = error) do
    # Notify handler before stopping — matches handler_message/0 contract
    state.handler.({:protocol_error, reason})
    {:stop, error, state}
  end

  @spec track_subscription_outbound(map(), binary()) :: map()
  defp track_subscription_outbound(state, message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> SubscriptionManager.handle_message(decoded, state)
      _ -> state
    end
  end
end
