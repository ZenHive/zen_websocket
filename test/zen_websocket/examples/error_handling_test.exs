defmodule ZenWebsocket.Examples.ErrorHandlingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenWebsocket.Client
  alias ZenWebsocket.Examples.Docs.ErrorHandling
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @invalid_url "wss://invalid.websocket.test"

  @doc false
  # Polls ErrorHandling GenServer state until client is connected or timeout expires.
  # Returns {:ok, state} on connection, {:timeout, state} on timeout.
  defp wait_for_connection(timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    fn ->
      state = ErrorHandling.get_state()

      cond do
        state.client != nil ->
          {:ok, state}

        System.monotonic_time(:millisecond) > deadline ->
          {:timeout, state}

        true ->
          Process.sleep(50)
          :continue
      end
    end
    |> Stream.repeatedly()
    |> Enum.find(&(&1 != :continue))
  end

  describe "connection error handling" do
    test "handles initial connection failure and retries" do
      log =
        capture_log(fn ->
          {:ok, pid} = ErrorHandling.start_link(@invalid_url)

          # Wait for initial connection failure
          Process.sleep(100)

          # Check state shows not connected
          state = ErrorHandling.get_state()
          assert state.client == nil
          assert state.retry_count == 1

          # Stop the GenServer
          GenServer.stop(pid)
        end)

      assert log =~ "Failed to connect"
    end

    test "successfully connects on first attempt" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        {:ok, pid} = ErrorHandling.start_link(mock_url)

        # Wait for connection with proper timeout
        assert {:ok, state} = wait_for_connection()
        assert %Client{} = state.client
        assert state.retry_count == 0

        GenServer.stop(pid)
      after
        MockWebSockServer.stop(server)
      end
    end

    test "handles send_message when not connected" do
      {:ok, pid} = ErrorHandling.start_link(@invalid_url)

      # Wait for initial connection failure
      Process.sleep(100)

      # Try to send message when not connected
      result = ErrorHandling.send_message("test message")
      assert result == {:error, :not_connected}

      # Clean up
      GenServer.stop(pid)
    end

    test "handles send_message when connected" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        {:ok, pid} = ErrorHandling.start_link(mock_url)

        # Wait for connection with proper timeout
        assert {:ok, _state} = wait_for_connection()

        # Send message when connected - can return :ok or {:ok, response}
        result = ErrorHandling.send_message("test message")
        assert result == :ok or match?({:ok, _}, result)

        GenServer.stop(pid)
      after
        MockWebSockServer.stop(server)
      end
    end
  end

  describe "reconnection patterns" do
    test "automatic reconnection after connection loss" do
      # Start with a connection that will fail
      log =
        capture_log(fn ->
          {:ok, pid} = ErrorHandling.start_link(@invalid_url)

          # Wait for initial failure
          Process.sleep(100)
          assert ErrorHandling.get_state().client == nil

          # Wait for retry attempt (5 seconds + buffer)
          Process.sleep(5500)

          # Check retry count increased
          state = ErrorHandling.get_state()
          assert state.retry_count >= 1

          GenServer.stop(pid)
        end)

      assert log =~ "Failed to connect"
    end
  end

  describe "error message handling" do
    test "handles websocket_error messages" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        log =
          capture_log(fn ->
            {:ok, pid} = ErrorHandling.start_link(mock_url)

            # Wait for connection
            assert {:ok, _state} = wait_for_connection()

            # Send error message directly to the GenServer
            send(pid, {:websocket_error, :connection_timeout})

            Process.sleep(100)

            GenServer.stop(pid)
          end)

        assert log =~ "WebSocket error: :connection_timeout"
      after
        MockWebSockServer.stop(server)
      end
    end

    test "handles websocket_message messages" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        # Configure logger to capture debug messages
        Logger.configure(level: :debug)

        log =
          capture_log(fn ->
            {:ok, pid} = ErrorHandling.start_link(mock_url)

            # Wait for connection
            assert {:ok, _state} = wait_for_connection()

            # Send message directly to the GenServer
            send(pid, {:websocket_message, "test message"})

            Process.sleep(100)

            GenServer.stop(pid)
          end)

        # Reset logger level
        Logger.configure(level: :info)

        assert log =~ "Processing message: \"test message\""
      after
        Logger.configure(level: :info)
        MockWebSockServer.stop(server)
      end
    end
  end

  describe "error resilience patterns" do
    test "maintains state through multiple retry attempts" do
      capture_log(fn ->
        {:ok, pid} = ErrorHandling.start_link(@invalid_url)

        # Check initial state
        state1 = ErrorHandling.get_state()
        assert state1.url == @invalid_url
        assert state1.client == nil

        # Wait for first retry
        Process.sleep(5100)

        state2 = ErrorHandling.get_state()
        assert state2.url == @invalid_url
        assert state2.retry_count > state1.retry_count

        GenServer.stop(pid)
      end)
    end

    test "preserves options through reconnection attempts" do
      opts = [timeout: 1000, headers: [{"custom", "header"}]]

      capture_log(fn ->
        {:ok, pid} = ErrorHandling.start_link(@invalid_url, opts)

        state = ErrorHandling.get_state()
        assert state.opts == opts

        GenServer.stop(pid)
      end)
    end
  end

  describe "connection state management" do
    test "tracks connection state accurately" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        {:ok, pid} = ErrorHandling.start_link(mock_url)

        # Wait for connection with proper timeout
        assert {:ok, state} = wait_for_connection()
        assert %Client{} = state.client
        assert state.retry_count == 0

        # Send a message to ensure connection works - can return :ok or {:ok, response}
        result = ErrorHandling.send_message("ping")
        assert result == :ok or match?({:ok, _}, result)

        GenServer.stop(pid)
      after
        MockWebSockServer.stop(server)
      end
    end

    test "handles rapid message sending" do
      {:ok, server, port} = MockWebSockServer.start_link()

      MockWebSockServer.set_handler(server, fn
        {:text, msg} -> {:reply, {:text, msg}}
        {:binary, data} -> {:reply, {:binary, data}}
      end)

      mock_url = "ws://localhost:#{port}/ws"

      try do
        {:ok, pid} = ErrorHandling.start_link(mock_url)

        # Wait for connection with proper timeout
        assert {:ok, _state} = wait_for_connection()

        # Send multiple messages rapidly - can return :ok or {:ok, response}
        for i <- 1..10 do
          result = ErrorHandling.send_message("message #{i}")
          assert result == :ok or match?({:ok, _}, result)
        end

        GenServer.stop(pid)
      after
        MockWebSockServer.stop(server)
      end
    end
  end

  describe "graceful degradation" do
    test "continues operation despite connection failures" do
      capture_log(fn ->
        {:ok, pid} = ErrorHandling.start_link(@invalid_url)

        # Despite no connection, GenServer stays alive
        Process.sleep(100)
        assert Process.alive?(pid)

        # Can still query state
        state = ErrorHandling.get_state()
        assert state.url == @invalid_url

        # Can attempt to send (will fail gracefully)
        assert {:error, :not_connected} = ErrorHandling.send_message("test")

        GenServer.stop(pid)
      end)
    end
  end
end
