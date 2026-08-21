defmodule ZenWebsocket.Helpers.DeribitTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.Helpers.Deribit
  alias ZenWebsocket.Test.Support.MockWebSockServer

  defp heartbeat_state(overrides \\ %{}) do
    Map.merge(
      %{
        active_heartbeats: MapSet.new(),
        gun_pid: self(),
        heartbeat_failures: 2,
        last_heartbeat_at: nil,
        stream_ref: make_ref()
      },
      overrides
    )
  end

  test "responds to test_request with public/test and records the heartbeat" do
    test_pid = self()
    handler_id = "deribit-helper-test-#{System.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:zen_websocket, :heartbeat, :pong],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    previous_heartbeat = System.monotonic_time(:millisecond) - 10
    state = heartbeat_state(%{last_heartbeat_at: previous_heartbeat})

    result = Deribit.handle_heartbeat(%{"params" => %{"type" => "test_request"}}, state)

    assert_receive {:telemetry, [:zen_websocket, :heartbeat, :pong], measurements, %{type: :deribit_test_request}}

    assert measurements.rtt_ms >= 10
    assert MapSet.member?(result.active_heartbeats, :deribit_test_request)
    assert result.heartbeat_failures == 0
    assert result.last_heartbeat_at > previous_heartbeat
  end

  test "sends public/test as the outbound heartbeat" do
    state = heartbeat_state()

    result = Deribit.send_heartbeat(state)

    assert is_integer(result.last_heartbeat_at)
  end

  @tag :integration
  test "sends public/test over a real WebSocket in response to test_request" do
    test_pid = self()
    {:ok, server, port} = MockWebSockServer.start_link()

    handler = fn frame ->
      send(test_pid, {:server_frame, frame})
      :ok
    end

    MockWebSockServer.set_handler(server, handler)
    {:ok, client} = Client.connect("ws://localhost:#{port}/ws")
    MockWebSockServer.set_handler(server, handler)

    on_exit(fn ->
      Client.close(client)
      MockWebSockServer.stop(server)
    end)

    :ok = Client.send_message(client, "handler-ready")
    assert_receive {:server_frame, {:text, "handler-ready"}}

    client_state = :sys.get_state(client.server_pid)

    state =
      heartbeat_state(%{
        gun_pid: client_state.gun_pid,
        stream_ref: client_state.stream_ref
      })

    result = Deribit.handle_heartbeat(%{"params" => %{"type" => "test_request"}}, state)

    assert_receive {:server_frame, {:text, payload}}
    assert Jason.decode!(payload) == %{"jsonrpc" => "2.0", "method" => "public/test", "params" => %{}}
    assert MapSet.member?(result.active_heartbeats, :deribit_test_request)
  end
end
