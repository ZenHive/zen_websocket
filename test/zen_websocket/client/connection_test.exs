defmodule ZenWebsocket.ClientConnectionTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.ClientCallbacks, as: Callbacks
  alias ZenWebsocket.ClientConnection, as: Connection
  alias ZenWebsocket.Config

  test "initial_state/2 records handler, heartbeat, and recorder fields" do
    handler = fn _msg -> :ok end
    on_connect = fn _pid -> :ok end
    config = %Config{url: "ws://localhost/ws", latency_buffer_size: 10}

    state =
      Connection.initial_state(config, handler: handler, heartbeat_config: %{type: :ping_pong}, on_connect: on_connect)

    assert state.config == config
    assert state.url == "ws://localhost/ws"
    assert state.state == :disconnected
    assert state.handler == handler
    assert state.heartbeat_config == %{type: :ping_pong}
    assert state.on_connect == on_connect
    assert state.recorder_pid == nil
    assert state.retry_count == 0
    assert state.pending_requests == %{}
  end

  test "get_latency_stats callback returns nil when the sample buffer is empty" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    assert {:reply, nil, ^state} = Callbacks.handle_call(:get_latency_stats, {self(), make_ref()}, state)
  end

  test "send_heartbeat callback rearms without sending a Gun frame" do
    config = %{type: :custom, interval: 30}

    state =
      %Config{url: "ws://localhost/ws"}
      |> Connection.initial_state(heartbeat_config: config)
      |> Map.put(:state, :connected)

    assert {:noreply, new_state} = Callbacks.handle_info(:send_heartbeat, state)
    assert is_reference(new_state.heartbeat_timer)
    assert_receive :send_heartbeat, 200
  end

  test "get_state_metrics callback reports connection state and empty collection sizes" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    assert {:reply, metrics, ^state} = Callbacks.handle_call(:get_state_metrics, {self(), make_ref()}, state)

    assert metrics.connection_state == :disconnected
    assert metrics.active_heartbeats_size == 0
    assert metrics.subscriptions_size == 0
    assert metrics.pending_requests_size == 0
    assert metrics.heartbeat_timer_active == false
    assert is_integer(metrics.state_memory)
    assert is_integer(metrics.message_queue_len)
  end

  test "cleanup_failed_connection/1 clears gun fields and marks disconnected" do
    state =
      %Config{url: "ws://localhost/ws"}
      |> Connection.initial_state([])
      |> Map.merge(%{gun_pid: nil, stream_ref: make_ref(), monitor_ref: nil, state: :connecting})

    cleaned = Connection.cleanup_failed_connection(state)
    assert cleaned.state == :disconnected
    assert cleaned.gun_pid == nil
    assert cleaned.stream_ref == nil
    assert cleaned.monitor_ref == nil
  end

  test "handle_upgrade/2 emits connection upgrade telemetry and marks connected" do
    test_pid = self()
    handler_id = "client-connection-upgrade-#{System.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:zen_websocket, :connection, :upgrade],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    started_at = System.monotonic_time(:millisecond) - 25

    state =
      %Config{url: "ws://localhost/ws"}
      |> Connection.initial_state([])
      |> Map.merge(%{
        gun_pid: self(),
        stream_ref: make_ref(),
        connect_start_time: started_at,
        heartbeat_config: :disabled
      })

    assert {:noreply, connected} = Connection.handle_upgrade(state, [{"sec-websocket-accept", "test"}])
    assert connected.state == :connected
    assert connected.connect_start_time == nil
    assert connected.retry_count == 0

    assert_receive {:telemetry, [:zen_websocket, :connection, :upgrade], measurements, %{url: "ws://localhost/ws"}}
    assert measurements.connect_time_ms >= 25
  end
end
