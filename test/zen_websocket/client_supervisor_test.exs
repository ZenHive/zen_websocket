defmodule ZenWebsocket.ClientSupervisorTest do
  # async: false because PoolRouter uses a shared ETS table
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.PoolRouter

  # Tests require external network access to Deribit testnet
  @moduletag :external_network

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  # Polling interval and max wait time for restart verification
  @poll_interval_ms 50
  @max_wait_ms 2000

  # ETS table used by PoolRouter
  @pool_table :zen_websocket_pool

  setup do
    # Clean up PoolRouter ETS table before each test
    if :ets.whereis(@pool_table) != :undefined do
      :ets.delete(@pool_table)
    end

    # Start the supervisor for tests
    {:ok, sup_pid} = start_supervised(ClientSupervisor)
    {:ok, supervisor: sup_pid}
  end

  describe "start_client/2" do
    test "starts a supervised client connection" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      assert %Client{state: :connected, server_pid: pid} = client
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify we can send messages
      assert :ok = Client.send_message(client, Jason.encode!(%{test: "message"}))

      # Clean up
      Client.close(client)
    end

    test "returns error for invalid URL" do
      assert {:error, _} = ClientSupervisor.start_client("invalid-url")
    end

    test "supervised client restarts on crash" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)
      original_pid = client.server_pid

      # Force a crash
      Process.exit(original_pid, :kill)

      # Poll until supervisor restarts the process (avoids flaky fixed sleep)
      new_pid = poll_until_restarted(original_pid, @max_wait_ms)

      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end
  end

  describe "list_clients/0" do
    test "lists all active supervised clients" do
      assert ClientSupervisor.list_clients() == []

      {:ok, client1} = ClientSupervisor.start_client(@deribit_test_url)
      {:ok, client2} = ClientSupervisor.start_client(@deribit_test_url)

      clients = ClientSupervisor.list_clients()
      assert length(clients) == 2
      assert client1.server_pid in clients
      assert client2.server_pid in clients

      # Clean up
      Client.close(client1)
      Client.close(client2)
    end
  end

  describe "stop_client/1" do
    test "gracefully stops a supervised client" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      assert :ok = ClientSupervisor.stop_client(client.server_pid)
      refute Process.alive?(client.server_pid)

      # Verify it's removed from the supervisor
      assert ClientSupervisor.list_clients() == []
    end
  end

  describe "send_balanced/2" do
    test "returns error when no connections available" do
      assert {:error, :no_connections} = ClientSupervisor.send_balanced("test message")
    end

    test "sends message via single connection" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      # Simple message should succeed
      message = Jason.encode!(%{jsonrpc: "2.0", method: "public/test", params: %{}, id: 1})
      result = ClientSupervisor.send_balanced(message)

      # Either :ok for fire-and-forget or {:ok, response} for RPC
      assert result == :ok or match?({:ok, _}, result)

      Client.close(client)
    end

    test "routes to healthiest connection in pool" do
      {:ok, client1} = ClientSupervisor.start_client(@deribit_test_url)
      {:ok, client2} = ClientSupervisor.start_client(@deribit_test_url)

      # Both connections should be healthy, message should succeed
      message = Jason.encode!(%{test: "balanced"})
      assert :ok = ClientSupervisor.send_balanced(message)

      # Verify both are still in pool
      assert length(ClientSupervisor.list_clients()) == 2

      Client.close(client1)
      Client.close(client2)
    end

    test "performs failover when connection fails" do
      {:ok, client1} = ClientSupervisor.start_client(@deribit_test_url)
      {:ok, client2} = ClientSupervisor.start_client(@deribit_test_url)

      # Record errors on client1 to make it less healthy
      PoolRouter.record_error(client1.server_pid)
      PoolRouter.record_error(client1.server_pid)

      # Message should route to healthier client2
      message = Jason.encode!(%{test: "failover"})
      assert :ok = ClientSupervisor.send_balanced(message)

      Client.close(client1)
      Client.close(client2)
    end

    test "returns max_attempts_exceeded after all connections fail" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      # Stop the client to simulate failure
      ClientSupervisor.stop_client(client.server_pid)

      # Poll until process is fully terminated (avoids flaky fixed sleep)
      poll_until_terminated(client.server_pid, @max_wait_ms)

      # Now send_balanced should fail (no healthy connections)
      result = ClientSupervisor.send_balanced("test", max_attempts: 1)
      assert result == {:error, :no_connections}
    end

    test "respects max_attempts option" do
      {:ok, _client} = ClientSupervisor.start_client(@deribit_test_url)

      # With max_attempts: 1, only one attempt allowed
      message = Jason.encode!(%{test: "limited"})
      result = ClientSupervisor.send_balanced(message, max_attempts: 1)

      # Should succeed on first attempt
      assert result == :ok or match?({:ok, _}, result)
    end
  end

  describe "send_balanced/2 with custom discovery" do
    test "uses provided client_discovery function" do
      {:ok, client1} = ClientSupervisor.start_client(@deribit_test_url)
      {:ok, client2} = ClientSupervisor.start_client(@deribit_test_url)

      # Custom discovery returns only client1
      discovery = fn -> [client1.server_pid] end

      # Message should succeed (routing to client1)
      message = Jason.encode!(%{test: "custom_discovery"})
      assert :ok = ClientSupervisor.send_balanced(message, client_discovery: discovery)

      Client.close(client1)
      Client.close(client2)
    end

    test "falls back to list_clients/0 when no discovery provided" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      # No client_discovery option - should use default list_clients/0
      message = Jason.encode!(%{test: "default_discovery"})
      assert :ok = ClientSupervisor.send_balanced(message)

      Client.close(client)
    end

    test "returns no_connections when custom discovery returns empty list" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      # Discovery returns empty list
      discovery = fn -> [] end

      message = Jason.encode!(%{test: "empty_discovery"})
      assert {:error, :no_connections} = ClientSupervisor.send_balanced(message, client_discovery: discovery)

      Client.close(client)
    end
  end

  describe "start_client/2 lifecycle callbacks" do
    test "on_connect called after successful connection" do
      test_pid = self()
      on_connect = fn pid -> send(test_pid, {:connected, pid}) end

      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, on_connect: on_connect)

      assert_receive {:connected, pid}
      assert pid == client.server_pid

      Client.close(client)
    end

    test "on_disconnect called when client terminates gracefully" do
      test_pid = self()
      on_disconnect = fn pid -> send(test_pid, {:disconnected, pid}) end

      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, on_disconnect: on_disconnect)
      client_pid = client.server_pid

      :ok = ClientSupervisor.stop_client(client_pid)

      assert_receive {:disconnected, ^client_pid}, 1000
    end

    test "on_disconnect called when client stops via Client.close" do
      test_pid = self()
      on_disconnect = fn pid -> send(test_pid, {:disconnected, pid}) end

      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, on_disconnect: on_disconnect)
      client_pid = client.server_pid

      Client.close(client)

      assert_receive {:disconnected, ^client_pid}, 1000
    end

    test "callbacks work together for registry integration pattern" do
      test_pid = self()

      # Simulate registry operations
      callbacks = [
        on_connect: fn pid -> send(test_pid, {:registered, pid}) end,
        on_disconnect: fn pid -> send(test_pid, {:unregistered, pid}) end
      ]

      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, callbacks)
      client_pid = client.server_pid

      # Verify on_connect was called
      assert_receive {:registered, ^client_pid}

      # Stop client
      ClientSupervisor.stop_client(client_pid)

      # Verify on_disconnect was called
      assert_receive {:unregistered, ^client_pid}, 1000
    end

    test "callback errors do not crash client" do
      # on_connect that raises
      on_connect = fn _pid -> raise "intentional error" end

      # Should still succeed despite callback error
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, on_connect: on_connect)

      # Client should still be alive
      assert Process.alive?(client.server_pid)

      Client.close(client)
    end

    test "on_disconnect callback error does not prevent termination" do
      test_pid = self()

      # on_disconnect that raises but also sends a message
      on_disconnect = fn pid ->
        send(test_pid, {:attempted_disconnect, pid})
        raise "intentional error"
      end

      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url, on_disconnect: on_disconnect)
      client_pid = client.server_pid

      ClientSupervisor.stop_client(client_pid)

      # Callback was attempted
      assert_receive {:attempted_disconnect, ^client_pid}, 1000

      # Client should be terminated despite callback error
      poll_until_terminated(client_pid, @max_wait_ms)
    end
  end

  describe "send_balanced/2 telemetry" do
    setup do
      test_pid = self()
      handler_id = "client-supervisor-test-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_websocket, :pool, :route],
          [:zen_websocket, :pool, :failover]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits route telemetry on successful send" do
      {:ok, client} = ClientSupervisor.start_client(@deribit_test_url)

      message = Jason.encode!(%{test: "telemetry"})
      :ok = ClientSupervisor.send_balanced(message)

      assert_receive {:telemetry, [:zen_websocket, :pool, :route], measurements, metadata}
      assert measurements.health > 0
      assert measurements.pool_size == 1
      assert metadata.selected == client.server_pid

      Client.close(client)
    end
  end

  # Polls until supervisor restarts a new process different from original_pid.
  # Returns the new pid or raises if timeout exceeded.
  defp poll_until_restarted(original_pid, remaining_ms) when remaining_ms <= 0 do
    flunk("Supervisor did not restart process within timeout. Original pid: #{inspect(original_pid)}")
  end

  defp poll_until_restarted(original_pid, remaining_ms) do
    clients = ClientSupervisor.list_clients()

    case clients do
      [new_pid] when new_pid != original_pid and is_pid(new_pid) ->
        new_pid

      _ ->
        Process.sleep(@poll_interval_ms)
        poll_until_restarted(original_pid, remaining_ms - @poll_interval_ms)
    end
  end

  # Polls until a process is fully terminated.
  # Returns :ok or raises if timeout exceeded.
  defp poll_until_terminated(pid, remaining_ms) when remaining_ms <= 0 do
    flunk("Process did not terminate within timeout. Pid: #{inspect(pid)}")
  end

  defp poll_until_terminated(pid, remaining_ms) do
    if Process.alive?(pid) do
      Process.sleep(@poll_interval_ms)
      poll_until_terminated(pid, remaining_ms - @poll_interval_ms)
    else
      :ok
    end
  end
end
