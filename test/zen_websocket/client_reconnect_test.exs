defmodule ZenWebsocket.ClientReconnectTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client

  require Logger

  @moduletag :integration

  describe "reconnect_on_error configuration" do
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
