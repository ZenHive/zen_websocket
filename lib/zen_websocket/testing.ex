defmodule ZenWebsocket.Testing do
  @moduledoc """
  Test helpers for consumers testing ZenWebsocket integrations.

  This module provides utilities to create mock WebSocket servers, simulate
  disconnections, inject messages, and assert on client behavior during tests.

  ## Usage

      defmodule MyApp.WebSocketTest do
        use ExUnit.Case
        alias ZenWebsocket.Testing

        setup do
          {:ok, server} = Testing.start_mock_server()
          on_exit(fn -> Testing.stop_server(server) end)
          {:ok, server: server}
        end

        test "handles messages", %{server: server} do
          {:ok, client} = ZenWebsocket.Client.connect(server.url)

          # Inject a message from server to client
          Testing.inject_message(server, ~s({"type": "hello"}))

          # Verify client sent expected message
          assert Testing.assert_message_sent(server, ~s({"type": "ping"}), 1000)
        end

        test "handles disconnection", %{server: server} do
          {:ok, client} = ZenWebsocket.Client.connect(server.url)

          # Simulate server disconnect
          Testing.simulate_disconnect(server, :going_away)

          assert ZenWebsocket.Client.get_state(client) == :disconnected
        end
      end

  ## Functions

  - `start_mock_server/1` - Start a mock WebSocket server
  - `stop_server/1` - Stop a mock server and clean up resources
  - `simulate_disconnect/2` - Trigger a disconnect scenario
  - `inject_message/2` - Send a message from server to connected clients
  - `assert_message_sent/3` - Verify client sent an expected message
  """

  alias ZenWebsocket.Testing.Server

  @type server :: %{
          pid: pid(),
          port: pos_integer(),
          url: String.t(),
          message_agent: pid()
        }

  @type disconnect_reason :: :normal | :going_away | {:code, pos_integer()}

  @doc """
  Starts a mock WebSocket server for testing.

  ## Options

  - `:port` - Port to listen on (default: 0, which assigns a random available port)
  - `:protocol` - `:http` or `:tls` (default: `:http`)
  - `:handler` - Custom frame handler function (default: echo handler)

  ## Returns

  `{:ok, server}` where `server` is a map containing:
  - `:pid` - Server process PID
  - `:port` - Actual port the server is listening on
  - `:url` - Full WebSocket URL for connecting
  - `:message_agent` - Agent PID for message capture

  ## Examples

      {:ok, server} = Testing.start_mock_server()
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      # With custom port
      {:ok, server} = Testing.start_mock_server(port: 9999)

      # With TLS
      {:ok, server} = Testing.start_mock_server(protocol: :tls)
  """
  @spec start_mock_server(keyword()) :: {:ok, server()} | {:error, term()}
  def start_mock_server(opts \\ []) do
    Server.start(opts)
  end

  @doc """
  Stops a mock server and cleans up all resources.

  This should be called in test teardown (e.g., `on_exit` callback).

  ## Examples

      setup do
        {:ok, server} = Testing.start_mock_server()
        on_exit(fn -> Testing.stop_server(server) end)
        {:ok, server: server}
      end
  """
  @spec stop_server(server()) :: :ok
  def stop_server(server) do
    Server.stop(server)
  end

  @doc """
  Simulates a WebSocket disconnect from the server side.

  This is useful for testing client reconnection behavior and error handling.

  ## Disconnect Reasons

  - `:normal` - Clean close (code 1000)
  - `:going_away` - Server shutting down (code 1001)
  - `{:code, n}` - Custom close code

  ## Examples

      # Normal close
      Testing.simulate_disconnect(server, :normal)

      # Server going away
      Testing.simulate_disconnect(server, :going_away)

      # Custom close code
      Testing.simulate_disconnect(server, {:code, 1008})
  """
  @spec simulate_disconnect(server(), disconnect_reason()) :: :ok
  def simulate_disconnect(server, reason) do
    Server.simulate_disconnect(server, reason)
  end

  @doc """
  Injects a message from the server to all connected clients.

  The message is sent as a text frame to all currently connected WebSocket clients.

  ## Examples

      # Send JSON message
      Testing.inject_message(server, ~s({"type": "notification", "data": "hello"}))

      # Send plain text
      Testing.inject_message(server, "ping")
  """
  @spec inject_message(server(), binary()) :: :ok
  def inject_message(server, message) when is_binary(message) do
    Server.inject_message(server, message)
  end

  @doc """
  Asserts that a client sent an expected message to the server.

  This function polls the captured messages and checks if any match the expected
  pattern within the given timeout.

  ## Pattern Matching

  The `expected` parameter can be:
  - A string for exact match
  - A regex for pattern match
  - A map for partial JSON match (decoded message must contain all keys/values)
  - A function that returns true/false

  ## Examples

      # Exact string match
      assert Testing.assert_message_sent(server, ~s({"type": "ping"}), 1000)

      # Regex match
      assert Testing.assert_message_sent(server, ~r/"type":\s*"ping"/, 1000)

      # Partial map match (message must contain these keys)
      assert Testing.assert_message_sent(server, %{"type" => "ping"}, 1000)

      # Custom function
      assert Testing.assert_message_sent(server, fn msg ->
        case Jason.decode(msg) do
          {:ok, %{"type" => "ping"}} -> true
          _ -> false
        end
      end, 1000)
  """
  @spec assert_message_sent(server(), term(), pos_integer()) :: boolean()
  def assert_message_sent(server, expected, timeout_ms) do
    Server.assert_message_sent(server, expected, timeout_ms)
  end
end
