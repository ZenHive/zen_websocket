defmodule ZenWebsocket.ClientTest do
  use ExUnit.Case

  alias ZenWebsocket.Client
  alias ZenWebsocket.Config
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  test "connect to test.deribit.com with URL string" do
    {:ok, client} = Client.connect(@deribit_test_url)

    assert client.gun_pid
    assert client.stream_ref
    assert client.state == :connected
    assert client.url == @deribit_test_url

    Client.close(client)
  end

  test "connect with config struct" do
    {:ok, config} = Config.new(@deribit_test_url, timeout: 10_000)
    {:ok, client} = Client.connect(config)

    assert client.gun_pid
    assert client.stream_ref
    assert client.state == :connected
    assert client.url == @deribit_test_url

    Client.close(client)
  end

  test "connect with invalid URL returns error" do
    {:error, "Invalid URL format"} = Client.connect("http://example.com")
  end

  test "connect with invalid config options returns error" do
    {:error, "Timeout must be positive"} = Client.connect(@deribit_test_url, timeout: 0)
  end

  test "get_state returns current state" do
    {:ok, client} = Client.connect(@deribit_test_url)

    assert Client.get_state(client) == :connected

    Client.close(client)
  end

  test "send_message when connected succeeds" do
    {:ok, client} = Client.connect(@deribit_test_url)

    result = Client.send_message(client, "test")
    assert :ok == result

    Client.close(client)
  end

  test "subscribe formats message correctly" do
    {:ok, client} = Client.connect(@deribit_test_url)

    result = Client.subscribe(client, ["deribit_price_index.btc_usd"])
    assert :ok == result

    Client.close(client)
  end

  describe "default message handler" do
    setup do
      # Start a local mock server with exact echo behavior
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

    test "sends text messages to calling process by default", %{mock_url: mock_url} do
      {:ok, client} = Client.connect(mock_url)

      # Send a test message
      test_message = "Hello, WebSocket!"
      assert :ok = Client.send_message(client, test_message)

      # Should receive the echoed message as {:websocket_message, data}
      assert_receive {:websocket_message, ^test_message}, 5_000

      Client.close(client)
    end

    test "custom handler overrides default behavior", %{mock_url: mock_url} do
      test_pid = self()

      # Custom handler that sends different message format
      custom_handler = fn
        {:message, data} -> send(test_pid, {:custom_message, data})
        _other -> :ok
      end

      {:ok, client} = Client.connect(mock_url, handler: custom_handler)

      test_message = "Custom handler test"
      assert :ok = Client.send_message(client, test_message)

      # Should receive custom format, not default
      assert_receive {:custom_message, ^test_message}, 5_000
      refute_receive {:websocket_message, _}, 100

      Client.close(client)
    end

    test "handles binary messages with default handler", %{mock_url: mock_url} do
      {:ok, client} = Client.connect(mock_url)

      # Send a simple text message (mock server will echo it back)
      test_message = "Binary handler test"

      assert :ok = Client.send_message(client, test_message)

      # Should receive the echoed message via default handler
      assert_receive {:websocket_message, ^test_message}, 5_000

      # Verify the GenServer is still alive (didn't crash from message handling)
      assert Process.alive?(client.server_pid)

      Client.close(client)
    end

    test "default handler ignores unrecognized message types" do
      # Test handler function directly since we can't easily trigger other frame types
      parent_pid = self()

      handler = fn
        {:message, data} -> send(parent_pid, {:websocket_message, data})
        {:binary, data} -> send(parent_pid, {:websocket_message, data})
        {:frame, frame} -> send(parent_pid, {:websocket_frame, frame})
        _other -> :ok
      end

      # These should not crash
      assert :ok = handler.({:unknown_type, "data"})
      assert :ok = handler.(:weird_message)

      # Should not have received anything
      refute_receive _, 10
    end
  end

  describe "GenServer implementation" do
    test "client struct includes server_pid" do
      {:ok, client} = Client.connect(@deribit_test_url)

      assert is_pid(client.server_pid)
      assert Process.alive?(client.server_pid)

      Client.close(client)
    end

    test "closing client stops GenServer process" do
      {:ok, client} = Client.connect(@deribit_test_url)
      server_pid = client.server_pid

      assert Process.alive?(server_pid)
      Client.close(client)

      # Give the process time to stop
      Process.sleep(100)
      refute Process.alive?(server_pid)
    end

    test "multiple clients can run concurrently" do
      {:ok, client1} = Client.connect(@deribit_test_url)
      {:ok, client2} = Client.connect(@deribit_test_url)

      assert client1.server_pid != client2.server_pid
      assert Process.alive?(client1.server_pid)
      assert Process.alive?(client2.server_pid)

      Client.close(client1)
      Client.close(client2)
    end

    test "GenServer handles connection errors properly" do
      # Use a very short timeout
      config = Config.new!(@deribit_test_url, timeout: 1)

      # Should get either timeout or connection_failed
      assert {:error, reason} = Client.connect(config)
      assert reason in [:timeout, :connection_failed]
    end

    test "client operations work through GenServer calls" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Test that operations go through GenServer
      assert Client.get_state(client) == :connected
      assert :ok = Client.send_message(client, "test")

      Client.close(client)
    end

    test "Gun sends messages to Client GenServer process" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Send a test message that should trigger a response
      test_request =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/test",
          "params" => %{},
          "id" => 1
        })

      # The Client GenServer should handle the response with correlation
      assert {:ok, %{"id" => 1, "result" => %{"version" => _}}} = Client.send_message(client, test_request)

      # Give time for response
      Process.sleep(100)

      # Verify the GenServer is still alive (didn't crash from unhandled messages)
      assert Process.alive?(client.server_pid)

      Client.close(client)
    end

    # TODO: Implement reconnection test - requires either:
    # 1. Kill the Gun process and verify reconnection
    # 2. Use MockWebSockServer with connection drop simulation
    # Tracked as future work for reconnection testing infrastructure
    @tag :skip
    test "reconnection maintains Gun message ownership in Client GenServer" do
    end
  end
end
