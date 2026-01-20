defmodule ZenWebsocket.Testing.Server do
  @moduledoc false
  # Internal implementation for Testing module.
  # Wraps MockWebSockServer and adds message capture for assertions.
  #
  # Uses dynamic function calls to avoid compile-time warnings since
  # MockWebSockServer is only available in test environment.

  # credo:disable-for-this-file Credo.Check.Refactor.Apply
  # ^ Intentional: MockWebSockServer is only compiled in test env,
  #   so we use apply/3 to avoid compile-time module not found warnings.

  @default_path "/ws"
  @mock_server_module ZenWebsocket.Test.Support.MockWebSockServer

  # Maximum messages to keep in capture buffer. Prevents unbounded memory growth
  # during long-running tests. Oldest messages are dropped when limit is reached.
  @max_captured_messages 1000

  # Polling interval for assert_message_sent/3 to check for matching messages
  @poll_interval_ms 10

  @doc false
  @spec start(keyword()) :: {:ok, map()} | {:error, term()}
  def start(opts) do
    # Check if MockWebSockServer is available
    if Code.ensure_loaded?(@mock_server_module) do
      do_start(opts)
    else
      mock_server_unavailable_error()
    end
  end

  defp do_start(opts) do
    # Start message capture agent
    {:ok, message_agent} = Agent.start_link(fn -> [] end)

    # Create a handler that captures all received messages
    capture_handler = build_capture_handler(message_agent, Keyword.get(opts, :handler))

    # Start the mock server (dynamic call to avoid compile warnings)
    server_opts = Keyword.put(opts, :handler, nil)

    case apply(@mock_server_module, :start_link, [server_opts]) do
      {:ok, pid, port} ->
        # Set the capture handler
        apply(@mock_server_module, :set_handler, [pid, capture_handler])

        protocol = Keyword.get(opts, :protocol, :http)
        scheme = if protocol == :tls, do: "wss", else: "ws"

        server = %{
          pid: pid,
          port: port,
          url: "#{scheme}://localhost:#{port}#{@default_path}",
          message_agent: message_agent
        }

        {:ok, server}

      {:error, reason} ->
        Agent.stop(message_agent)
        {:error, reason}
    end
  end

  @doc false
  @spec stop(map()) :: :ok
  def stop(%{pid: pid, message_agent: message_agent}) do
    # Stop the mock server (dynamic call)
    if Process.alive?(pid) do
      apply(@mock_server_module, :stop, [pid])
    end

    # Stop the message agent
    if Process.alive?(message_agent) do
      Agent.stop(message_agent)
    end

    :ok
  end

  @doc false
  @spec simulate_disconnect(map(), term()) :: :ok
  def simulate_disconnect(%{pid: pid}, reason) do
    close_code = reason_to_code(reason)
    close_reason = reason_to_string(reason)

    # Set a handler that sends close frame to all connections
    apply(@mock_server_module, :set_handler, [
      pid,
      fn _frame -> {:reply, {:close, close_code, close_reason}} end
    ])

    # Get all connections and send close to each
    connections = apply(@mock_server_module, :get_connections, [pid])

    Enum.each(connections, fn {_ref, ws_pid} ->
      if Process.alive?(ws_pid) do
        # Send close frame directly via websocket_info callback
        send(ws_pid, {:trigger_close, close_code, close_reason})
      end
    end)

    :ok
  end

  @doc false
  @spec inject_message(map(), binary()) :: :ok
  def inject_message(%{pid: pid}, message) do
    connections = apply(@mock_server_module, :get_connections, [pid])

    Enum.each(connections, fn {_ref, ws_pid} ->
      if Process.alive?(ws_pid) do
        # Send text frame directly via websocket_info callback
        send(ws_pid, {:send_text, message})
      end
    end)

    :ok
  end

  @doc false
  @spec assert_message_sent(map(), term(), pos_integer()) :: boolean()
  def assert_message_sent(%{message_agent: agent}, expected, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_for_message(agent, expected, deadline)
  end

  # Private helpers

  @doc false
  # Builds a handler that captures frames to the agent before delegating to custom handler
  defp build_capture_handler(agent, custom_handler) do
    fn frame ->
      capture_frame(agent, frame)

      # Call custom handler if provided, otherwise use default behavior
      if custom_handler do
        custom_handler.(frame)
      else
        default_handler(frame)
      end
    end
  end

  # Stores text frame data in the capture agent, limiting to max buffer size
  defp capture_frame(agent, {:text, data}) do
    Agent.update(agent, &Enum.take([data | &1], @max_captured_messages))
  end

  # Stores binary frame data (tagged) in the capture agent
  defp capture_frame(agent, {:binary, data}) do
    Agent.update(agent, &Enum.take([{:binary, data} | &1], @max_captured_messages))
  end

  # Ignores other frame types (ping, pong, close)
  defp capture_frame(_agent, _frame), do: :ok

  # Default echo handler for frames when no custom handler is provided
  defp default_handler(frame) do
    case frame do
      {:text, "ping"} -> {:reply, {:text, "pong"}}
      {:text, msg} -> {:reply, {:text, "echo: #{msg}"}}
      {:binary, data} -> {:reply, {:binary, data}}
      _ -> :ok
    end
  end

  # Polls the message agent until a matching message is found or deadline expires
  defp poll_for_message(agent, expected, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      false
    else
      messages = Agent.get(agent, & &1)

      if Enum.any?(messages, &message_matches?(&1, expected)) do
        true
      else
        Process.sleep(@poll_interval_ms)
        poll_for_message(agent, expected, deadline)
      end
    end
  end

  # Exact string match
  defp message_matches?(message, expected) when is_binary(expected) do
    message == expected
  end

  # Regex pattern match
  defp message_matches?(message, %Regex{} = expected) when is_binary(message) do
    Regex.match?(expected, message)
  end

  # Partial JSON map match - decoded message must contain all expected keys/values
  defp message_matches?(message, expected) when is_map(expected) and is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} when is_map(decoded) ->
        Enum.all?(expected, fn {key, value} ->
          Map.get(decoded, key) == value
        end)

      _ ->
        false
    end
  end

  # Custom function matcher
  defp message_matches?(message, expected) when is_function(expected, 1) do
    expected.(message)
  end

  # Fallback - no match
  defp message_matches?(_message, _expected), do: false

  # Converts disconnect reason atoms to WebSocket close codes
  defp reason_to_code(:normal), do: 1000
  defp reason_to_code(:going_away), do: 1001
  defp reason_to_code({:code, code}) when is_integer(code), do: code
  defp reason_to_code(_), do: 1000

  # Converts disconnect reason atoms to human-readable strings
  defp reason_to_string(:normal), do: "Normal closure"
  defp reason_to_string(:going_away), do: "Server going away"
  defp reason_to_string({:code, _}), do: "Custom close"
  defp reason_to_string(_), do: "Unknown"

  # Returns descriptive error when MockWebSockServer is not available
  defp mock_server_unavailable_error do
    {:error,
     {:mock_server_unavailable,
      "MockWebSockServer is not available. " <>
        "The Testing module requires the test support modules to be compiled. " <>
        "Make sure you're running in a test environment or have test support loaded."}}
  end
end
