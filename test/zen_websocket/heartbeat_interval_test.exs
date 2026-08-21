defmodule ZenWebsocket.HeartbeatIntervalTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.HeartbeatInterval

  defp state(overrides) do
    Map.merge(
      %{
        active_heartbeats: MapSet.new([:existing]),
        heartbeat_failures: 3,
        last_heartbeat_at: nil
      },
      overrides
    )
  end

  test "records the supplied active set and clears failures" do
    result = HeartbeatInterval.record_pong(state(%{}), :deribit_test_request, MapSet.new([:deribit_test_request]))

    assert MapSet.to_list(result.active_heartbeats) == [:deribit_test_request]
    assert result.heartbeat_failures == 0
    assert is_integer(result.last_heartbeat_at)
  end

  test "does not emit telemetry when no previous timestamp exists" do
    test_pid = self()
    handler_id = "heartbeat-interval-none-#{System.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:zen_websocket, :heartbeat, :pong],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    HeartbeatInterval.record_pong(state(%{last_heartbeat_at: nil}), :ping, MapSet.new([:ping]))

    refute_received {:telemetry, [:zen_websocket, :heartbeat, :pong], _, _}
  end

  test "emits interval telemetry when a previous timestamp exists" do
    test_pid = self()
    handler_id = "heartbeat-interval-pong-#{System.unique_integer()}"

    :telemetry.attach(
      handler_id,
      [:zen_websocket, :heartbeat, :pong],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    previous = System.monotonic_time(:millisecond) - 120

    result =
      HeartbeatInterval.record_pong(
        state(%{last_heartbeat_at: previous, heartbeat_failures: 4}),
        :deribit_test_request,
        MapSet.put(state(%{}).active_heartbeats, :deribit_test_request)
      )

    assert_receive {:telemetry, [:zen_websocket, :heartbeat, :pong], measurements, %{type: :deribit_test_request}}
    assert measurements.rtt_ms >= 120
    assert MapSet.member?(result.active_heartbeats, :existing)
    assert MapSet.member?(result.active_heartbeats, :deribit_test_request)
    assert result.heartbeat_failures == 0
    assert result.last_heartbeat_at > previous
  end
end
