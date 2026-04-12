defmodule ZenWebsocket.ClientReconnectTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.Test.Support.MockWebSockServer

  # Maximum time to wait for client to reconnect after server restart
  @reconnect_poll_timeout_ms 3_000
  @reconnect_poll_interval_ms 100

  # Waits for client to reach :connected state by polling
  defp wait_for_reconnect(client) do
    polls = div(@reconnect_poll_timeout_ms, @reconnect_poll_interval_ms)

    Enum.reduce_while(1..polls, false, fn _, _acc ->
      Process.sleep(@reconnect_poll_interval_ms)

      if Client.get_state(client) == :connected do
        {:halt, true}
      else
        {:cont, false}
      end
    end)
  end

  defp get_internal_state(client) do
    {:ok, state} = GenServer.call(client.server_pid, :get_state_internal)
    state
  end

  # Disconnects by stopping server, waits for detection, restarts on same port
  defp disconnect_and_reconnect(client, server, port, handler) do
    MockWebSockServer.stop(server)

    # Allow time for Gun to detect TCP close
    Process.sleep(300)
    assert Process.alive?(client.server_pid), "Client GenServer crashed instead of reconnecting"

    {:ok, new_server, ^port} = MockWebSockServer.start_link(port: port)
    MockWebSockServer.set_handler(new_server, handler)

    assert wait_for_reconnect(client), "Client did not reconnect within #{@reconnect_poll_timeout_ms}ms"

    new_server
  end

  describe "config preservation across reconnect" do
    setup do
      echo_handler = fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end

      {:ok, server, port} = MockWebSockServer.start_link()
      MockWebSockServer.set_handler(server, echo_handler)

      mock_url = "ws://localhost:#{port}/ws"

      on_exit(fn ->
        # Server may already be stopped by test
        try do
          MockWebSockServer.stop(server)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, server: server, port: port, mock_url: mock_url, echo_handler: echo_handler}
    end

    test "retry_count resets after successful reconnect", %{
      server: server,
      port: port,
      mock_url: mock_url,
      echo_handler: handler
    } do
      # Connect with low retry_count — if retry_count doesn't reset,
      # the second disconnect cycle will exhaust retries and crash
      {:ok, client} = Client.connect(mock_url, retry_count: 3, retry_delay: 100)
      assert Client.get_state(client) == :connected

      # First disconnect-reconnect cycle
      server2 = disconnect_and_reconnect(client, server, port, handler)

      # Verify echo works after first reconnect
      assert :ok = Client.send_message(client, "after-first-reconnect")
      assert_receive {:websocket_message, "after-first-reconnect"}, 2_000

      # Second disconnect-reconnect cycle — would fail if retry_count wasn't reset
      server3 = disconnect_and_reconnect(client, server2, port, handler)

      # Verify echo works after second reconnect
      assert :ok = Client.send_message(client, "after-second-reconnect")
      assert_receive {:websocket_message, "after-second-reconnect"}, 2_000

      Client.close(client)
      MockWebSockServer.stop(server3)
    end

    test "handler callback preserved after reconnect", %{
      server: server,
      port: port,
      mock_url: mock_url,
      echo_handler: handler
    } do
      test_pid = self()

      # Custom handler that tags messages with a unique marker
      custom_handler = fn msg -> send(test_pid, {:custom_handler, msg}) end

      {:ok, client} = Client.connect(mock_url, handler: custom_handler, retry_count: 5, retry_delay: 100)
      assert Client.get_state(client) == :connected

      # Verify handler works before disconnect
      assert :ok = Client.send_message(client, "before-disconnect")
      assert_receive {:custom_handler, {:message, "before-disconnect"}}, 2_000

      # Disconnect and reconnect
      server2 = disconnect_and_reconnect(client, server, port, handler)

      # Verify the SAME custom handler receives messages after reconnect
      assert :ok = Client.send_message(client, "after-reconnect")
      assert_receive {:custom_handler, {:message, "after-reconnect"}}, 2_000

      Client.close(client)
      MockWebSockServer.stop(server2)
    end

    test "config struct preserved after reconnect", %{
      server: server,
      port: port,
      mock_url: mock_url,
      echo_handler: handler
    } do
      custom_timeout = 8_000
      custom_retry_delay = 200

      {:ok, client} =
        Client.connect(mock_url,
          timeout: custom_timeout,
          retry_delay: custom_retry_delay,
          retry_count: 5
        )

      assert Client.get_state(client) == :connected

      # Capture config before disconnect
      state_before = get_internal_state(client)
      config_before = state_before.config

      # Disconnect and reconnect
      server2 = disconnect_and_reconnect(client, server, port, handler)

      # Verify config is identical after reconnect
      state_after = get_internal_state(client)
      config_after = state_after.config

      assert config_after.timeout == custom_timeout
      assert config_after.retry_delay == custom_retry_delay
      assert config_after.url == mock_url
      assert config_after == config_before

      # Verify retry_count was reset
      assert state_after.retry_count == 0

      Client.close(client)
      MockWebSockServer.stop(server2)
    end

    test "explicit reconnect preserves config and runtime callbacks", %{mock_url: mock_url} do
      test_pid = self()
      heartbeat_config = %{type: :ping_pong, interval: 10_000}
      on_disconnect = fn pid -> send(test_pid, {:disconnect_callback, pid}) end

      custom_handler = fn
        {:message, data} -> send(test_pid, {:explicit_reconnect_handler, data})
        _other -> :ok
      end

      {:ok, client} =
        Client.connect(mock_url,
          headers: [{"x-test-header", "keep-me"}],
          timeout: 8_000,
          retry_count: 5,
          retry_delay: 200,
          request_timeout: 9_000,
          handler: custom_handler,
          heartbeat_config: heartbeat_config,
          on_disconnect: on_disconnect
        )

      state_before = get_internal_state(client)

      {:ok, new_client} = Client.reconnect(client)

      assert_receive {:disconnect_callback, old_pid}, 2_000
      assert old_pid == client.server_pid

      state_after = get_internal_state(new_client)

      refute new_client.server_pid == client.server_pid
      assert state_after.config == state_before.config
      assert state_after.heartbeat_config == heartbeat_config
      assert state_after.heartbeat_timer

      assert :ok = Client.send_message(new_client, "after-explicit-reconnect")
      assert_receive {:explicit_reconnect_handler, "after-explicit-reconnect"}, 2_000

      Client.close(new_client)

      assert_receive {:disconnect_callback, new_pid}, 2_000
      assert new_pid == new_client.server_pid
    end

    test "explicit reconnect after close preserves stored contract", %{mock_url: mock_url} do
      test_pid = self()

      custom_handler = fn
        {:message, data} -> send(test_pid, {:closed_client_reconnect_handler, data})
        _other -> :ok
      end

      {:ok, client} =
        Client.connect(mock_url,
          headers: [{"x-reconnect", "after-close"}],
          timeout: 9_000,
          retry_delay: 250,
          handler: custom_handler
        )

      state_before = get_internal_state(client)

      Client.close(client)

      {:ok, new_client} = Client.reconnect(client)
      state_after = get_internal_state(new_client)

      assert state_after.config == state_before.config
      assert :ok = Client.send_message(new_client, "after-closed-client-reconnect")
      assert_receive {:closed_client_reconnect_handler, "after-closed-client-reconnect"}, 2_000

      Client.close(new_client)
    end

    test "explicit reconnect keeps supervised clients under ClientSupervisor", %{mock_url: mock_url} do
      test_pid = self()

      start_supervised!({ClientSupervisor, []})

      custom_handler = fn
        {:message, data} -> send(test_pid, {:supervised_reconnect_handler, data})
        _other -> :ok
      end

      {:ok, client} =
        ClientSupervisor.start_client(mock_url,
          timeout: 8_000,
          handler: custom_handler,
          on_connect: fn pid -> send(test_pid, {:connected, pid}) end,
          on_disconnect: fn pid -> send(test_pid, {:disconnected, pid}) end
        )

      assert_receive {:connected, original_pid}, 2_000
      assert original_pid == client.server_pid
      assert original_pid in ClientSupervisor.list_clients()

      {:ok, new_client} = Client.reconnect(client)

      assert_receive {:disconnected, ^original_pid}, 2_000
      assert_receive {:connected, new_pid}, 2_000

      refute new_pid == original_pid
      assert new_pid == new_client.server_pid
      assert new_pid in ClientSupervisor.list_clients()
      refute original_pid in ClientSupervisor.list_clients()

      assert :ok = Client.send_message(new_client, "after-supervised-reconnect")
      assert_receive {:supervised_reconnect_handler, "after-supervised-reconnect"}, 2_000

      Client.close(new_client)

      assert_receive {:disconnected, ^new_pid}, 2_000
    end
  end

  describe "reconnect_on_error configuration" do
    @tag :external_network
    test "client stops cleanly when reconnect_on_error is false" do
      # Start a client with reconnect_on_error: false
      {:ok, client} =
        Client.connect("wss://test.deribit.com/ws/api/v2",
          reconnect_on_error: false
        )

      # Monitor the client process
      ref = Process.monitor(client.server_pid)

      # Kill the Gun process to simulate connection failure
      Process.exit(client.gun_pid, :kill)

      # Verify the client process stops
      assert_receive {:DOWN, ^ref, :process, _pid, {:connection_down, :killed}}, 5000

      # Verify the client process is no longer alive
      refute Process.alive?(client.server_pid)
    end

    @tag :external_network
    test "client behavior with bad URL demonstrates reconnect_on_error difference" do
      # Test with reconnect_on_error: false - should stop immediately
      # May return :connection_failed or :timeout depending on network conditions
      result1 =
        Client.connect("wss://nonexistent.example.com:9999/ws",
          reconnect_on_error: false,
          timeout: 1000
        )

      assert {:error, reason1} = result1
      assert reason1 in [:connection_failed, :timeout]

      # Test with reconnect_on_error: true (default) - will retry
      result2 =
        Client.connect("wss://nonexistent.example.com:9999/ws",
          reconnect_on_error: true,
          timeout: 1000,
          retry_count: 1,
          retry_delay: 100
        )

      assert {:error, reason2} = result2
      assert reason2 in [:connection_failed, :timeout]
    end

    @tag :external_network
    test "adapter pattern with supervised client disables internal reconnection" do
      # This demonstrates the intended pattern where the adapter
      # handles reconnection instead of the client
      client_opts = [
        reconnect_on_error: false,
        timeout: 5000
      ]

      # Start client with reconnect disabled (as adapter would do)
      {:ok, client} = Client.connect("wss://test.deribit.com/ws/api/v2", client_opts)

      # Verify the client is configured not to reconnect
      {:ok, state} = GenServer.call(client.server_pid, :get_state_internal)
      refute state.config.reconnect_on_error

      # Clean up
      Client.close(client)
    end
  end
end
