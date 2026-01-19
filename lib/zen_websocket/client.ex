defmodule ZenWebsocket.Client do
  # GenServer.call needs extra time beyond the underlying operation timeout.
  # This buffer accounts for message passing and scheduling overhead.
  @moduledoc """
  WebSocket client GenServer using Gun as transport layer.

  ## Overview

  The Client module is implemented as a GenServer to handle asynchronous Gun messages.
  Gun sends all WebSocket messages to the process that opens the connection, so the
  Client GenServer owns the Gun connection to receive these messages directly.

  ## Public API

  Despite being a GenServer internally, the public API returns struct-based responses
  for backward compatibility:

      {:ok, client} = Client.connect("wss://example.com")
      # client is a struct with gun_pid, stream_ref, and server_pid fields
      
      :ok = Client.send_message(client, "hello")
      Client.close(client)

  ## Connection Ownership and Reconnection

  ### Initial Connection
  When you call `connect/2`, a new Client GenServer is started which:
  1. Opens a Gun connection from within the GenServer 
  2. Receives all Gun messages (gun_ws, gun_up, gun_down, etc.)
  3. Returns a client struct containing the GenServer PID

  ### Automatic Reconnection
  On connection failure, the Client GenServer:
  1. Detects the failure via process monitoring
  2. Cleans up the old Gun connection
  3. Opens a new Gun connection from the same GenServer process
  4. Maintains Gun message ownership continuity
  5. Preserves the same Client GenServer PID throughout

  This ensures that integrated heartbeat functionality continues to work seamlessly
  across reconnections without needing to track connection changes.

  The Client GenServer handles all reconnection logic internally to maintain
  Gun message ownership throughout the connection lifecycle.

  ## Core Functions
  - connect/2 - Establish connection
  - send_message/2 - Send messages  
  - close/1 - Close connection
  - subscribe/2 - Subscribe to channels
  - get_state/1 - Get connection state

  ## Configuration Options

  The `connect/2` function accepts all options from `ZenWebsocket.Config`:

      # Customize reconnection behavior
      {:ok, client} = Client.connect("wss://example.com",
        retry_count: 5,              # Try reconnecting 5 times
        retry_delay: 2000,           # Start with 2 second delay
        max_backoff: 60_000,         # Cap backoff at 1 minute
        reconnect_on_error: true     # Auto-reconnect on errors
      )

      # Disable auto-reconnection for critical operations
      {:ok, client} = Client.connect("wss://example.com",
        reconnect_on_error: false
      )

  See `ZenWebsocket.Config` for all available options.
  """

  use GenServer

  alias ZenWebsocket.Debug
  alias ZenWebsocket.HeartbeatManager

  require Logger

  @genserver_call_buffer_ms 100

  # Minimum timeout ensures connection attempts have reasonable time,
  # even if user specifies a very short timeout.
  @minimum_connection_timeout_ms 1000

  defstruct [:gun_pid, :stream_ref, :state, :url, :monitor_ref, :server_pid]

  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil,
          server_pid: pid() | nil
        }

  @type state :: %{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil
        }

  @doc """
  Returns a child specification for starting a Client under a supervisor.

  ## Examples

      # In your application's supervision tree
      children = [
        {ZenWebsocket.Client, url: "wss://example.com", id: :my_client},
        # Or with full configuration
        {ZenWebsocket.Client, [
          url: "wss://example.com",
          heartbeat_config: %{type: :deribit, interval: 30_000},
          retry_count: 10
        ]}
      ]
      
      Supervisor.start_link(children, strategy: :one_for_one)
  """
  def child_spec(opts) do
    url = Keyword.fetch!(opts, :url)
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [url, opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Public API

  @doc """
  Starts a Client GenServer under a supervisor.

  This function is designed to be called by a supervisor. For direct usage,
  prefer `connect/2` which provides better error handling and connection
  establishment feedback.
  """
  @spec start_link(String.t() | ZenWebsocket.Config.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_link(url_or_config, opts \\ []) do
    config =
      case url_or_config do
        url when is_binary(url) ->
          case ZenWebsocket.Config.new(url, opts) do
            {:ok, config} -> config
            {:error, reason} -> {:error, reason}
          end

        %ZenWebsocket.Config{} = config ->
          config
      end

    case config do
      {:error, reason} ->
        {:error, reason}

      %ZenWebsocket.Config{} = valid_config ->
        GenServer.start_link(__MODULE__, {valid_config, opts})
    end
  end

  @spec connect(String.t() | ZenWebsocket.Config.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url_or_config, opts \\ [])

  def connect(url, opts) when is_binary(url) do
    case ZenWebsocket.Config.new(url, opts) do
      {:ok, config} -> connect(config, opts)
      error -> error
    end
  end

  def connect(%ZenWebsocket.Config{} = config, opts) do
    # Capture calling process PID for default handler
    parent_pid = self()

    # Create default handler that sends messages to parent process if none provided
    opts_with_handler =
      if Keyword.has_key?(opts, :handler) do
        opts
      else
        default_handler = fn
          {:message, {:text, data}} -> send(parent_pid, {:websocket_message, data})
          {:message, {:binary, data}} -> send(parent_pid, {:websocket_message, data})
          {:message, data} when is_binary(data) -> send(parent_pid, {:websocket_message, data})
          {:binary, data} -> send(parent_pid, {:websocket_message, data})
          {:frame, frame} -> send(parent_pid, {:websocket_frame, frame})
          _other -> :ok
        end

        Keyword.put(opts, :handler, default_handler)
      end

    case GenServer.start(__MODULE__, {config, opts_with_handler}) do
      {:ok, server_pid} ->
        # Add a bit more time for GenServer overhead
        timeout = max(config.timeout + @genserver_call_buffer_ms, @minimum_connection_timeout_ms)

        try do
          case GenServer.call(server_pid, :await_connection, timeout) do
            {:ok, state} ->
              {:ok, build_client_struct(state, server_pid)}

            {:error, reason} ->
              GenServer.stop(server_pid)
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            GenServer.stop(server_pid)
            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec send_message(t(), binary()) :: :ok | {:ok, map()} | {:error, term()}
  def send_message(%__MODULE__{server_pid: server_pid}, message) when is_pid(server_pid) do
    GenServer.call(server_pid, {:send_message, message})
  end

  def send_message(%__MODULE__{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected}, message) do
    :gun.ws_send(gun_pid, stream_ref, {:text, message})
  end

  def send_message(%__MODULE__{state: state}, _message) do
    {:error, {:not_connected, state}}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    if Process.alive?(server_pid) do
      GenServer.stop(server_pid)
    end

    :ok
  end

  def close(%__MODULE__{gun_pid: gun_pid, monitor_ref: monitor_ref}) when is_pid(gun_pid) do
    Process.demonitor(monitor_ref, [:flush])
    :gun.close(gun_pid)
  end

  def close(_client), do: :ok

  @spec subscribe(t(), list()) :: :ok | {:error, term()}
  def subscribe(client, channels) when is_list(channels) do
    message = Jason.encode!(%{method: "public/subscribe", params: %{channels: channels}})
    send_message(client, message)
  end

  @spec get_state(t()) :: :connecting | :connected | :disconnected
  def get_state(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    GenServer.call(server_pid, :get_state)
  end

  def get_state(%__MODULE__{state: state}), do: state

  @spec get_heartbeat_health(t()) :: map() | nil
  def get_heartbeat_health(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    GenServer.call(server_pid, :get_heartbeat_health)
  end

  def get_heartbeat_health(%__MODULE__{}), do: nil

  @doc """
  Gets detailed metrics about the client's internal state.

  Returns a map containing:
  - Data structure sizes (heartbeats, subscriptions, pending requests)
  - Memory usage information
  - Process statistics
  """
  @spec get_state_metrics(t()) :: map() | nil
  def get_state_metrics(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    GenServer.call(server_pid, :get_state_metrics)
  end

  def get_state_metrics(%__MODULE__{}), do: nil

  @spec reconnect(t()) :: {:ok, t()} | {:error, term()}
  def reconnect(%__MODULE__{url: url} = client) do
    close(client)

    case connect(url) do
      {:ok, new_client} ->
        {:ok, new_client}

      {:error, reason} ->
        if ZenWebsocket.ErrorHandler.recoverable?(reason) do
          {:error, {:recoverable, reason}}
        else
          {:error, reason}
        end
    end
  end

  # GenServer callbacks

  @impl true
  def init({%ZenWebsocket.Config{} = config, opts}) do
    # Setup message handler callback
    handler = Keyword.get(opts, :handler, &ZenWebsocket.MessageHandler.default_handler/1)

    # Setup heartbeat configuration
    heartbeat_config = Keyword.get(opts, :heartbeat_config, :disabled)

    initial_state = %{
      config: config,
      gun_pid: nil,
      stream_ref: nil,
      state: :disconnected,
      monitor_ref: nil,
      url: config.url,
      handler: handler,
      subscriptions: MapSet.new(),
      pending_requests: %{},
      # Heartbeat tracking
      heartbeat_config: heartbeat_config,
      active_heartbeats: MapSet.new(),
      last_heartbeat_at: nil,
      heartbeat_failures: 0,
      heartbeat_timer: nil
    }

    {:ok, initial_state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, %{config: config} = state) do
    Debug.log(state, "🔌 [GUN CONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🌐 URL: #{config.url}")
    Debug.log(state, "   ⏱️  Timeout: #{config.timeout}ms")
    Debug.log(state, "   🔄 Establishing connection...")

    case ZenWebsocket.Reconnection.establish_connection(config) do
      {:ok, gun_pid, stream_ref, monitor_ref} ->
        Debug.log(state, "   ✅ Gun connection established")
        Debug.log(state, "   🔧 Gun PID: #{inspect(gun_pid)}")
        Debug.log(state, "   📡 Stream Ref: #{inspect(stream_ref)}")
        Debug.log(state, "   👁️  Monitor Ref: #{inspect(monitor_ref)}")
        Debug.log(state, "   🔄 State: :disconnected → :connecting")
        Debug.log(state, "   ⏰ Timeout scheduled: #{config.timeout}ms")

        # Gun will send all messages to this GenServer process (self())
        # because we opened the connection from this process

        # Schedule timeout check
        Process.send_after(self(), {:connection_timeout, config.timeout}, config.timeout)
        {:noreply, %{state | gun_pid: gun_pid, stream_ref: stream_ref, state: :connecting, monitor_ref: monitor_ref}}

      {:error, reason} ->
        Debug.log(state, "   ❌ Gun connection failed: #{inspect(reason)}")
        Debug.log(state, "   🔄 State: → :disconnected")
        {:noreply, %{state | state: :disconnected}, {:continue, {:connection_failed, reason}}}
    end
  end

  def handle_continue({:connection_failed, _reason}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_continue(:reconnect, %{config: config} = state) do
    current_attempt = Map.get(state, :retry_count, 0)

    Debug.log(state, "🔄 [GUN RECONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🔢 Attempt: #{current_attempt + 1}")
    Debug.log(state, "   🌐 URL: #{config.url}")
    Debug.log(state, "   🔄 Re-establishing connection...")

    # Reconnect from within the GenServer to maintain Gun ownership
    # This ensures the new Gun connection sends messages to this GenServer
    case ZenWebsocket.Reconnection.establish_connection(config) do
      {:ok, gun_pid, stream_ref, monitor_ref} ->
        Debug.log(state, "   ✅ Gun reconnection successful")
        Debug.log(state, "   🔧 New Gun PID: #{inspect(gun_pid)}")
        Debug.log(state, "   📡 New Stream Ref: #{inspect(stream_ref)}")
        Debug.log(state, "   👁️  New Monitor Ref: #{inspect(monitor_ref)}")
        Debug.log(state, "   🔄 State: :disconnected → :connecting")
        Debug.log(state, "   ⏰ Timeout scheduled: #{config.timeout}ms")

        # New Gun connection will send messages to this GenServer
        Process.send_after(self(), {:connection_timeout, config.timeout}, config.timeout)
        {:noreply, %{state | gun_pid: gun_pid, stream_ref: stream_ref, state: :connecting, monitor_ref: monitor_ref}}

      {:error, reason} ->
        Debug.log(state, "   ❌ Gun reconnection failed: #{inspect(reason)}")

        # Schedule retry with exponential backoff
        retry_delay =
          ZenWebsocket.Reconnection.calculate_backoff(
            current_attempt,
            config.retry_delay,
            config.max_backoff
          )

        Debug.log(state, "   ⏳ Scheduling retry in #{retry_delay}ms (attempt #{current_attempt + 1})")
        Process.send_after(self(), :retry_reconnect, retry_delay)
        {:noreply, %{state | state: :disconnected, retry_count: current_attempt + 1}}
    end
  end

  @impl true
  def handle_call(:await_connection, _from, %{state: :connected} = state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:await_connection, from, %{state: :connecting} = state) do
    {:noreply, Map.put(state, :awaiting_connection, from)}
  end

  def handle_call(:await_connection, _from, state) do
    {:reply, {:error, :connection_failed}, state}
  end

  def handle_call({:send_message, message}, from, %{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected} = state) do
    # Check if message has an ID for correlation
    case Jason.decode(message) do
      {:ok, %{"id" => id} = _decoded} when not is_nil(id) ->
        # Track this request for correlation
        timeout = state.config.request_timeout
        timeout_ref = Process.send_after(self(), {:correlation_timeout, id}, timeout)

        pending = Map.put(state.pending_requests, id, {from, timeout_ref})

        # Send message but don't reply yet - will reply when response arrives
        :gun.ws_send(gun_pid, stream_ref, {:text, message})

        {:noreply, %{state | pending_requests: pending}}

      _ ->
        # No ID or not JSON - send without correlation
        result = :gun.ws_send(gun_pid, stream_ref, {:text, message})
        {:reply, result, state}
    end
  end

  def handle_call({:send_message, _message}, _from, %{state: conn_state} = state) do
    {:reply, {:error, {:not_connected, conn_state}}, state}
  end

  def handle_call(:get_state, _from, %{state: conn_state} = state) do
    {:reply, conn_state, state}
  end

  def handle_call(:get_state_internal, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_heartbeat_health, _from, state) do
    {:reply, HeartbeatManager.get_health(state), state}
  end

  def handle_call(:get_state_metrics, _from, state) do
    metrics = %{
      # Connection state
      connection_state: Map.get(state, :state, :unknown),

      # Data structure sizes
      active_heartbeats_size: MapSet.size(Map.get(state, :active_heartbeats, MapSet.new())),
      subscriptions_size: MapSet.size(Map.get(state, :subscriptions, MapSet.new())),
      pending_requests_size: map_size(Map.get(state, :pending_requests, %{})),

      # Memory usage estimates
      state_memory: :erts_debug.size(state),

      # Heartbeat tracking
      heartbeat_failures: Map.get(state, :heartbeat_failures, 0),
      last_heartbeat_at: Map.get(state, :last_heartbeat_at),
      heartbeat_timer_active: Map.get(state, :heartbeat_timer) != nil,

      # Process info
      message_queue_len: self() |> Process.info(:message_queue_len) |> elem(1),
      memory: self() |> Process.info(:memory) |> elem(1),
      reductions: self() |> Process.info(:reductions) |> elem(1)
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_info(
        {:gun_upgrade, gun_pid, stream_ref, ["websocket"], headers},
        %{gun_pid: gun_pid, stream_ref: stream_ref} = state
      ) do
    Debug.log(state, "🔗 [GUN UPGRADE] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   ✅ WebSocket connection upgraded successfully")
    Debug.log(state, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(state, "   📋 Headers: #{inspect(headers, pretty: true)}")

    # Start heartbeat timer if configured
    new_state = HeartbeatManager.start_timer(%{state | state: :connected})

    Debug.log(state, "   🔄 State: :connecting → :connected")

    if Map.get(state, :heartbeat_config) != :disabled do
      Debug.log(state, "   💓 Heartbeat timer started")
    end

    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:ok, new_state})
      {:noreply, Map.delete(new_state, :awaiting_connection)}
    else
      {:noreply, new_state}
    end
  end

  def handle_info({:gun_error, gun_pid, stream_ref, reason}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    Debug.log(state, "❌ [GUN ERROR] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(state, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state, "   🔄 Triggering connection error handling...")

    handle_connection_error(state, {:gun_error, gun_pid, stream_ref, reason})
  end

  def handle_info({:gun_down, gun_pid, protocol, reason, killed_streams}, %{gun_pid: gun_pid} = state) do
    Debug.log(state, "📉 [GUN DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state, "   🌐 Protocol: #{inspect(protocol)}")
    Debug.log(state, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state, "   🚫 Killed Streams: #{inspect(killed_streams)}")
    Debug.log(state, "   🔄 Connection lost, triggering error handling...")

    handle_connection_error(state, {:gun_down, gun_pid, protocol, reason, killed_streams})
  end

  def handle_info({:DOWN, ref, :process, gun_pid, reason}, %{gun_pid: gun_pid, monitor_ref: ref} = state) do
    Debug.log(state, "💀 [PROCESS DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🔧 Gun PID: #{inspect(gun_pid)} (monitored process)")
    Debug.log(state, "   📍 Monitor Ref: #{inspect(ref)}")
    Debug.log(state, "   💥 Exit Reason: #{inspect(reason)}")
    Debug.log(state, "   🔄 Process terminated, triggering connection error handling...")

    handle_connection_error(state, {:connection_down, reason})
  end

  def handle_info({:gun_ws, gun_pid, stream_ref, frame}, %{gun_pid: gun_pid, stream_ref: stream_ref} = state) do
    # Log WebSocket frame details
    case frame do
      {:text, _} ->
        Debug.log(state, "📨 [GUN WS TEXT] #{DateTime.to_string(DateTime.utc_now())}")

      {:binary, data} ->
        Debug.log(state, "📦 [GUN WS BINARY] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state, "   📏 Size: #{byte_size(data)} bytes")

      {:ping, payload} ->
        Debug.log(state, "🏓 [GUN WS PING] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state, "   📦 Payload: #{inspect(payload)}")

      {:pong, payload} ->
        Debug.log(state, "🏓 [GUN WS PONG] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state, "   📦 Payload: #{inspect(payload)}")

      {:close, code, reason} ->
        Debug.log(state, "🔒 [GUN WS CLOSE] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state, "   🔢 Code: #{code}")
        Debug.log(state, "   📝 Reason: #{inspect(reason)}")

      other ->
        Debug.log(state, "❓ [GUN WS OTHER] #{DateTime.to_string(DateTime.utc_now())}")
        Debug.log(state, "   🔍 Frame: #{inspect(other)}")
    end

    # Route WebSocket frames through MessageHandler
    case ZenWebsocket.MessageHandler.handle_message({:gun_ws, gun_pid, stream_ref, frame}, state.handler) do
      {:ok, {:message, decoded_frame}} ->
        # Data frame - route to subscriptions, heartbeat manager, etc.
        new_state = route_data_frame(decoded_frame, state)
        {:noreply, new_state}

      {:ok, :control_frame_handled} ->
        # Control frame already handled (ping/pong)
        {:noreply, state}

      {:error, reason} ->
        # Frame decode error
        handle_frame_error(state, reason)
    end
  end

  def handle_info({:connection_timeout, timeout}, %{state: :connecting} = state) do
    Debug.log(state, "⏰ [CONNECTION TIMEOUT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   ⏱️  Timeout: #{timeout}ms")
    Debug.log(state, "   🔄 State: :connecting (timeout)")
    Debug.log(state, "   🔄 Triggering connection error handling...")

    handle_connection_error(state, :timeout)
  end

  def handle_info({:connection_timeout, _}, state) do
    # Connection already established, ignore timeout
    {:noreply, state}
  end

  @doc false
  # Handles scheduled reconnection retry with exponential backoff
  def handle_info(:retry_reconnect, %{config: config} = state) do
    current_retries = Map.get(state, :retry_count, 0)

    Debug.log(state, "🔄 [RETRY RECONNECT] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state, "   🔢 Current Retries: #{current_retries}")
    Debug.log(state, "   🔢 Max Retries: #{config.retry_count}")

    if ZenWebsocket.Reconnection.max_retries_exceeded?(current_retries, config.retry_count) do
      Debug.log(state, "   🚫 Max reconnection attempts exceeded")
      Debug.log(state, "   🛑 Stopping GenServer with reason: :max_reconnection_attempts")
      {:stop, :max_reconnection_attempts, state}
    else
      Debug.log(state, "   ✅ Retries within limit, attempting reconnection...")
      {:noreply, state, {:continue, :reconnect}}
    end
  end

  @doc false
  # Handles periodic heartbeat sending
  def handle_info(:send_heartbeat, %{state: :connected, heartbeat_config: config} = state) when is_map(config) do
    new_state = HeartbeatManager.send_heartbeat(state)

    # Schedule next heartbeat
    interval = Map.get(config, :interval, state.config.heartbeat_interval)
    timer_ref = Process.send_after(self(), :send_heartbeat, interval)

    {:noreply, %{new_state | heartbeat_timer: timer_ref}}
  end

  def handle_info(:send_heartbeat, state) do
    # Not connected or heartbeat disabled
    {:noreply, state}
  end

  def handle_info({:correlation_timeout, request_id}, state) do
    # Handle correlation timeout
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        # Already handled
        {:noreply, state}

      {{from, _timeout_ref}, new_pending} ->
        # Reply with timeout error
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  # Handles connection errors and triggers internal reconnection when appropriate.
  # This maintains Gun ownership by reconnecting from within the same GenServer.
  @spec handle_connection_error(map(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  defp handle_connection_error(state, reason) do
    if Map.has_key?(state, :awaiting_connection) do
      GenServer.reply(state.awaiting_connection, {:error, reason})
    end

    if state.config.reconnect_on_error && ZenWebsocket.Reconnection.should_reconnect?(reason) do
      # Clean up old connection
      if state.monitor_ref do
        Process.demonitor(state.monitor_ref, [:flush])
      end

      # Cancel heartbeat timer and reset state
      state_after_heartbeat = HeartbeatManager.cancel_timer(state)

      # Trigger reconnection from this GenServer to maintain ownership
      new_state = %{
        state_after_heartbeat
        | gun_pid: nil,
          stream_ref: nil,
          state: :disconnected,
          monitor_ref: nil
      }

      {:noreply, Map.delete(new_state, :awaiting_connection), {:continue, :reconnect}}
    else
      {:stop, reason, state}
    end
  end

  @spec build_client_struct(state(), pid()) :: t()
  defp build_client_struct(state, server_pid) do
    %__MODULE__{
      gun_pid: state.gun_pid,
      stream_ref: state.stream_ref,
      state: state.state,
      url: state.url,
      monitor_ref: state.monitor_ref,
      server_pid: server_pid
    }
  end

  # Routes data frames to appropriate handlers based on content
  @spec route_data_frame(term(), state()) :: state()
  defp route_data_frame(frame, state) do
    case frame do
      {:text, json_data} ->
        # Parse JSON and route based on message type
        case Jason.decode(json_data) do
          {:ok, %{"method" => "heartbeat"} = msg} ->
            # Handle heartbeat directly
            Debug.log(state, "💓 [HEARTBEAT DETECTED] #{DateTime.to_string(DateTime.utc_now())}")
            Debug.log(state, "   Heartbeat message: #{inspect(msg, pretty: true)}")
            HeartbeatManager.handle_message(msg, state)

          {:ok, %{"method" => "subscription"} = msg} ->
            # Handle subscription confirmation
            handle_subscription_message(msg, state)

          {:ok, %{"id" => id} = msg} when is_integer(id) or is_binary(id) ->
            # JSON-RPC response - route to pending request
            handle_rpc_response(msg, state)

          {:ok, msg} ->
            # General message - forward to handler
            state.handler.({:message, msg})
            state

          {:error, _} ->
            # Non-JSON text frame
            state.handler.({:message, json_data})
            state
        end

      {:binary, data} ->
        # Binary frame
        state.handler.({:binary, data})
        state

      other ->
        # Other frame types
        state.handler.({:frame, other})
        state
    end
  end

  # Handles subscription-related messages
  @spec handle_subscription_message(map(), state()) :: state()
  defp handle_subscription_message(%{"params" => %{"channel" => channel}}, state) do
    new_subscriptions = MapSet.put(state.subscriptions, channel)
    %{state | subscriptions: new_subscriptions}
  end

  defp handle_subscription_message(_msg, state), do: state

  # Routes JSON-RPC responses to waiting callers
  @spec handle_rpc_response(map(), state()) :: state()
  defp handle_rpc_response(%{"id" => id} = response, state) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        # No pending request for this ID
        state.handler.({:unmatched_response, response})
        state

      {{from, timeout_ref}, new_pending} ->
        # Cancel timeout and reply to waiting caller
        Process.cancel_timer(timeout_ref)
        GenServer.reply(from, {:ok, response})
        %{state | pending_requests: new_pending}
    end
  end

  # Handles frame decode errors
  @spec handle_frame_error(state(), term()) :: {:noreply, state()} | {:stop, term(), state()}
  defp handle_frame_error(state, {:protocol_error, _} = error) do
    # Serious protocol error - stop the connection
    {:stop, error, state}
  end

  defp handle_frame_error(state, error) do
    # Other errors - log and continue
    state.handler.({:frame_error, error})
    {:noreply, state}
  end
end
