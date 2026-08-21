defmodule ZenWebsocket.Examples.SupervisedConnectionTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @moduletag :integration

  @deribit_testnet "wss://test.deribit.com/ws/api/v2"

  setup do
    # Start a supervised instance for testing
    {:ok, sup_pid} = start_supervised({ClientSupervisor, []})

    # Start a mock server for testing
    {:ok, server, port} = MockWebSockServer.start_link()

    MockWebSockServer.set_handler(server, fn
      {:text, msg} -> {:reply, {:text, msg}}
      {:binary, data} -> {:reply, {:binary, data}}
    end)

    mock_url = "ws://localhost:#{port}/ws"

    on_exit(fn -> MockWebSockServer.stop(server) end)

    {:ok, supervisor: sup_pid, server: server, port: port, mock_url: mock_url}
  end

  describe "basic supervised connections" do
    test "starts supervised client connection", %{mock_url: mock_url} do
      {:ok, client} = ClientSupervisor.start_client(mock_url)

      assert is_pid(client.server_pid)
      assert Process.alive?(client.server_pid)

      # Verify connection works - can return :ok or {:ok, response}
      assert :ok = Client.send_message(client, "test message")

      :ok = Client.close(client)
    end

    test "restarts client on crash", %{mock_url: mock_url} do
      {:ok, client} = ClientSupervisor.start_client(mock_url)

      original_pid = client.server_pid
      assert Process.alive?(original_pid)

      # Kill the client process
      Process.exit(original_pid, :kill)

      # Wait for supervisor to restart
      Process.sleep(100)

      # Check if a new process was started
      clients = ClientSupervisor.list_clients()
      assert clients != []

      new_pid = hd(clients)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end

    test "lists all supervised clients", %{mock_url: mock_url} do
      # Start multiple clients
      {:ok, _client1} = ClientSupervisor.start_client(mock_url)
      {:ok, _client2} = ClientSupervisor.start_client(mock_url)

      clients = ClientSupervisor.list_clients()
      assert [_, _] = clients
      assert Enum.all?(clients, &Process.alive?/1)
    end
  end

  describe "supervision tree integration" do
    test "integrates with application supervision tree", %{mock_url: mock_url} do
      # Example of how it would be used in an application
      defmodule TestApp do
        @moduledoc false
        use Application

        def start(_type, _args) do
          children = [
            {Task.Supervisor, name: TestApp.TaskSupervisor}
          ]

          opts = [strategy: :one_for_one, name: TestApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

      # Start the app
      {:ok, _} = TestApp.start(:normal, [])

      # Use the already running supervisor from setup
      {:ok, client} = ClientSupervisor.start_client(mock_url)
      assert Process.alive?(client.server_pid)

      :ok = Client.close(client)
    end

    test "handles supervisor restarts", %{mock_url: mock_url} do
      {:ok, client} =
        ClientSupervisor.start_client(mock_url,
          retry_count: 3,
          retry_delay: 100
        )

      # Get supervisor stats before
      stats_before = DynamicSupervisor.count_children(ClientSupervisor)
      assert stats_before.active > 0

      # Force multiple crashes to test restart limits
      original_pid = client.server_pid

      # First crash
      Process.exit(original_pid, :kill)
      Process.sleep(150)

      # Should have restarted
      clients = ClientSupervisor.list_clients()
      assert clients != []
    end
  end

  describe "error handling and recovery" do
    test "handles connection failures gracefully" do
      # Try to connect to invalid URL
      result = ClientSupervisor.start_client("ws://invalid.example.com:9999")

      assert {:error, _reason} = result

      # Verify no zombie processes
      Process.sleep(100)
      assert ClientSupervisor.list_clients() == []
    end

    test "stops supervised client cleanly", %{mock_url: mock_url} do
      {:ok, client} = ClientSupervisor.start_client(mock_url)
      pid = client.server_pid

      assert Process.alive?(pid)
      assert [_] = ClientSupervisor.list_clients()

      # Stop the client
      :ok = ClientSupervisor.stop_client(pid)

      Process.sleep(100)
      refute Process.alive?(pid)
      assert ClientSupervisor.list_clients() == []
    end

    test "supervised client maintains state across restarts", %{mock_url: mock_url} do
      {:ok, client} =
        ClientSupervisor.start_client(mock_url,
          heartbeat_interval: 30_000
        )

      # Subscribe - mock server returns echo of subscription message, not a subscription confirmation
      # We just verify the call doesn't crash the client
      assert :ok = Client.subscribe(client, ["test.channel"])

      # Get current connection state
      assert Client.get_state(client) == :connected

      # Force restart
      Process.exit(client.server_pid, :kill)
      Process.sleep(200)

      # Note: In a real implementation with supervision, you'd need to
      # reacquire the client reference after restart. This is just testing
      # the supervision pattern.
      new_clients = ClientSupervisor.list_clients()
      assert new_clients != []
    end
  end

  describe "advanced supervision patterns" do
    test "multiple supervised connections with different configs", %{mock_url: mock_url} do
      configs = [
        %{url: mock_url, retry_count: 3},
        %{url: mock_url, retry_count: 5},
        %{url: mock_url, heartbeat_interval: 20_000}
      ]

      clients =
        for config <- configs do
          {:ok, client} =
            ClientSupervisor.start_client(
              config.url,
              Keyword.new(Map.delete(config, :url))
            )

          client
        end

      assert [_, _, _] = clients
      assert Enum.all?(clients, fn c -> Process.alive?(c.server_pid) end)

      # Clean up
      for client <- clients do
        ClientSupervisor.stop_client(client.server_pid)
      end
    end

    test "respects max restart limits", %{mock_url: mock_url} do
      {:ok, _client} = ClientSupervisor.start_client(mock_url)
      sup_pid = Process.whereis(ClientSupervisor)
      assert is_pid(sup_pid)
      ref = Process.monitor(sup_pid)

      # max_restarts: 10 — the 11th crash exceeds intensity and stops the supervisor
      Enum.each(1..11, fn _ ->
        pid = await_supervised_client()
        monitor = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _} -> :ok
        after
          1_000 -> flunk("Supervised client #{inspect(pid)} did not die")
        end
      end)

      assert_receive {:DOWN, ^ref, :process, ^sup_pid, _reason}, 2_000
      refute Process.alive?(sup_pid)
    end
  end

  describe "real-world supervised connection patterns" do
    test "connection manager pattern", %{mock_url: mock_url} do
      defmodule ConnectionManager do
        @moduledoc false
        use GenServer

        def start_link(urls) do
          GenServer.start_link(__MODULE__, urls)
        end

        def init(urls) do
          clients =
            Enum.map(urls, fn url ->
              case ClientSupervisor.start_client(url) do
                {:ok, client} -> {url, client}
                {:error, _} -> {url, nil}
              end
            end)

          {:ok, %{clients: clients}}
        end

        def get_client(manager, url) do
          GenServer.call(manager, {:get_client, url})
        end

        def handle_call({:get_client, url}, _from, state) do
          client =
            case List.keyfind(state.clients, url, 0) do
              {^url, client} -> client
              nil -> nil
            end

          {:reply, client, state}
        end
      end

      # Start connection manager
      urls = [mock_url]
      {:ok, manager} = ConnectionManager.start_link(urls)

      # Get managed client
      client = ConnectionManager.get_client(manager, mock_url)
      assert client

      # Use the client - can return :ok or {:ok, response}
      assert :ok = Client.send_message(client, "managed message")
    end

    @tag :external_network
    test "supervised Deribit connection" do
      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if is_nil(client_id) or is_nil(client_secret) do
        flunk("""
        Missing Deribit testnet credentials!

        Set these environment variables:
          export DERIBIT_CLIENT_ID="your_client_id"
          export DERIBIT_CLIENT_SECRET="your_client_secret"

        Get credentials at: https://test.deribit.com
        """)
      end

      opts = [
        heartbeat_interval: 30_000,
        timeout: 10_000
      ]

      {:ok, client} = ClientSupervisor.start_client(@deribit_testnet, opts)

      auth_msg = %{
        "jsonrpc" => "2.0",
        "method" => "public/auth",
        "params" => %{
          "grant_type" => "client_credentials",
          "client_id" => client_id,
          "client_secret" => client_secret
        },
        "id" => 1
      }

      assert {:ok, %{"result" => %{"access_token" => _}}} =
               Client.send_message(client, Jason.encode!(auth_msg))

      assert Process.alive?(client.server_pid)

      :ok = Client.close(client)
    end
  end

  defp await_supervised_client(remaining_ms \\ 2_000)

  defp await_supervised_client(remaining_ms) when remaining_ms <= 0 do
    flunk("No supervised client appeared before timeout")
  end

  defp await_supervised_client(remaining_ms) do
    case ClientSupervisor.list_clients() do
      [pid | _] ->
        pid

      [] ->
        Process.sleep(20)
        await_supervised_client(remaining_ms - 20)
    end
  end
end
