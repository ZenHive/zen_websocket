defmodule ZenWebsocket.Examples.SupervisedClientTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.Examples.SupervisedClient
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @moduletag :integration

  setup do
    # Start the ClientSupervisor
    {:ok, _sup_pid} = start_supervised({ClientSupervisor, []})

    # Start a mock server for testing
    {:ok, server, port} = MockWebSockServer.start_link()

    MockWebSockServer.set_handler(server, fn
      {:text, msg} -> {:reply, {:text, msg}}
      {:binary, data} -> {:reply, {:binary, data}}
    end)

    mock_url = "ws://localhost:#{port}/ws"

    on_exit(fn -> MockWebSockServer.stop(server) end)

    {:ok, server: server, port: port, mock_url: mock_url}
  end

  describe "start_connection/2" do
    test "starts a supervised WebSocket connection", %{mock_url: mock_url} do
      {:ok, client} = SupervisedClient.start_connection(mock_url)

      assert is_map(client)
      assert is_pid(client.server_pid)
      assert Process.alive?(client.server_pid)

      # Clean up
      SupervisedClient.stop_connection(client.server_pid)
    end

    test "passes options to the client", %{mock_url: mock_url} do
      opts = [retry_count: 5, heartbeat_interval: 20_000]
      {:ok, client} = SupervisedClient.start_connection(mock_url, opts)

      assert Process.alive?(client.server_pid)

      # Clean up
      SupervisedClient.stop_connection(client.server_pid)
    end

    test "handles connection failures" do
      result = SupervisedClient.start_connection("ws://invalid.example.com:9999")
      assert {:error, _reason} = result
    end
  end

  describe "start_multiple/1" do
    test "starts multiple supervised connections", %{mock_url: mock_url} do
      configs = [
        {mock_url, retry_count: 3},
        {mock_url, heartbeat_interval: 15_000}
      ]

      results = SupervisedClient.start_multiple(configs)

      assert length(results) == 2

      assert Enum.all?(results, fn {url, result} ->
               assert url == mock_url

               case result do
                 {:ok, client} ->
                   is_map(client) && Process.alive?(client.server_pid)

                 {:error, _} ->
                   false
               end
             end)

      # Clean up
      Enum.each(results, fn {_url, result} ->
        case result do
          {:ok, client} -> SupervisedClient.stop_connection(client.server_pid)
          _ -> :ok
        end
      end)
    end

    test "handles mixed success and failure", %{mock_url: mock_url} do
      configs = [
        {mock_url, []},
        {"ws://invalid.example.com:9999", []}
      ]

      results = SupervisedClient.start_multiple(configs)

      assert length(results) == 2

      # Check first succeeded
      {url1, result1} = Enum.at(results, 0)
      assert url1 == mock_url
      assert {:ok, client} = result1
      assert Process.alive?(client.server_pid)

      # Check second failed
      {url2, result2} = Enum.at(results, 1)
      assert url2 == "ws://invalid.example.com:9999"
      assert {:error, _} = result2

      # Clean up
      SupervisedClient.stop_connection(client.server_pid)
    end
  end

  describe "list_connections/0" do
    test "lists all supervised connections", %{mock_url: mock_url} do
      # Start with no connections
      assert SupervisedClient.list_connections() == []

      # Start some connections
      {:ok, client1} = SupervisedClient.start_connection(mock_url)
      {:ok, client2} = SupervisedClient.start_connection(mock_url)

      connections = SupervisedClient.list_connections()
      assert length(connections) == 2
      assert client1.server_pid in connections
      assert client2.server_pid in connections

      # Clean up
      SupervisedClient.stop_connection(client1.server_pid)
      SupervisedClient.stop_connection(client2.server_pid)

      # Verify cleanup
      Process.sleep(100)
      assert SupervisedClient.list_connections() == []
    end
  end

  describe "stop_connection/1" do
    test "stops a supervised connection", %{mock_url: mock_url} do
      {:ok, client} = SupervisedClient.start_connection(mock_url)
      pid = client.server_pid

      assert Process.alive?(pid)
      assert pid in SupervisedClient.list_connections()

      :ok = SupervisedClient.stop_connection(pid)

      Process.sleep(100)
      refute Process.alive?(pid)
      refute pid in SupervisedClient.list_connections()
    end

    test "handles stopping non-existent connection" do
      fake_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      # Should not crash, returns error for non-existent process
      result = SupervisedClient.stop_connection(fake_pid)
      assert {:error, :not_found} = result
    end
  end

  describe "integration patterns" do
    test "supervised client survives crashes", %{mock_url: mock_url} do
      {:ok, client} = SupervisedClient.start_connection(mock_url)
      original_pid = client.server_pid

      # Kill the client process
      Process.exit(original_pid, :kill)

      # Wait for supervisor to restart
      Process.sleep(100)

      # Should have a new process
      connections = SupervisedClient.list_connections()
      assert connections != []
      new_pid = hd(connections)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      # Clean up
      SupervisedClient.stop_connection(new_pid)
    end

    test "multiple connections with different configurations", %{mock_url: mock_url} do
      configs = [
        {mock_url, retry_count: 3, retry_delay: 1000},
        {mock_url, retry_count: 5, retry_delay: 2000},
        {mock_url, heartbeat_interval: 20_000}
      ]

      results = SupervisedClient.start_multiple(configs)

      successful =
        Enum.filter(results, fn {_, result} ->
          match?({:ok, _}, result)
        end)

      assert length(successful) == 3

      # All should be alive
      assert Enum.all?(successful, fn {_, {:ok, client}} ->
               Process.alive?(client.server_pid)
             end)

      # Clean up all connections
      Enum.each(successful, fn {_, {:ok, client}} ->
        SupervisedClient.stop_connection(client.server_pid)
      end)
    end
  end
end
