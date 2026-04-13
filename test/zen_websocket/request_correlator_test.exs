defmodule ZenWebsocket.RequestCorrelatorTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.RequestCorrelator

  # Helper to build test state with required fields
  defp build_state(overrides \\ %{}) do
    Map.merge(%{pending_requests: %{}}, overrides)
  end

  describe "extract_id/1" do
    test "extracts integer ID from JSON message" do
      message = Jason.encode!(%{"id" => 42, "method" => "test"})
      assert {:ok, 42} = RequestCorrelator.extract_id(message)
    end

    test "extracts string ID from JSON message" do
      message = Jason.encode!(%{"id" => "req-123", "method" => "test"})
      assert {:ok, "req-123"} = RequestCorrelator.extract_id(message)
    end

    test "returns :no_id when message has no ID field" do
      message = Jason.encode!(%{"method" => "test"})
      assert :no_id = RequestCorrelator.extract_id(message)
    end

    test "returns :no_id when ID is nil" do
      message = Jason.encode!(%{"id" => nil, "method" => "test"})
      assert :no_id = RequestCorrelator.extract_id(message)
    end

    test "returns :no_id for invalid JSON" do
      assert :no_id = RequestCorrelator.extract_id("not json")
    end

    test "returns :no_id for empty string" do
      assert :no_id = RequestCorrelator.extract_id("")
    end

    test "returns :no_id for non-binary input" do
      assert :no_id = RequestCorrelator.extract_id(123)
      assert :no_id = RequestCorrelator.extract_id(nil)
      assert :no_id = RequestCorrelator.extract_id(%{})
    end
  end

  describe "track/4" do
    test "adds request to pending_requests map with timestamp" do
      state = build_state()
      from = {self(), make_ref()}

      new_state = RequestCorrelator.track(state, 42, from, 5000)

      assert Map.has_key?(new_state.pending_requests, 42)
      {stored_from, timeout_ref, start_time} = new_state.pending_requests[42]
      assert stored_from == from
      assert is_reference(timeout_ref)
      assert is_integer(start_time)

      # Clean up timer
      Process.cancel_timer(timeout_ref)
    end

    test "creates timer that sends a unique timeout ref with the correlation message" do
      state = build_state()
      from = {self(), make_ref()}

      # Use short timeout for testing
      new_state = RequestCorrelator.track(state, "test-id", from, 50)
      {_from, timeout_ref, _start_time} = new_state.pending_requests["test-id"]

      # Should receive timeout message
      assert_receive {:timeout, ^timeout_ref, {:correlation_timeout, "test-id"}}, 200
    end

    test "tracks multiple requests with different IDs" do
      state = build_state()
      from1 = {self(), make_ref()}
      from2 = {self(), make_ref()}

      state =
        state
        |> RequestCorrelator.track(1, from1, 5000)
        |> RequestCorrelator.track(2, from2, 5000)

      assert map_size(state.pending_requests) == 2
      assert Map.has_key?(state.pending_requests, 1)
      assert Map.has_key?(state.pending_requests, 2)

      # Clean up timers
      for {_id, {_from, timer_ref, _start_time}} <- state.pending_requests do
        Process.cancel_timer(timer_ref)
      end
    end
  end

  describe "resolve/2" do
    test "returns entry and removes request from pending" do
      from = {self(), make_ref()}
      timeout_ref = make_ref()
      start_time = System.monotonic_time(:millisecond)
      state = build_state(%{pending_requests: %{42 => {from, timeout_ref, start_time}}})

      {entry, new_state} = RequestCorrelator.resolve(state, 42)

      assert entry == {from, timeout_ref, start_time}
      refute Map.has_key?(new_state.pending_requests, 42)
    end

    test "cancels timeout timer on resolve" do
      state = build_state()
      from = {self(), make_ref()}

      # Track with real timer
      state = RequestCorrelator.track(state, "cancel-test", from, 5000)
      {_from, timeout_ref, _start_time} = state.pending_requests["cancel-test"]

      # Resolve should cancel the timer
      {_entry, _new_state} = RequestCorrelator.resolve(state, "cancel-test")

      # Should NOT receive timeout message
      refute_receive {:timeout, ^timeout_ref, {:correlation_timeout, "cancel-test"}}, 100
    end

    test "returns nil for unknown request ID" do
      start_time = System.monotonic_time(:millisecond)
      state = build_state(%{pending_requests: %{42 => {{self(), make_ref()}, make_ref(), start_time}}})

      {entry, new_state} = RequestCorrelator.resolve(state, 999)

      assert entry == nil
      # State unchanged
      assert new_state.pending_requests == state.pending_requests
    end

    test "returns nil for empty pending_requests" do
      state = build_state()

      {entry, new_state} = RequestCorrelator.resolve(state, 42)

      assert entry == nil
      assert new_state.pending_requests == %{}
    end
  end

  describe "timeout/2" do
    test "returns entry and removes request from pending" do
      from = {self(), make_ref()}
      timeout_ref = make_ref()
      start_time = System.monotonic_time(:millisecond)
      state = build_state(%{pending_requests: %{42 => {from, timeout_ref, start_time}}})

      {entry, new_state} = RequestCorrelator.timeout(state, 42)

      assert entry == {from, timeout_ref, start_time}
      refute Map.has_key?(new_state.pending_requests, 42)
    end

    test "returns nil for already-resolved request" do
      state = build_state()

      {entry, new_state} = RequestCorrelator.timeout(state, 42)

      assert entry == nil
      assert new_state.pending_requests == %{}
    end

    test "returns nil for unknown request ID" do
      from = {self(), make_ref()}
      timeout_ref = make_ref()
      start_time = System.monotonic_time(:millisecond)
      state = build_state(%{pending_requests: %{42 => {from, timeout_ref, start_time}}})

      {entry, new_state} = RequestCorrelator.timeout(state, 999)

      assert entry == nil
      # Original request still there
      assert Map.has_key?(new_state.pending_requests, 42)
    end
  end

  describe "pending_count/1" do
    test "returns 0 for empty pending_requests" do
      state = build_state()
      assert RequestCorrelator.pending_count(state) == 0
    end

    test "returns correct count for non-empty pending_requests" do
      now = System.monotonic_time(:millisecond)

      state =
        build_state(%{
          pending_requests: %{
            1 => {{self(), make_ref()}, make_ref(), now},
            2 => {{self(), make_ref()}, make_ref(), now},
            3 => {{self(), make_ref()}, make_ref(), now}
          }
        })

      assert RequestCorrelator.pending_count(state) == 3
    end
  end

  describe "telemetry events" do
    setup do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach("test-correlator-track", [:zen_websocket, :request_correlator, :track], handler, nil)
      :telemetry.attach("test-correlator-resolve", [:zen_websocket, :request_correlator, :resolve], handler, nil)
      :telemetry.attach("test-correlator-timeout", [:zen_websocket, :request_correlator, :timeout], handler, nil)

      on_exit(fn ->
        :telemetry.detach("test-correlator-track")
        :telemetry.detach("test-correlator-resolve")
        :telemetry.detach("test-correlator-timeout")
      end)

      :ok
    end

    test "emits telemetry event on track" do
      state = build_state()
      from = {self(), make_ref()}

      new_state = RequestCorrelator.track(state, 42, from, 5000)

      assert_receive {:telemetry_event, [:zen_websocket, :request_correlator, :track], %{count: 1},
                      %{id: 42, timeout_ms: 5000}}

      # Clean up timer
      {_from, timer_ref, _start_time} = new_state.pending_requests[42]
      Process.cancel_timer(timer_ref)
    end

    test "emits telemetry event on resolve with round_trip_ms" do
      from = {self(), make_ref()}
      timeout_ref = make_ref()
      start_time = System.monotonic_time(:millisecond) - 50
      state = build_state(%{pending_requests: %{42 => {from, timeout_ref, start_time}}})

      RequestCorrelator.resolve(state, 42)

      assert_receive {:telemetry_event, [:zen_websocket, :request_correlator, :resolve],
                      %{count: 1, round_trip_ms: round_trip_ms}, %{id: 42}}

      # round_trip_ms should be approximately 50ms (with some tolerance)
      assert round_trip_ms >= 50
      assert round_trip_ms < 200
    end

    test "does not emit resolve telemetry for unknown ID" do
      state = build_state()

      RequestCorrelator.resolve(state, 999)

      refute_receive {:telemetry_event, [:zen_websocket, :request_correlator, :resolve], _, _}
    end

    test "emits telemetry event on timeout" do
      from = {self(), make_ref()}
      timeout_ref = make_ref()
      start_time = System.monotonic_time(:millisecond)
      state = build_state(%{pending_requests: %{42 => {from, timeout_ref, start_time}}})

      RequestCorrelator.timeout(state, 42)

      assert_receive {:telemetry_event, [:zen_websocket, :request_correlator, :timeout], %{count: 1}, %{id: 42}}
    end

    test "does not emit timeout telemetry for already-resolved request" do
      state = build_state()

      RequestCorrelator.timeout(state, 999)

      refute_receive {:telemetry_event, [:zen_websocket, :request_correlator, :timeout], _, _}
    end
  end

  describe "integration scenarios" do
    test "full track -> resolve cycle" do
      state = build_state()
      from = {self(), make_ref()}

      # Track request
      state = RequestCorrelator.track(state, "req-1", from, 5000)
      assert RequestCorrelator.pending_count(state) == 1

      # Resolve request
      {{resolved_from, _timer_ref, _start_time}, state} = RequestCorrelator.resolve(state, "req-1")
      assert resolved_from == from
      assert RequestCorrelator.pending_count(state) == 0
    end

    test "full track -> timeout cycle" do
      state = build_state()
      from = {self(), make_ref()}

      # Track request with very short timeout
      state = RequestCorrelator.track(state, "req-1", from, 10)
      assert RequestCorrelator.pending_count(state) == 1

      # Wait for timeout message
      assert_receive {:timeout, _timeout_ref, {:correlation_timeout, "req-1"}}, 100

      # Handle timeout
      {{timed_out_from, _timer_ref, _start_time}, state} = RequestCorrelator.timeout(state, "req-1")
      assert timed_out_from == from
      assert RequestCorrelator.pending_count(state) == 0
    end

    test "multiple concurrent requests" do
      state = build_state()
      from1 = {self(), make_ref()}
      from2 = {self(), make_ref()}
      from3 = {self(), make_ref()}

      # Track multiple requests
      state =
        state
        |> RequestCorrelator.track(1, from1, 5000)
        |> RequestCorrelator.track(2, from2, 5000)
        |> RequestCorrelator.track(3, from3, 5000)

      assert RequestCorrelator.pending_count(state) == 3

      # Resolve out of order
      {entry2, state} = RequestCorrelator.resolve(state, 2)
      assert elem(entry2, 0) == from2
      assert RequestCorrelator.pending_count(state) == 2

      {entry1, state} = RequestCorrelator.resolve(state, 1)
      assert elem(entry1, 0) == from1
      assert RequestCorrelator.pending_count(state) == 1

      {entry3, state} = RequestCorrelator.resolve(state, 3)
      assert elem(entry3, 0) == from3
      assert RequestCorrelator.pending_count(state) == 0
    end
  end

  describe "fail_all/2" do
    test "replies {:error, reason} to every pending caller" do
      state = build_state()
      ref1 = make_ref()
      ref2 = make_ref()

      state = RequestCorrelator.track(state, 1, {self(), ref1}, 5_000)
      state = RequestCorrelator.track(state, 2, {self(), ref2}, 5_000)

      new_state = RequestCorrelator.fail_all(state, :disconnected)

      assert_receive {^ref1, {:error, :disconnected}}
      assert_receive {^ref2, {:error, :disconnected}}
      assert new_state.pending_requests == %{}
    end

    test "is a no-op on empty pending_requests" do
      state = build_state()
      assert %{pending_requests: %{}} = RequestCorrelator.fail_all(state, :disconnected)
      refute_receive _, 10
    end

    test "emits :fail_all telemetry per pending request" do
      handler_id = {:fail_all_telemetry, make_ref()}
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:zen_websocket, :request_correlator, :fail_all],
        fn event, measures, meta, _ -> send(test_pid, {:telemetry_event, event, measures, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      state = build_state()
      state = RequestCorrelator.track(state, 1, {self(), make_ref()}, 5_000)
      state = RequestCorrelator.track(state, 2, {self(), make_ref()}, 5_000)

      RequestCorrelator.fail_all(state, :disconnected)

      assert_receive {:telemetry_event, [:zen_websocket, :request_correlator, :fail_all], %{count: 1},
                      %{id: 1, reason: :disconnected}}

      assert_receive {:telemetry_event, [:zen_websocket, :request_correlator, :fail_all], %{count: 1},
                      %{id: 2, reason: :disconnected}}
    end
  end

  describe "concurrent timeout cleanup" do
    test "all pending requests are cleaned up when N concurrent timeouts fire" do
      n = 10
      timeout_ms = 30

      state =
        Enum.reduce(1..n, build_state(), fn id, acc ->
          RequestCorrelator.track(acc, id, {self(), make_ref()}, timeout_ms)
        end)

      assert RequestCorrelator.pending_count(state) == n

      telemetry_ref = :atomics.new(1, [])
      handler_id = {:concurrent_timeout_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:zen_websocket, :request_correlator, :timeout],
        fn _event, _measures, _meta, _config -> :atomics.add(telemetry_ref, 1, 1) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      for id <- 1..n do
        assert_receive {:timeout, _timeout_ref, {:correlation_timeout, ^id}}, 500
      end

      final_state =
        Enum.reduce(1..n, state, fn id, acc ->
          {entry, next} = RequestCorrelator.timeout(acc, id)
          assert entry
          next
        end)

      assert final_state.pending_requests == %{}
      assert RequestCorrelator.pending_count(final_state) == 0
      assert :atomics.get(telemetry_ref, 1) == n
    end

    test "timeout on an already-resolved request is a no-op" do
      state = build_state()
      state = RequestCorrelator.track(state, 1, {self(), make_ref()}, 5_000)
      {entry, state} = RequestCorrelator.resolve(state, 1)
      assert entry

      # Simulate timeout message arriving after resolution — no double-resolution
      {nil, state} = RequestCorrelator.timeout(state, 1)
      assert RequestCorrelator.pending_count(state) == 0
    end
  end
end
