defmodule ZenWebsocket.HeartbeatManagerTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.HeartbeatManager
  alias ZenWebsocket.Test.Support.MockWebSockServer

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

    test "handles unknown heartbeat message gracefully" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})
      msg = %{"unknown" => "format"}

      result = HeartbeatManager.handle_message(msg, state)

      assert result == state
    end
  end

  describe "send_heartbeat/1" do
    test "returns state unchanged for unknown heartbeat type" do
      state = build_state(%{heartbeat_config: %{type: :unknown}})
      result = HeartbeatManager.send_heartbeat(state)

      assert result == state
    end

    @tag :integration
    @tag timeout: 10_000
    test "sends ping frame and updates last_heartbeat_at for ping_pong type" do
      # Start mock WebSocket server
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
        :ping -> {:reply, :pong}
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

      # Verify last_heartbeat_at was updated (monotonic time can be negative)
      assert is_integer(result.last_heartbeat_at)

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
