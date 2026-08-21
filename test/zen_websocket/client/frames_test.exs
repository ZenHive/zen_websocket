defmodule ZenWebsocket.Client.FramesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenWebsocket.Client.Connection, as: Connection
  alias ZenWebsocket.Client.Correlation, as: Correlation
  alias ZenWebsocket.Client.Frames, as: Frames
  alias ZenWebsocket.Client.Recorder, as: RecorderLifecycle
  alias ZenWebsocket.Config
  alias ZenWebsocket.LatencyStats

  test "route_data_frame/2 delivers JSON maps, non-JSON text, and binary frames" do
    parent = self()
    state = frame_state(fn msg -> send(parent, msg) end)

    Frames.route_data_frame({:text, ~s({"foo":1})}, state)
    assert_received {:message, %{"foo" => 1}}

    Frames.route_data_frame({:text, "not-json"}, state)
    assert_received {:message, "not-json"}

    Frames.route_data_frame({:binary, <<1, 2>>}, state)
    assert_received {:binary, <<1, 2>>}
  end

  test "route_data_frame/2 forwards subscription notifications without treating them as confirms" do
    parent = self()
    state = frame_state(fn msg -> send(parent, msg) end)
    msg = %{"method" => "subscription", "params" => %{"channel" => "trades"}}

    new_state = Frames.route_data_frame({:text, Jason.encode!(msg)}, state)
    assert new_state.subscriptions == MapSet.new()
    assert_received {:message, ^msg}
  end

  test "route_data_frame/2 routes heartbeat JSON through HeartbeatManager" do
    state = frame_state(fn _msg -> flunk("handler") end)
    heartbeat = %{"method" => "heartbeat", "params" => %{"type" => "test"}}

    log =
      capture_log(fn ->
        new_state = Frames.route_data_frame({:text, Jason.encode!(heartbeat)}, state)
        assert new_state.heartbeat_failures == 0
        assert MapSet.member?(new_state.active_heartbeats, "test")
      end)

    assert log =~ "PLATFORM HEARTBEAT" or log =~ "HEARTBEAT"
  end

  test "route_data_frame/2 delivers unmatched JSON-RPC responses to the handler" do
    parent = self()
    response = %{"id" => 42, "result" => "ok"}
    Frames.route_data_frame({:text, Jason.encode!(response)}, frame_state(fn msg -> send(parent, msg) end))
    assert_received {:unmatched_response, ^response}
  end

  test "handle_ws/4 treats ping as a handled control frame" do
    state = frame_state(fn _msg -> flunk("handler") end)
    assert {:noreply, ^state} = Frames.handle_ws(state, self(), make_ref(), {:ping, "hi"})
  end

  test "handle_ws/4 stops on a protocol error after notifying the handler" do
    parent = self()
    state = frame_state(fn msg -> send(parent, msg) end)

    assert {:stop, {:protocol_error, reason}, ^state} = Frames.handle_ws(state, self(), make_ref(), {:unknown, <<>>})
    assert is_binary(reason)
    assert_received {:protocol_error, ^reason}
  end

  test "maybe_restore_subscriptions/1 is a no-op when nothing is subscribed" do
    state = frame_state(fn _msg -> :ok end)
    assert Frames.maybe_restore_subscriptions(state) == state
  end

  test "maybe_start_recorder/1 returns nil for a missing path and for a missing parent dir" do
    assert RecorderLifecycle.maybe_start(nil) == nil

    log =
      capture_log(fn ->
        assert RecorderLifecycle.maybe_start("/definitely/missing/#{System.unique_integer()}/session.jsonl") == nil
      end)

    assert log =~ "Failed to start session recorder"
  end

  test "maybe_stop_recorder/1 is a no-op for nil" do
    assert RecorderLifecycle.maybe_stop(nil) == :ok
  end

  test "handle_correlation_timeout/2 is a no-op when the id is not pending" do
    state = frame_state(fn _msg -> flunk("handler") end)
    assert {:noreply, ^state} = Correlation.handle_timeout(state, "missing")
  end

  test "handle_timeout_message/2 ignores a stale Erlang timer ref" do
    from = {self(), make_ref()}
    timeout_ref = make_ref()
    state = pending_state(from, timeout_ref)

    assert {:noreply, ^state} =
             Correlation.handle_timeout_message(state, {:timeout, make_ref(), {:correlation_timeout, "id"}})

    refute_received {_, {:error, :timeout}}
  end

  test "handle_timeout_message/2 times out a matching Erlang timer" do
    {_pid, from_ref} = from = {self(), make_ref()}
    timeout_ref = make_ref()
    state = pending_state(from, timeout_ref)

    assert {:noreply, new_state} =
             Correlation.handle_timeout_message(state, {:timeout, timeout_ref, {:correlation_timeout, "id"}})

    assert new_state.pending_requests == %{}
    assert_receive {^from_ref, {:error, :timeout}}
  end

  test "handle_timeout_message/2 times out a legacy correlation timeout" do
    {_pid, from_ref} = from = {self(), make_ref()}
    state = pending_state(from, make_ref())

    assert {:noreply, new_state} = Correlation.handle_timeout_message(state, {:correlation_timeout, "id"})
    assert new_state.pending_requests == %{}
    assert_receive {^from_ref, {:error, :timeout}}
  end

  defp frame_state(handler) do
    %Config{url: "ws://localhost/ws"}
    |> Connection.initial_state(handler: handler)
    |> Map.put(:latency_stats, LatencyStats.new())
  end

  defp pending_state(from, timeout_ref) do
    fn _msg -> flunk("handler") end
    |> frame_state()
    |> Map.put(:pending_requests, %{"id" => {from, timeout_ref, 0}})
  end
end
