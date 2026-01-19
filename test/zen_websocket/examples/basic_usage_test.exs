defmodule ZenWebsocket.Examples.BasicUsageTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.Config
  alias ZenWebsocket.Examples.Docs.BasicUsage
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @deribit_testnet "wss://test.deribit.com/ws/api/v2"

  describe "deribit_testnet_example/0" do
    @tag timeout: 10_000
    test "demonstrates basic Deribit testnet connection from docs" do
      # Run the example function
      assert {:ok, client} = BasicUsage.deribit_testnet_example()

      # Client should already be closed by the example
      refute Process.alive?(client.server_pid)
    end
  end

  describe "custom_headers_example/1" do
    @tag timeout: 10_000
    test "demonstrates connection with custom headers" do
      # Run the example with a test token
      assert {:ok, client} = BasicUsage.custom_headers_example("test-token-123")

      # Verify connection was established
      assert Client.get_state(client) == :connected

      # Clean up
      assert :ok = Client.close(client)
    end
  end

  describe "basic usage patterns with MockWebSockServer" do
    setup do
      {:ok, server, port} = MockWebSockServer.start_link()

      # Set handler for exact echo (no prefix)
      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      on_exit(fn -> MockWebSockServer.stop(server) end)

      {:ok, server: server, port: port, mock_url: mock_url}
    end

    @tag timeout: 10_000
    test "simple connection and message exchange", %{mock_url: mock_url} do
      assert {:ok, client} = Client.connect(mock_url)

      # Send a message
      assert :ok = Client.send_message(client, "test message")

      # Receive the echo
      assert_receive {:websocket_message, "test message"}, 5_000

      assert :ok = Client.close(client)
    end

    @tag timeout: 10_000
    test "multiple messages in sequence", %{mock_url: mock_url} do
      assert {:ok, client} = Client.connect(mock_url)

      # Send multiple messages
      messages = ["first", "second", "third"]

      for msg <- messages do
        assert :ok = Client.send_message(client, msg)
      end

      # Receive all echoes
      for msg <- messages do
        assert_receive {:websocket_message, ^msg}, 5_000
      end

      assert :ok = Client.close(client)
    end

    @tag timeout: 10_000
    test "connection with custom configuration", %{mock_url: mock_url} do
      config = %Config{
        url: mock_url,
        headers: [
          {"User-Agent", "ZenWebsocket Test"},
          {"X-Test-Header", "test-value"}
        ],
        timeout: 10_000,
        retry_count: 3
      }

      assert {:ok, client} = Client.connect(config)
      assert Client.get_state(client) == :connected

      # Test message exchange
      assert :ok = Client.send_message(client, "config test")
      assert_receive {:websocket_message, "config test"}, 5_000

      assert :ok = Client.close(client)
    end

    @tag timeout: 15_000
    test "parallel connections work independently", %{mock_url: mock_url} do
      assert {:ok, client1} = Client.connect(mock_url)
      assert {:ok, client2} = Client.connect(mock_url)

      # Send different messages from each client
      assert :ok = Client.send_message(client1, "from client 1")
      assert :ok = Client.send_message(client2, "from client 2")

      # Each should receive its own echo
      assert_receive {:websocket_message, "from client 1"}, 5_000
      assert_receive {:websocket_message, "from client 2"}, 5_000

      assert :ok = Client.close(client1)
      assert :ok = Client.close(client2)
    end

    @tag timeout: 10_000
    test "handles large messages", %{mock_url: mock_url} do
      assert {:ok, client} = Client.connect(mock_url)

      # Create a large message (10KB)
      large_message = String.duplicate("x", 10_000)

      assert :ok = Client.send_message(client, large_message)
      assert_receive {:websocket_message, ^large_message}, 5_000

      assert :ok = Client.close(client)
    end

    @tag timeout: 10_000
    test "validates invalid URLs" do
      assert {:error, _} = Client.connect("not-a-websocket-url")
      # Wrong protocol
      assert {:error, _} = Client.connect("http://example.com")
    end
  end

  describe "Deribit testnet integration" do
    @tag :integration
    @tag timeout: 10_000
    test "connects to Deribit testnet and receives response" do
      assert {:ok, client} = Client.connect(@deribit_testnet)

      # Send public/test request
      request =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/test",
          "params" => %{},
          "id" => 1
        })

      assert {:ok, response} = Client.send_message(client, request)
      assert response["id"] == 1
      assert response["result"]["version"]

      assert :ok = Client.close(client)
    end
  end
end
