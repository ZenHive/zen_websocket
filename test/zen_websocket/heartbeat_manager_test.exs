defmodule ZenWebsocket.HeartbeatManagerTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.HeartbeatManager
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @heartbeat_interval_ms 60_000

  # Helper to build test state with required fields
  defp build_state(overrides) do
    default_config = %ZenWebsocket.Config{
      url: "wss://test.example.com",
      timeout: 5000,
      retry_count: 3,
      retry_delay: 1000,
      max_backoff: 30_000,
      heartbeat_interval: 30_000,
      request_timeout: 10_000,
      reconnect_on_error: true
    }

    Map.merge(
      %{
        config: default_config,
        heartbeat_config: :disabled,
        heartbeat_timer: nil,
        heartbeat_failures: 0,
        active_heartbeats: MapSet.new(),
        last_heartbeat_at: nil,
        heartbeat_ping_payload: nil,
        heartbeat_ping_sent_at: nil,
        gun_pid: nil,
        stream_ref: nil
      },
      overrides
    )
  end

  describe "start_timer/1" do
    test "returns state unchanged when heartbeat disabled" do
      state = build_state(%{heartbeat_config: :disabled})
      result = HeartbeatManager.start_timer(state)

      assert result == state
      assert result.heartbeat_timer == nil
    end

    test "starts timer when heartbeat config is a map" do
      state = build_state(%{heartbeat_config: %{type: :deribit, interval: 15_000}})
      result = HeartbeatManager.start_timer(state)

      assert is_reference(result.heartbeat_timer)
      # Clean up timer
      Process.cancel_timer(result.heartbeat_timer)
    end

    test "uses config interval when not specified in heartbeat_config" do
      state = build_state(%{heartbeat_config: %{type: :deribit}})
      result = HeartbeatManager.start_timer(state)

      assert is_reference(result.heartbeat_timer)
      Process.cancel_timer(result.heartbeat_timer)
    end

    test "returns state unchanged for nil heartbeat_config" do
      state = build_state(%{heartbeat_config: nil})
      result = HeartbeatManager.start_timer(state)

      assert result == state
    end
  end

  describe "cancel_timer/1" do
    test "returns state unchanged when no timer active" do
      state = build_state(%{heartbeat_timer: nil, heartbeat_failures: 5})
      result = HeartbeatManager.cancel_timer(state)

      assert result.heartbeat_timer == nil
      # Note: failures not reset when no timer to cancel
      assert result.heartbeat_failures == 5
    end

    test "cancels timer and resets failures when timer active" do
      timer_ref = Process.send_after(self(), :test, 60_000)
      state = build_state(%{heartbeat_timer: timer_ref, heartbeat_failures: 3})

      result = HeartbeatManager.cancel_timer(state)

      assert result.heartbeat_timer == nil
      assert result.heartbeat_failures == 0
    end
  end

  describe "handle_message/2" do
    test "routes to Deribit handler for deribit config" do
      state =
        build_state(%{
          heartbeat_config: %{type: :deribit},
          gun_pid: self(),
          stream_ref: make_ref()
        })

      msg = %{"params" => %{"type" => "test_request"}}

      result = HeartbeatManager.handle_message(msg, state)

      # Deribit handler updates active_heartbeats
      assert MapSet.member?(result.active_heartbeats, :deribit_test_request)
    end

    test "returns state unchanged for binance config" do
      state = build_state(%{heartbeat_config: %{type: :binance}})
      msg = %{"method" => "heartbeat"}

      result = HeartbeatManager.handle_message(msg, state)

      assert result == state
    end

    test "handles generic heartbeat with type" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})
      msg = %{"method" => "heartbeat", "params" => %{"type" => "ping"}}

      result = HeartbeatManager.handle_message(msg, state)

      assert MapSet.member?(result.active_heartbeats, "ping")
      assert result.heartbeat_failures == 0
      assert is_integer(result.last_heartbeat_at)
    end

    test "generic heartbeats replace the active set instead of accumulating types" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})

      first = HeartbeatManager.handle_message(%{"method" => "heartbeat", "params" => %{"type" => "ping"}}, state)

      second =
        HeartbeatManager.handle_message(%{"method" => "heartbeat", "params" => %{"type" => "custom"}}, first)

      assert MapSet.to_list(second.active_heartbeats) == ["custom"]
    end

    test "handles unknown heartbeat message gracefully" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})
      msg = %{"unknown" => "format"}

      result = HeartbeatManager.handle_message(msg, state)

      assert result == state
    end

    test "only acknowledges the pong matching the outstanding ping" do
      sent_state =
        %{
          heartbeat_config: %{type: :ping_pong},
          gun_pid: self(),
          stream_ref: make_ref(),
          heartbeat_failures: 2
        }
        |> build_state()
        |> HeartbeatManager.send_heartbeat()

      payload = sent_state.heartbeat_ping_payload

      assert HeartbeatManager.handle_message({:pong, "other-ping"}, sent_state) == sent_state

      acknowledged = HeartbeatManager.handle_message({:pong, payload}, sent_state)

      assert MapSet.member?(acknowledged.active_heartbeats, :ping_pong)
      assert acknowledged.heartbeat_failures == 0
      assert acknowledged.heartbeat_ping_payload == nil
      assert acknowledged.heartbeat_ping_sent_at == nil
      assert is_integer(acknowledged.last_heartbeat_at)
    end

    test "emits round-trip telemetry when a previous heartbeat timestamp exists" do
      test_pid = self()
      handler_id = "heartbeat-manager-test-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:zen_websocket, :heartbeat, :pong],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      previous_ts = System.monotonic_time(:millisecond) - 250

      state =
        build_state(%{
          heartbeat_config: %{type: :unknown},
          last_heartbeat_at: previous_ts,
          heartbeat_failures: 3
        })

      msg = %{"method" => "heartbeat", "params" => %{"type" => "custom"}}

      result = HeartbeatManager.handle_message(msg, state)

      assert_receive {:telemetry, [:zen_websocket, :heartbeat, :pong], measurements, %{type: "custom"}}
      # rtt_ms is computed as now - previous_ts, so it must be >= the gap we seeded.
      assert measurements.rtt_ms >= 250

      assert MapSet.member?(result.active_heartbeats, "custom")
      assert result.heartbeat_failures == 0
      assert result.last_heartbeat_at > previous_ts
    end
  end

  describe "send_heartbeat/1" do
    test "returns state unchanged for unknown heartbeat type" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})
      result = HeartbeatManager.send_heartbeat(state)

      assert result == state
    end

    test "reports a missed pong when the next ping is sent unanswered" do
      state =
        build_state(%{
          heartbeat_config: %{type: :ping_pong},
          gun_pid: self(),
          stream_ref: make_ref()
        })

      first_ping = HeartbeatManager.send_heartbeat(state)
      second_ping = HeartbeatManager.send_heartbeat(first_ping)

      assert first_ping.heartbeat_ping_payload != second_ping.heartbeat_ping_payload
      assert HeartbeatManager.get_health(second_ping).failure_count == 1
    end

    @tag :integration
    @tag timeout: 10_000
    test "client health reports a failure when the server withholds pongs" do
      {:ok, server, port} = MockWebSockServer.start_link()
      MockWebSockServer.set_handler(server, fn _frame -> :ok end)

      {:ok, client} =
        Client.connect("ws://localhost:#{port}/ws",
          heartbeat_config: %{type: :ping_pong, interval: @heartbeat_interval_ms}
        )

      on_exit(fn ->
        Client.close(client)
        MockWebSockServer.stop(server)
      end)

      send(client.server_pid, :send_heartbeat)
      send(client.server_pid, :send_heartbeat)

      assert Client.get_heartbeat_health(client).failure_count == 1
    end

    @tag :integration
    @tag timeout: 10_000
    test "client correlates the server pong with its outstanding ping" do
      test_pid = self()
      handler_id = "ping-pong-client-test-#{System.unique_integer()}"
      {:ok, server, port} = MockWebSockServer.start_link()

      handler = fn
        {:text, "handler-ready"} ->
          send(test_pid, :handler_ready)
          :ok

        {:ping, payload} ->
          {:reply, {:pong, payload}}

        _frame ->
          :ok
      end

      MockWebSockServer.set_handler(server, handler)

      :telemetry.attach(
        handler_id,
        [:zen_websocket, :heartbeat, :pong],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, client} =
        Client.connect("ws://localhost:#{port}/ws",
          heartbeat_config: %{type: :ping_pong, interval: @heartbeat_interval_ms}
        )

      MockWebSockServer.set_handler(server, handler)
      :ok = Client.send_message(client, "handler-ready")
      assert_receive :handler_ready

      on_exit(fn ->
        :telemetry.detach(handler_id)
        Client.close(client)
        MockWebSockServer.stop(server)
      end)

      send(client.server_pid, :send_heartbeat)

      assert_receive {:telemetry, [:zen_websocket, :heartbeat, :pong], %{rtt_ms: rtt_ms}, %{type: :ping_pong}}

      assert rtt_ms >= 0
      assert Client.get_heartbeat_health(client).failure_count == 0
      assert is_integer(Client.get_heartbeat_health(client).last_heartbeat_at)
    end

    @tag :integration
    @tag timeout: 10_000
    test "sends a correlated ping frame over a real WebSocket connection" do
      # Start mock WebSocket server
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
        {:ping, payload} -> {:reply, {:pong, payload}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      # Connect client to get real gun_pid and stream_ref
      {:ok, client} = Client.connect(mock_url)

      # Get internal state to extract gun_pid and stream_ref
      client_state = :sys.get_state(client.server_pid)

      # Build heartbeat state with real connection handles
      state =
        build_state(%{
          heartbeat_config: %{type: :ping_pong},
          gun_pid: client_state.gun_pid,
          stream_ref: client_state.stream_ref,
          last_heartbeat_at: nil
        })

      # Send ping_pong heartbeat
      result = HeartbeatManager.send_heartbeat(state)

      assert is_binary(result.heartbeat_ping_payload)
      assert is_integer(result.heartbeat_ping_sent_at)

      # Clean up
      Client.close(client)
      MockWebSockServer.stop(server)
    end

    test "returns unchanged state when heartbeat_config is nil" do
      state = build_state(%{heartbeat_config: nil})
      result = HeartbeatManager.send_heartbeat(state)

      assert result == state
    end
  end

  describe "get_health/1" do
    test "returns health map with all fields" do
      state =
        build_state(%{
          heartbeat_config: %{type: :deribit, interval: 15_000},
          active_heartbeats: MapSet.new([:deribit_test_request]),
          last_heartbeat_at: 12_345,
          heartbeat_failures: 2,
          heartbeat_timer: make_ref()
        })

      health = HeartbeatManager.get_health(state)

      assert health.active_heartbeats == [:deribit_test_request]
      assert health.last_heartbeat_at == 12_345
      assert health.failure_count == 2
      assert health.config == %{type: :deribit, interval: 15_000}
      assert health.timer_active == true
    end

    test "returns defaults for missing fields" do
      health = HeartbeatManager.get_health(%{})

      assert health.active_heartbeats == []
      assert health.last_heartbeat_at == nil
      assert health.failure_count == 0
      assert health.config == :disabled
      assert health.timer_active == false
    end

    test "handles empty state gracefully" do
      health = HeartbeatManager.get_health(%{heartbeat_timer: nil})

      assert health.timer_active == false
    end
  end
end
