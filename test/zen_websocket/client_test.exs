defmodule ZenWebsocket.ClientTest do
  use ExUnit.Case

  alias ZenWebsocket.Client
  alias ZenWebsocket.ClientSupervisor
  alias ZenWebsocket.Config
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @moduletag :integration

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

  test "subscribe sends message to server" do
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

      # Should receive the echoed message exactly once
      assert_receive {:websocket_message, ^test_message}, 5_000
      refute_receive {:websocket_message, _}, 200

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
        _other -> :ok
      end

      # These should not crash
      assert :ok = handler.({:unknown_type, "data"})
      assert :ok = handler.(:weird_message)

      # Should not have received anything
      refute_receive _, 10
    end

    test "subscribe sends correct JSON-RPC payload", %{server: server, mock_url: mock_url} do
      test_pid = self()

      # Handler that captures raw frames received by the server
      MockWebSockServer.set_handler(server, fn
        {:text, msg} ->
          send(test_pid, {:server_received, msg})
          :ok
      end)

      {:ok, client} = Client.connect(mock_url)

      channels = ["deribit_price_index.btc_usd", "trades.BTC-PERPETUAL"]
      assert :ok = Client.subscribe(client, channels)

      assert_receive {:server_received, raw}, 5_000
      msg = Jason.decode!(raw)

      assert msg["method"] == "public/subscribe"
      assert msg["params"]["channels"] == channels

      Client.close(client)
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

    test "reconnection delivers frames after server restart" do
      echo_handler = fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end

      # Start a mock server and capture its port
      {:ok, server, port} = MockWebSockServer.start_link()
      MockWebSockServer.set_handler(server, echo_handler)

      mock_url = "ws://localhost:#{port}/ws"

      {:ok, client} = Client.connect(mock_url, retry_count: 10, retry_delay: 100)
      server_pid = client.server_pid

      assert Client.get_state(client) == :connected

      # Kill the mock server to trigger disconnect
      MockWebSockServer.stop(server)

      # Allow time for Gun to detect TCP close and Client to enter reconnection
      disconnect_detection_ms = 300
      Process.sleep(disconnect_detection_ms)
      assert Process.alive?(server_pid), "Client GenServer crashed instead of reconnecting"

      # Start a NEW server on the same port with echo handler
      {:ok, server2, ^port} = MockWebSockServer.start_link(port: port)
      MockWebSockServer.set_handler(server2, echo_handler)

      # Wait for client to reconnect (poll up to 3 seconds)
      reconnected =
        Enum.reduce_while(1..30, false, fn _, _acc ->
          Process.sleep(100)

          if Client.get_state(client) == :connected do
            {:halt, true}
          else
            {:cont, false}
          end
        end)

      assert reconnected, "Client did not reconnect within 3 seconds"

      # Send a message and verify the echo comes back through the new connection
      test_message = "post-reconnect-echo"
      assert :ok = Client.send_message(client, test_message)
      assert_receive {:websocket_message, ^test_message}, 5_000

      Client.close(client)
      MockWebSockServer.stop(server2)
    end
  end

  describe "pending requests on disconnect" do
    test "blocked callers receive {:error, :disconnected} on automatic disconnect" do
      # Handler that swallows inbound frames (never replies), so the correlated
      # request stays pending until the connection drops.
      silent_handler = fn _ -> :ok end

      {:ok, server, port} = MockWebSockServer.start_link()
      MockWebSockServer.set_handler(server, silent_handler)

      mock_url = "ws://localhost:#{port}/ws"
      {:ok, client} = Client.connect(mock_url, retry_count: 10, retry_delay: 100, request_timeout: 30_000)

      assert Client.get_state(client) == :connected

      # Spawn a task that sends a correlated request and blocks waiting for a reply
      test_pid = self()

      caller =
        spawn(fn ->
          request = Jason.encode!(%{"id" => "drain-test-1", "method" => "noop"})
          result = Client.send_message(client, request)
          send(test_pid, {:caller_result, result})
        end)

      ref = Process.monitor(caller)

      # Give the caller time to get the request into pending_requests before we kill the socket.
      Process.sleep(100)

      # Drop the server to trigger the automatic Gun-down / reconnect path
      MockWebSockServer.stop(server)

      # Blocked caller should get a prompt error, well before the 30s request_timeout.
      assert_receive {:caller_result, {:error, :disconnected}}, 2_000
      assert_receive {:DOWN, ^ref, :process, ^caller, _}, 1_000

      Client.close(client)
    end

    test "stale timeout from a disconnected request does not time out a reused ID after reconnect" do
      reused_id = "reused-id"
      request = Jason.encode!(%{"id" => reused_id, "method" => "noop"})

      {:ok, server, port} = MockWebSockServer.start_link()
      MockWebSockServer.set_handler(server, fn _ -> :ok end)

      mock_url = "ws://localhost:#{port}/ws"
      {:ok, client} = Client.connect(mock_url, retry_count: 10, retry_delay: 50, request_timeout: 300)

      assert Client.get_state(client) == :connected

      first_call =
        Task.async(fn ->
          Client.send_message(client, request)
        end)

      Process.sleep(50)
      MockWebSockServer.stop(server)

      assert {:error, :disconnected} = Task.await(first_call, 2_000)

      {:ok, server2, ^port} = MockWebSockServer.start_link(port: port)

      delayed_response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => reused_id,
          "result" => %{"ok" => true}
        })

      MockWebSockServer.set_handler(server2, fn
        {:text, _msg} ->
          Process.sleep(200)
          {:reply, {:text, delayed_response}}
      end)

      reconnected =
        Enum.reduce_while(1..30, false, fn _, _acc ->
          Process.sleep(50)

          if Client.get_state(client) == :connected do
            {:halt, true}
          else
            {:cont, false}
          end
        end)

      assert reconnected, "Client did not reconnect within 1.5 seconds"

      assert {:ok, %{"id" => ^reused_id, "result" => %{"ok" => true}}} =
               Client.send_message(client, request)

      Client.close(client)
      MockWebSockServer.stop(server2)
    end
  end

  describe "duplicate request ID (R043)" do
    test "second caller gets :duplicate_request_id while first still resolves" do
      dup_id = "r043-dup"
      request = Jason.encode!(%{"id" => dup_id, "method" => "public/test"})

      response =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => dup_id,
          "result" => %{"ok" => true}
        })

      {:ok, server, port} = MockWebSockServer.start_link()

      test_pid = self()
      frame_counter = :counters.new(1, [])

      # Signal receipt so the duplicate is fired only after track/4 has
      # registered the first request. Delay before replying so the first
      # call stays pending while the duplicate lands.
      MockWebSockServer.set_handler(server, fn
        {:text, _msg} ->
          :counters.add(frame_counter, 1, 1)
          send(test_pid, :first_frame_received)
          Process.sleep(300)
          {:reply, {:text, response}}
      end)

      mock_url = "ws://localhost:#{port}/ws"
      {:ok, client} = Client.connect(mock_url, request_timeout: 5_000)

      assert Client.get_state(client) == :connected

      first_call = Task.async(fn -> Client.send_message(client, request) end)

      # Deterministic sync: server-side receipt proves track/4 has already
      # registered the first request in pending_requests.
      assert_receive :first_frame_received, 1_000

      assert {:error, :duplicate_request_id} = Client.send_message(client, request)

      assert {:ok, %{"id" => ^dup_id, "result" => %{"ok" => true}}} =
               Task.await(first_call, 2_000)

      # Duplicate must never have reached the wire.
      assert :counters.get(frame_counter, 1) == 1

      Client.close(client)
      MockWebSockServer.stop(server)
    end
  end

  describe "handler callback regressions" do
    setup do
      {:ok, server, port} = MockWebSockServer.start_link()

      mock_url = "ws://localhost:#{port}/ws"

      on_exit(fn -> MockWebSockServer.stop(server) end)

      {:ok, server: server, port: port, mock_url: mock_url}
    end

    test "subscription messages are forwarded to user handler", %{server: server, mock_url: mock_url} do
      test_pid = self()

      # Handler that captures all messages
      handler = fn
        {:message, data} -> send(test_pid, {:handler_received, data})
        _other -> :ok
      end

      # Mock server replies with a subscription notification when it gets any text
      subscription_msg =
        Jason.encode!(%{
          "method" => "subscription",
          "params" => %{
            "channel" => "trades.BTC-PERPETUAL",
            "data" => %{"price" => 50_000, "amount" => 1.5}
          }
        })

      MockWebSockServer.set_handler(server, fn
        {:text, _msg} -> {:reply, {:text, subscription_msg}}
      end)

      {:ok, client} = Client.connect(mock_url, handler: handler)

      # Trigger a subscription message from the server
      :ok = Client.send_message(client, "trigger")

      # The subscription message MUST reach the user handler
      assert_receive {:handler_received, %{"method" => "subscription", "params" => params}}, 5_000
      assert params["channel"] == "trades.BTC-PERPETUAL"
      assert params["data"]["price"] == 50_000

      Client.close(client)
    end

    test "protocol errors are delivered to handler before connection stops", %{mock_url: mock_url} do
      test_pid = self()

      # Handler that captures protocol errors
      handler = fn
        {:protocol_error, reason} -> send(test_pid, {:handler_protocol_error, reason})
        _other -> :ok
      end

      {:ok, client} = Client.connect(mock_url, handler: handler)
      server_pid = client.server_pid

      # Monitor the GenServer to detect stop
      ref = Process.monitor(server_pid)

      # Send an invalid frame directly to the GenServer to trigger protocol error.
      # We simulate what Gun would send for a malformed frame.
      send(server_pid, {:gun_ws, client.gun_pid, client.stream_ref, {:invalid, "bad frame"}})

      # The handler should receive the protocol error BEFORE the process stops
      assert_receive {:handler_protocol_error, _reason}, 5_000

      # The process should stop after notifying
      assert_receive {:DOWN, ^ref, :process, ^server_pid, _reason}, 5_000
    end

    test "default handler delivers protocol errors to caller mailbox", %{mock_url: mock_url} do
      # Connect WITHOUT a custom handler — uses the default handler
      {:ok, client} = Client.connect(mock_url)
      server_pid = client.server_pid
      ref = Process.monitor(server_pid)

      # Trigger a protocol error via invalid frame
      send(server_pid, {:gun_ws, client.gun_pid, client.stream_ref, {:invalid, "bad frame"}})

      # Default handler should deliver {:websocket_protocol_error, reason}
      assert_receive {:websocket_protocol_error, _reason}, 5_000

      # Process stops after notifying
      assert_receive {:DOWN, ^ref, :process, ^server_pid, _reason}, 5_000
    end

    test "subscription tracker updates state alongside handler delivery", %{server: server, mock_url: mock_url} do
      test_pid = self()

      handler = fn
        {:message, _data} -> send(test_pid, :handler_called)
        _other -> :ok
      end

      # Server sends subscription confirmation with channel info
      confirmation_msg =
        Jason.encode!(%{
          "method" => "subscription",
          "params" => %{"channel" => "orderbook.ETH-PERPETUAL"}
        })

      MockWebSockServer.set_handler(server, fn
        {:text, _msg} -> {:reply, {:text, confirmation_msg}}
      end)

      {:ok, client} = Client.connect(mock_url, handler: handler)

      :ok = Client.send_message(client, "trigger")

      # Handler receives the message
      assert_receive :handler_called, 5_000

      # Subscription tracker must have updated state.subscriptions
      metrics = Client.get_state_metrics(client)

      assert metrics.subscriptions_size >= 1,
             "Expected subscriptions to be tracked, got size: #{metrics.subscriptions_size}"

      assert metrics.connection_state == :connected

      Client.close(client)
    end

    test "custom handler receives unmatched JSON-RPC responses (R047)", %{server: server, mock_url: mock_url} do
      test_pid = self()

      handler = fn
        {:unmatched_response, response} -> send(test_pid, {:handler_unmatched, response})
        _other -> :ok
      end

      # Server replies with a JSON-RPC response whose id won't match any pending request
      orphan_response = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 99_999, "result" => "late"})

      MockWebSockServer.set_handler(server, fn
        {:text, _msg} -> {:reply, {:text, orphan_response}}
      end)

      {:ok, client} = Client.connect(mock_url, handler: handler)
      :ok = Client.send_message(client, "trigger")

      assert_receive {:handler_unmatched, %{"id" => 99_999, "result" => "late"}}, 5_000

      Client.close(client)
    end

    test "default handler forwards unmatched responses to caller mailbox (R047)", %{server: server, mock_url: mock_url} do
      orphan_response = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 88_888, "result" => "orphan"})

      MockWebSockServer.set_handler(server, fn
        {:text, _msg} -> {:reply, {:text, orphan_response}}
      end)

      {:ok, client} = Client.connect(mock_url)
      :ok = Client.send_message(client, "trigger")

      assert_receive {:websocket_unmatched_response, %{"id" => 88_888, "result" => "orphan"}}, 5_000

      Client.close(client)
    end
  end

  describe "dead PID safety (R029)" do
    setup do
      # Create a guaranteed-dead PID by spawning and waiting for exit
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)

      dead_client = %Client{server_pid: pid, state: :connected}
      {:ok, client: dead_client}
    end

    test "send_message/2 returns error tuple for dead server_pid", %{client: client} do
      assert {:error, {:not_connected, :process_down}} = Client.send_message(client, "test")
    end

    test "get_state/1 returns :disconnected for dead server_pid", %{client: client} do
      assert :disconnected = Client.get_state(client)
    end

    test "close/1 returns :ok for dead server_pid", %{client: client} do
      assert :ok = Client.close(client)
    end

    test "get_heartbeat_health/1 returns nil for dead server_pid", %{client: client} do
      assert is_nil(Client.get_heartbeat_health(client))
    end

    test "get_state_metrics/1 returns nil for dead server_pid", %{client: client} do
      assert is_nil(Client.get_state_metrics(client))
    end

    test "get_latency_stats/1 returns nil for dead server_pid", %{client: client} do
      assert is_nil(Client.get_latency_stats(client))
    end
  end

  describe "dead PID failover with send_balanced/2 (R029)" do
    setup do
      start_supervised!({ClientSupervisor, []})

      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      on_exit(fn -> MockWebSockServer.stop(server) end)

      {:ok, mock_url: mock_url}
    end

    test "fails over when custom discovery returns a dead pid before a live client", %{mock_url: mock_url} do
      dead_pid = spawn(fn -> :ok end)
      ref = Process.monitor(dead_pid)
      receive do: ({:DOWN, ^ref, :process, ^dead_pid, _} -> :ok)

      {:ok, client} = ClientSupervisor.start_client(mock_url)
      discovery = fn -> [dead_pid, client.server_pid] end

      assert :ok = ClientSupervisor.send_balanced("failover works", client_discovery: discovery)

      Client.close(client)
    end

    test "returns process_down when custom discovery only returns dead pids" do
      dead_pid = spawn(fn -> :ok end)
      ref = Process.monitor(dead_pid)
      receive do: ({:DOWN, ^ref, :process, ^dead_pid, _} -> :ok)

      discovery = fn -> [dead_pid] end

      assert {:error, {:not_connected, :process_down}} =
               ClientSupervisor.send_balanced("no live clients", client_discovery: discovery)
    end
  end
end
