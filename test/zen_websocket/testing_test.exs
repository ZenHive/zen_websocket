defmodule ZenWebsocket.TestingTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Testing

  @moduletag :integration

  describe "start_mock_server/1" do
    test "starts a mock server with default options" do
      {:ok, server} = Testing.start_mock_server()

      assert is_pid(server.pid)
      assert is_integer(server.port)
      assert server.port > 0
      assert String.starts_with?(server.url, "ws://localhost:")
      assert is_pid(server.message_agent)

      Testing.stop_server(server)
    end

    test "starts a mock server and assigns a port" do
      # Use port 0 to let OS assign available port, avoiding conflicts
      {:ok, server} = Testing.start_mock_server(port: 0)

      assert is_integer(server.port)
      assert server.port > 0
      assert server.url == "ws://localhost:#{server.port}/ws"

      Testing.stop_server(server)
    end

    test "generates correct URL for TLS protocol" do
      {:ok, server} = Testing.start_mock_server(protocol: :tls)

      assert String.starts_with?(server.url, "wss://localhost:")

      Testing.stop_server(server)
    end
  end

  describe "stop_server/1" do
    test "stops the server and cleans up resources" do
      {:ok, server} = Testing.start_mock_server()

      assert Process.alive?(server.pid)
      assert Process.alive?(server.message_agent)

      :ok = Testing.stop_server(server)

      # Give processes time to terminate
      Process.sleep(50)

      refute Process.alive?(server.pid)
      refute Process.alive?(server.message_agent)
    end

    test "handles already stopped server gracefully" do
      {:ok, server} = Testing.start_mock_server()
      Testing.stop_server(server)

      # Second stop should not raise
      :ok = Testing.stop_server(server)
    end
  end

  describe "inject_message/2" do
    test "sends message to connected client" do
      {:ok, server} = Testing.start_mock_server()

      # Connect a client
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      # Inject a message from server
      :ok = Testing.inject_message(server, ~s({"type": "notification"}))

      # Client should receive the message
      assert_receive {:websocket_message, ~s({"type": "notification"})}, 1000

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end

    test "handles no connected clients gracefully" do
      {:ok, server} = Testing.start_mock_server()

      # Should not raise even with no clients
      :ok = Testing.inject_message(server, "hello")

      Testing.stop_server(server)
    end
  end

  describe "assert_message_sent/3" do
    test "returns true for exact string match" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      # Send a message from client
      ZenWebsocket.Client.send_message(client, "hello world")

      # Assert it was sent
      assert Testing.assert_message_sent(server, "hello world", 1000)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end

    test "returns true for regex match" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      ZenWebsocket.Client.send_message(client, ~s({"type": "ping"}))

      assert Testing.assert_message_sent(server, ~r/"type":\s*"ping"/, 1000)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end

    test "returns true for partial map match" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      ZenWebsocket.Client.send_message(client, ~s({"type": "ping", "extra": "data"}))

      # Should match even though message has extra fields
      assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end

    test "returns true for function match" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      ZenWebsocket.Client.send_message(client, ~s({"value": 42}))

      matcher = fn msg ->
        case Jason.decode(msg) do
          {:ok, %{"value" => v}} when v > 40 -> true
          _ -> false
        end
      end

      assert Testing.assert_message_sent(server, matcher, 1000)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end

    test "returns false when no matching message within timeout" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      ZenWebsocket.Client.send_message(client, "actual message")

      # Should timeout looking for non-existent message
      refute Testing.assert_message_sent(server, "nonexistent message", 100)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end
  end

  describe "simulate_disconnect/2" do
    test "disconnects client with :normal reason" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url, reconnect_on_error: false)

      assert ZenWebsocket.Client.get_state(client) == :connected

      Testing.simulate_disconnect(server, :normal)

      # Give time for disconnect to propagate
      Process.sleep(100)

      # Client should be disconnected
      refute Process.alive?(client.server_pid)

      Testing.stop_server(server)
    end

    test "disconnects client with :going_away reason" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url, reconnect_on_error: false)

      Testing.simulate_disconnect(server, :going_away)

      Process.sleep(100)

      refute Process.alive?(client.server_pid)

      Testing.stop_server(server)
    end

    test "disconnects client with custom close code" do
      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url, reconnect_on_error: false)

      Testing.simulate_disconnect(server, {:code, 1008})

      Process.sleep(100)

      refute Process.alive?(client.server_pid)

      Testing.stop_server(server)
    end
  end

  describe "integration with ExUnit setup" do
    setup do
      {:ok, server} = Testing.start_mock_server()
      on_exit(fn -> Testing.stop_server(server) end)
      {:ok, server: server}
    end

    test "server is available in test context", %{server: server} do
      assert is_pid(server.pid)
      assert Process.alive?(server.pid)
    end

    test "can connect multiple clients", %{server: server} do
      {:ok, client1} = ZenWebsocket.Client.connect(server.url)
      {:ok, client2} = ZenWebsocket.Client.connect(server.url)

      assert ZenWebsocket.Client.get_state(client1) == :connected
      assert ZenWebsocket.Client.get_state(client2) == :connected

      ZenWebsocket.Client.close(client1)
      ZenWebsocket.Client.close(client2)
    end
  end
end
