defmodule ZenWebsocket.ClientSupervisorSendBalancedTest do
  @moduledoc """
  Unit-level coverage for `ClientSupervisor.send_balanced/2` and
  `stop_client/1` that does not require a live WebSocket connection.

  `client_supervisor_test.exs` covers the same functions end-to-end against a
  real Deribit testnet connection (tagged `:external_network`), but that
  leaves the failover/load-balancing logic itself - which only ever talks to
  its candidates through `GenServer.call/2` - entirely untested outside a
  live network run. A local GenServer standing in for those three calls is
  the fenced exception in CLAUDE.md → Real API Testing Policy → Narrow
  exceptions → ClientSupervisor routing stand-in.
  """
  # async: false: PoolRouter uses a shared ETS table and ClientSupervisor is
  # a globally named process, same as client_supervisor_test.exs.
  use ExUnit.Case, async: false

  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.PoolRouter

  @pool_table :zen_websocket_pool

  # Minimal stand-in for the Client GenServer. ClientSupervisor.send_balanced/2
  # only ever reaches a "client" through GenServer.call (via
  # ZenWebsocket.Client.send_message/get_state_metrics/get_latency_stats, all
  # of which call through `server_pid` when it's a pid), so a fake process
  # answering those three calls is enough to drive the failover/load-balancing
  # logic without a real Gun/WebSocket connection.
  defmodule FakeClient do
    @moduledoc false
    use GenServer

    def start_link(reply), do: GenServer.start_link(__MODULE__, reply)

    @impl true
    def init(reply), do: {:ok, reply}

    @impl true
    def handle_call({:send_message, _message}, _from, reply) do
      {:reply, reply, reply}
    end

    def handle_call(:get_state_metrics, _from, reply) do
      {:reply, %{pending_requests_size: 0}, reply}
    end

    def handle_call(:get_latency_stats, _from, reply) do
      {:reply, nil, reply}
    end
  end

  defp start_fake_client(reply) do
    child_spec = %{id: make_ref(), start: {FakeClient, :start_link, [reply]}, restart: :temporary}
    start_supervised!(child_spec)
  end

  setup do
    if :ets.whereis(@pool_table) != :undefined do
      :ets.delete_all_objects(@pool_table)
    end

    {:ok, sup_pid} = start_supervised(ClientSupervisor)
    {:ok, supervisor: sup_pid}
  end

  describe "send_balanced/2 (fake clients, no live connection)" do
    test "returns error immediately when discovery yields no connections" do
      assert {:error, :no_connections} =
               ClientSupervisor.send_balanced("msg", client_discovery: fn -> [] end)
    end

    test "defaults opts to [] and falls back to list_clients/0 when called with one argument" do
      # Calling with arity 1 exercises the `opts \\ []` default clause; with
      # no supervised clients started, the default list_clients/0 discovery
      # returns [] and this must behave identically to passing opts: [].
      assert {:error, :no_connections} = ClientSupervisor.send_balanced("msg")
    end

    test "sends via the only candidate and returns :ok on a fire-and-forget reply" do
      pid = start_fake_client(:ok)

      assert :ok = ClientSupervisor.send_balanced("msg", client_discovery: fn -> [pid] end)
    end

    test "returns {:ok, response} for RPC-style replies" do
      pid = start_fake_client({:ok, %{"result" => 42}})

      assert {:ok, %{"result" => 42}} =
               ClientSupervisor.send_balanced("msg", client_discovery: fn -> [pid] end)
    end

    test "fails over to the next healthy connection after an error" do
      bad_pid = start_fake_client({:error, :boom})
      good_pid = start_fake_client(:ok)

      # Both candidates start at equal (100) health. Bias selection so
      # bad_pid is tried first deterministically, instead of depending on
      # PoolRouter's round-robin tie-break order.
      PoolRouter.record_error(good_pid)

      assert :ok =
               ClientSupervisor.send_balanced("msg",
                 client_discovery: fn -> [bad_pid, good_pid] end,
                 max_attempts: 3
               )
    end

    test "stops after max_attempts and returns :max_attempts_exceeded without exhausting every candidate" do
      pid1 = start_fake_client({:error, :down})
      pid2 = start_fake_client({:error, :down})

      assert {:error, :max_attempts_exceeded} =
               ClientSupervisor.send_balanced("msg",
                 client_discovery: fn -> [pid1, pid2] end,
                 max_attempts: 1
               )
    end

    test "returns the last error once every candidate has been tried" do
      pid = start_fake_client({:error, :unreachable})

      assert {:error, :unreachable} =
               ClientSupervisor.send_balanced("msg",
                 client_discovery: fn -> [pid] end,
                 max_attempts: 5
               )
    end

    test "emits failover telemetry when a candidate errors" do
      test_pid = self()
      handler_id = "client-supervisor-failover-test-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:zen_websocket, :pool, :failover],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      bad_pid = start_fake_client({:error, :boom})
      good_pid = start_fake_client(:ok)
      PoolRouter.record_error(good_pid)

      assert :ok =
               ClientSupervisor.send_balanced("msg",
                 client_discovery: fn -> [bad_pid, good_pid] end,
                 max_attempts: 3
               )

      assert_receive {:telemetry, [:zen_websocket, :pool, :failover], %{attempt: 1}, metadata}
      assert metadata.failed_pid == bad_pid
      assert metadata.reason == :boom
    end
  end

  describe "stop_client/1" do
    test "returns {:error, :not_found} for a pid the supervisor never started" do
      stray_pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(stray_pid, :kill) end)

      assert {:error, :not_found} = ClientSupervisor.stop_client(stray_pid)
    end
  end
end
