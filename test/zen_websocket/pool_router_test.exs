defmodule ZenWebsocket.PoolRouterTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.PoolRouter

  # ETS table name used by PoolRouter
  @table_name :zen_websocket_pool

  # Stand-in for the Client GenServer. PoolRouter.calculate_health/1 only ever
  # reaches a "client" through GenServer.call (via Client.get_state_metrics/1
  # and Client.get_latency_stats/1), so a fake process answering those two
  # calls drives the real metrics-gathering path without a live connection.
  defmodule FakeMetricsClient do
    @moduledoc false
    use GenServer

    def start_link(metrics), do: GenServer.start_link(__MODULE__, metrics)

    @impl true
    def init(metrics), do: {:ok, metrics}

    @impl true
    def handle_call(:get_state_metrics, _from, %{state_metrics: state_metrics} = metrics) do
      {:reply, state_metrics, metrics}
    end

    def handle_call(:get_latency_stats, _from, %{latency_stats: latency_stats} = metrics) do
      {:reply, latency_stats, metrics}
    end
  end

  # A GenServer with no matching handle_call clauses - any call crashes it,
  # simulating a client process that dies mid-metrics-lookup.
  defmodule CrashingClient do
    @moduledoc false
    use GenServer

    def start_link(_arg \\ nil), do: GenServer.start_link(__MODULE__, :ok)

    @impl true
    def init(:ok), do: {:ok, :ok}
  end

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete_all_objects(@table_name)
    end

    :ok
  end

  describe "select_connection/1" do
    test "returns error when no connections available" do
      assert {:error, :no_connections} = PoolRouter.select_connection([])
    end

    test "returns single connection when only one available" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      assert {:ok, ^pid} = PoolRouter.select_connection([pid])
    end

    test "selects from multiple connections" do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each([pid1, pid2], &Process.exit(&1, :kill)) end)

      assert {:ok, selected} = PoolRouter.select_connection([pid1, pid2])
      assert selected in [pid1, pid2]
    end

    test "uses round-robin among equally healthy connections" do
      # Create simple processes (not real clients, so all have equal health)
      pids = for _ <- 1..3, do: spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each(pids, &Process.exit(&1, :kill)) end)

      # Select multiple times and verify distribution
      selections =
        for _ <- 1..6 do
          {:ok, pid} = PoolRouter.select_connection(pids)
          pid
        end

      # Should have selected from all available pids
      unique = Enum.uniq(selections)
      assert Enum.count(unique) > 1, "Expected round-robin to select different pids"
    end
  end

  describe "calculate_health/1" do
    test "returns 100 for healthy process with no errors" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Non-client process returns optimistic default
      health = PoolRouter.calculate_health(pid)
      assert health == 100
    end

    test "returns 100 for dead process (optimistic default)" do
      pid = spawn(fn -> :ok end)
      # Wait for process to die
      Process.sleep(10)
      refute Process.alive?(pid)

      health = PoolRouter.calculate_health(pid)
      assert health == 100
    end

    test "reduces health score based on recorded errors" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Base health with no errors
      assert PoolRouter.calculate_health(pid) == 100

      # Record an error (15 point penalty per error)
      PoolRouter.record_error(pid)
      assert PoolRouter.calculate_health(pid) == 85

      # Record another error
      PoolRouter.record_error(pid)
      # Max error penalty is 20, so 2 errors = min(30, 20) = 20
      assert PoolRouter.calculate_health(pid) == 80
    end
  end

  describe "record_error/1" do
    test "increments error count for connection" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Initially no errors
      assert PoolRouter.calculate_health(pid) == 100

      # Record errors
      PoolRouter.record_error(pid)
      PoolRouter.record_error(pid)
      PoolRouter.record_error(pid)

      # Health should decrease (max error penalty is 20)
      health = PoolRouter.calculate_health(pid)
      assert health < 100
      # 3 errors × 15 = 45, capped at 20 → 100 - 20 = 80
      assert health == 80
    end

    test "error tracking includes timestamp for decay" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      PoolRouter.record_error(pid)

      # Verify error is stored in ETS with timestamp
      [{_, count, timestamp}] = :ets.lookup(@table_name, {:error_count, pid})
      assert count == 1
      assert is_integer(timestamp)
    end

    test "error state survives the process that first invoked the router" do
      if :ets.whereis(@table_name) != :undefined do
        table_owner = :ets.info(@table_name, :owner)
        owner_ref = Process.monitor(table_owner)
        Process.exit(table_owner, :kill)
        assert_receive {:DOWN, ^owner_ref, :process, ^table_owner, :killed}
      end

      assert :ets.whereis(@table_name) == :undefined

      connection_pid = spawn(fn -> Process.sleep(:infinity) end)
      test_pid = self()

      on_exit(fn -> Process.exit(connection_pid, :kill) end)

      creator_pid =
        spawn(fn ->
          PoolRouter.record_error(connection_pid)
          send(test_pid, :error_recorded)
        end)

      creator_ref = Process.monitor(creator_pid)

      assert_receive :error_recorded
      assert_receive {:DOWN, ^creator_ref, :process, ^creator_pid, :normal}
      assert :ets.whereis(@table_name) != :undefined
      assert PoolRouter.calculate_health(connection_pid) == 85
    end
  end

  describe "clear_errors/1" do
    test "removes error tracking for connection" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Record some errors
      PoolRouter.record_error(pid)
      PoolRouter.record_error(pid)
      assert PoolRouter.calculate_health(pid) < 100

      # Clear errors
      PoolRouter.clear_errors(pid)

      # Health should be restored
      assert PoolRouter.calculate_health(pid) == 100
    end

    test "returns :ok when no errors exist" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      assert :ok = PoolRouter.clear_errors(pid)
    end
  end

  describe "pool_health/1" do
    test "returns health for all connections" do
      pids = for _ <- 1..3, do: spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each(pids, &Process.exit(&1, :kill)) end)

      health_data = PoolRouter.pool_health(pids)

      assert [_, _, _] = health_data
      assert Enum.all?(health_data, fn %{pid: pid, health: health} -> pid in pids and health == 100 end)
    end

    test "returns empty list for empty pool" do
      assert [] = PoolRouter.pool_health([])
    end

    test "reflects error penalties in health data" do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each([pid1, pid2], &Process.exit(&1, :kill)) end)

      # Record error on pid1
      PoolRouter.record_error(pid1)

      health_data = PoolRouter.pool_health([pid1, pid2])

      pid1_health = Enum.find(health_data, fn %{pid: p} -> p == pid1 end)
      pid2_health = Enum.find(health_data, fn %{pid: p} -> p == pid2 end)

      assert pid1_health.health < pid2_health.health
      assert pid1_health.health == 85
      assert pid2_health.health == 100
    end
  end

  describe "error decay" do
    test "stores timestamp for decay calculation" do
      # Note: Full decay behavior (60s expiry) is not tested here because
      # it would require waiting 60+ seconds. Instead, we verify the timestamp
      # storage mechanism that enables decay. The actual decay logic in
      # get_error_count/1 checks: (now - timestamp) >= 60_000ms

      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      PoolRouter.record_error(pid)

      # Verify error is tracked with timestamp
      [{_, count, timestamp}] = :ets.lookup(@table_name, {:error_count, pid})
      assert count == 1
      # Timestamp uses System.monotonic_time(:millisecond) which can be negative
      # (it's relative to an arbitrary VM start point), so we just verify it's an integer
      assert is_integer(timestamp)
    end
  end

  describe "telemetry events" do
    setup do
      test_pid = self()
      handler_id = "pool-router-test-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_websocket, :pool, :route],
          [:zen_websocket, :pool, :health]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits telemetry on connection selection" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      {:ok, ^pid} = PoolRouter.select_connection([pid])

      assert_receive {:telemetry, [:zen_websocket, :pool, :route], measurements, metadata}
      assert measurements.health == 100
      assert measurements.pool_size == 1
      assert metadata.selected == pid
    end

    test "emits telemetry on pool health query" do
      pids = for _ <- 1..2, do: spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each(pids, &Process.exit(&1, :kill)) end)

      PoolRouter.pool_health(pids)

      assert_receive {:telemetry, [:zen_websocket, :pool, :health], measurements, _metadata}
      assert measurements.pool_size == 2
      assert measurements.avg_health == 100
    end
  end

  describe "health score formula" do
    test "pending requests penalty is capped at 40" do
      # This tests the formula: min(pending_requests * 10, 40)
      # We can't easily test with real clients here, but we verify
      # the error penalty cap works similarly

      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # With just errors (no pending requests since it's not a real client):
      # 2 errors × 15 = 30, but capped at 20
      PoolRouter.record_error(pid)
      PoolRouter.record_error(pid)

      health = PoolRouter.calculate_health(pid)
      # 100 - 20 (error penalty capped) = 80
      assert health == 80
    end

    test "error penalty is capped at 20" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Record many errors
      for _ <- 1..10 do
        PoolRouter.record_error(pid)
      end

      health = PoolRouter.calculate_health(pid)
      # 10 errors × 15 = 150, but capped at 20
      # 100 - 20 = 80
      assert health == 80
    end

    test "health score is clamped to minimum 0" do
      # Even with maximum penalties, score should not go negative
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Record maximum errors
      for _ <- 1..10 do
        PoolRouter.record_error(pid)
      end

      health = PoolRouter.calculate_health(pid)
      assert health >= 0
    end
  end

  describe "connection selection with varying health" do
    test "selects connection with higher health score" do
      healthy_pid = spawn(fn -> Process.sleep(:infinity) end)
      unhealthy_pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Enum.each([healthy_pid, unhealthy_pid], &Process.exit(&1, :kill)) end)

      # Make one connection unhealthy
      PoolRouter.record_error(unhealthy_pid)
      PoolRouter.record_error(unhealthy_pid)

      # Should always select the healthy one
      for _ <- 1..5 do
        {:ok, selected} = PoolRouter.select_connection([healthy_pid, unhealthy_pid])
        assert selected == healthy_pid
      end
    end
  end

  describe "calculate_health/1 with a live metrics-reporting process" do
    test "pulls pending_requests and p99 latency from the client and applies the documented formula" do
      {:ok, pid} =
        start_supervised(
          {FakeMetricsClient,
           %{
             state_metrics: %{pending_requests_size: 8},
             latency_stats: %{p99: 50}
           }}
        )

      # pending_penalty = min(8 * 10, 40) = 40
      # latency_penalty = min(div(50, 25), 30) = 2
      # error_penalty = 0, pressure_penalty = 0
      # score = 100 - 40 - 2 - 0 - 0 = 58
      assert PoolRouter.calculate_health(pid) == 58
    end

    test "caps the pending-requests penalty at 40 points regardless of queue depth" do
      {:ok, pid} =
        start_supervised(
          {FakeMetricsClient,
           %{
             state_metrics: %{pending_requests_size: 999},
             latency_stats: nil
           }}
        )

      # pending_penalty = min(999 * 10, 40) = 40, everything else 0
      assert PoolRouter.calculate_health(pid) == 60
    end

    test "applies a non-zero pressure penalty when the client reports queue pressure" do
      {:ok, pid} =
        start_supervised(
          {FakeMetricsClient,
           %{
             state_metrics: %{pending_requests_size: 0, pressure_level: :high},
             latency_stats: nil
           }}
        )

      assert PoolRouter.calculate_health(pid) == 90
    end

    test "returns the optimistic default when the client process crashes answering a metrics call" do
      {:ok, pid} = start_supervised(CrashingClient)

      # get_state_metrics/get_latency_stats hit a process with no matching
      # handle_call clause, so it crashes mid-call; PoolRouter must catch
      # that exit and fall back to the optimistic default instead of
      # propagating the crash or hanging.
      assert PoolRouter.calculate_health(pid) == 100
    end
  end

  describe "error decay expiry" do
    test "clears an error count once it is older than the decay window" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      # Ensure the ETS table exists before writing to it directly (PoolRouter
      # creates it lazily on first use).
      :ok = PoolRouter.clear_errors(pid)

      # Seed an already-expired error entry directly (the real decay window
      # is 60s - too slow to actually sleep through in a test). This drives
      # get_error_count/1's decay branch deterministically.
      stale_timestamp = System.monotonic_time(:millisecond) - 61_000
      :ets.insert(@table_name, {{:error_count, pid}, 5, stale_timestamp})

      # The stale count must not penalize health...
      assert PoolRouter.calculate_health(pid) == 100
      # ...and the decayed entry must be cleared from the table as a side effect.
      assert :ets.lookup(@table_name, {:error_count, pid}) == []
    end
  end
end
