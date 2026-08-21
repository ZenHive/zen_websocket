defmodule ZenWebsocket.Client.Connection do
  @moduledoc """
  Gun connection open, upgrade, and cleanup for `ZenWebsocket.Client`.

  Runs inside the Client GenServer process so Gun messages keep the same owner.
  Attempt-identity timers are preserved from the Task 2 rewrite. Retry decisions
  live in `ZenWebsocket.Client.Retry`.
  """

  alias ZenWebsocket.Client.Frames, as: Frames
  alias ZenWebsocket.Client.Recorder, as: RecorderLifecycle
  alias ZenWebsocket.Config
  alias ZenWebsocket.Debug
  alias ZenWebsocket.HeartbeatManager
  alias ZenWebsocket.LatencyStats
  alias ZenWebsocket.MessageHandler
  alias ZenWebsocket.Reconnection
  alias ZenWebsocket.RequestCorrelator

  @doc """
  Builds the GenServer state used by `Client.init/1`.
  """
  @spec initial_state(Config.t(), keyword()) :: map()
  def initial_state(%Config{} = config, opts) do
    %{
      config: config,
      gun_pid: nil,
      stream_ref: nil,
      state: :disconnected,
      monitor_ref: nil,
      url: config.url,
      handler: Keyword.get(opts, :handler, &MessageHandler.default_handler/1),
      subscriptions: MapSet.new(),
      pending_requests: %{},
      heartbeat_config: Keyword.get(opts, :heartbeat_config, :disabled),
      active_heartbeats: MapSet.new(),
      last_heartbeat_at: nil,
      heartbeat_failures: 0,
      heartbeat_timer: nil,
      heartbeat_ping_payload: nil,
      heartbeat_ping_sent_at: nil,
      retry_count: 0,
      connection_timer: nil,
      connection_attempt: nil,
      connect_start_time: nil,
      latency_stats: LatencyStats.new(max_size: config.latency_buffer_size),
      recorder_pid: RecorderLifecycle.maybe_start(config.record_to),
      on_connect: Keyword.get(opts, :on_connect),
      on_disconnect: Keyword.get(opts, :on_disconnect),
      reconnector: Keyword.get(opts, :reconnector)
    }
  end

  @doc """
  Opens the first Gun connection after `init/1`.
  """
  @spec continue_connect(map()) ::
          {:noreply, map()} | {:noreply, map(), {:continue, {:connection_failed, term()}}}
  def continue_connect(%{config: config} = state) do
    Debug.log(state.config, "🔌 [GUN CONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🌐 URL: #{config.url}")
    Debug.log(state.config, "   ⏱️  Timeout: #{config.timeout}ms")
    Debug.log(state.config, "   🔄 Establishing connection...")
    start_gun_attempt(state)
  end

  @doc """
  Opens a Gun connection on a scheduled or immediate reconnect.
  """
  @spec continue_reconnect(map()) ::
          {:noreply, map()} | {:noreply, map(), {:continue, {:connection_failed, term()}}}
  def continue_reconnect(%{config: config} = state) do
    current_attempt = Map.get(state, :retry_count, 0)

    Debug.log(state.config, "🔄 [GUN RECONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔢 Attempt: #{current_attempt + 1}")
    Debug.log(state.config, "   🌐 URL: #{config.url}")
    Debug.log(state.config, "   🔄 Re-establishing connection...")
    start_gun_attempt(state)
  end

  @doc """
  Marks the connection connected after a WebSocket upgrade.
  """
  @spec handle_upgrade(map(), term()) :: {:noreply, map()}
  def handle_upgrade(state, headers) do
    gun_pid = state.gun_pid
    stream_ref = state.stream_ref

    Debug.log(state.config, "🔗 [GUN UPGRADE] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   ✅ WebSocket connection upgraded successfully")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state.config, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(state.config, "   📋 Headers: #{inspect(headers, pretty: true)}")

    if state.connect_start_time do
      connect_time_ms = System.monotonic_time(:millisecond) - state.connect_start_time

      :telemetry.execute(
        [:zen_websocket, :connection, :upgrade],
        %{connect_time_ms: connect_time_ms},
        %{url: state.url}
      )
    end

    # Start heartbeat timer if configured
    # Reset retry_count so the next disconnect-reconnect cycle gets fresh retries
    new_state =
      state
      |> cancel_connection_timer()
      |> Map.merge(%{state: :connected, connect_start_time: nil, retry_count: 0})
      |> HeartbeatManager.start_timer()
      |> Frames.maybe_restore_subscriptions()

    Debug.log(state.config, "   🔄 State: :connecting → :connected")

    if Map.get(state, :heartbeat_config) != :disabled do
      Debug.log(state.config, "   💓 Heartbeat timer started")
    end

    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:ok, new_state})
      {:noreply, Map.delete(new_state, :awaiting_connection)}
    else
      {:noreply, new_state}
    end
  end

  @doc """
  Fails pending requests, cancels timers, and closes the Gun connection.
  """
  @spec cleanup_failed_connection(map()) :: map()
  def cleanup_failed_connection(state) do
    state
    |> RequestCorrelator.fail_all(:disconnected)
    |> HeartbeatManager.cancel_timer()
    |> cancel_connection_timer()
    |> close_gun()
    |> Map.put(:state, :disconnected)
  end

  @spec start_gun_attempt(map()) ::
          {:noreply, map()} | {:noreply, map(), {:continue, {:connection_failed, term()}}}
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

  @spec begin_attempt(map(), pid(), reference(), reference()) :: map()
  defp begin_attempt(state, gun_pid, stream_ref, monitor_ref) do
    state = arm_connection_timer(state)
    %{state | gun_pid: gun_pid, stream_ref: stream_ref, monitor_ref: monitor_ref, state: :connecting}
  end

  @spec arm_connection_timer(map()) :: map()
  defp arm_connection_timer(state) do
    state = cancel_connection_timer(state)
    attempt = make_ref()
    timer = Process.send_after(self(), {:connection_timeout, attempt}, state.config.timeout)
    %{state | connection_timer: timer, connection_attempt: attempt}
  end

  @spec cancel_connection_timer(map()) :: map()
  defp cancel_connection_timer(%{connection_timer: nil} = state), do: state

  defp cancel_connection_timer(%{connection_timer: timer} = state) do
    Process.cancel_timer(timer, async: false, info: false)
    %{state | connection_timer: nil}
  end

  defp cancel_connection_timer(state), do: Map.put(state, :connection_timer, nil)

  @spec close_gun(map()) :: map()
  defp close_gun(state) do
    if is_reference(state.monitor_ref), do: Process.demonitor(state.monitor_ref, [:flush])
    if is_pid(state.gun_pid), do: :gun.close(state.gun_pid)
    %{state | gun_pid: nil, stream_ref: nil, monitor_ref: nil}
  end
end
