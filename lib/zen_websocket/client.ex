defmodule ZenWebsocket.Client do
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

  ## Public API
  - connect/2 - Establish connection
  - send_message/2 - Send messages
  - subscribe/2 - Subscribe to channels
  - get_state/1 - Get connection state
  - close/1 - Close connection
  - reconnect/1 - Close and re-establish the connection
  - get_heartbeat_health/1, get_state_metrics/1, get_latency_stats/1 - Monitoring
  - build_client_struct/2 - Internal client struct assembly (`@doc false`; ClientSupervisor)

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

  use Descripex, namespace: "/client"
  use GenServer

  alias ZenWebsocket.ClientCallbacks, as: Callbacks
  alias ZenWebsocket.ClientCallFacade, as: CallFacade
  alias ZenWebsocket.ClientConnection, as: Connection
  alias ZenWebsocket.ClientReconnect, as: Reconnect
  alias ZenWebsocket.ClientRecorder, as: RecorderLifecycle
  alias ZenWebsocket.ClientRetry, as: Retry
  alias ZenWebsocket.ErrorHandler
  alias ZenWebsocket.LatencyStats
  alias ZenWebsocket.SafeCallback

  defstruct [:gun_pid, :stream_ref, :state, :url, :monitor_ref, :server_pid, :config, reconnect_opts: []]

  @type t :: %__MODULE__{
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t() | nil,
          monitor_ref: reference() | nil,
          server_pid: pid() | nil,
          config: ZenWebsocket.Config.t() | nil,
          reconnect_opts: keyword()
        }

  @typedoc """
  Tuple shapes delivered to user-provided message handlers.

  See `USAGE_RULES.md` "Handler Message Reference" for semantics and when each
  shape is emitted.
  """
  @type handler_message ::
          {:message, map() | binary()}
          | {:binary, binary()}
          | {:unmatched_response, map()}
          | {:protocol_error, term()}

  @typedoc "Function invoked for each inbound message. Return value is ignored."
  @type handler :: (handler_message() -> any())

  @typedoc "Internal GenServer state for the WebSocket client"
  @type state :: %{
          # Optional fields (added during lifecycle) - must come first
          optional(:retry_count) => non_neg_integer(),
          optional(:awaiting_connection) => GenServer.from(),
          optional(:connection_timer) => reference() | nil,
          optional(:connection_attempt) => reference() | nil,
          optional(:pending_subscription_ops) => %{optional(term()) => :add | :remove},
          # Connection fields
          gun_pid: pid() | nil,
          stream_ref: reference() | nil,
          state: :connecting | :connected | :disconnected,
          url: String.t(),
          monitor_ref: reference() | nil,
          config: ZenWebsocket.Config.t(),
          handler: handler(),
          # Subscription tracking
          subscriptions: MapSet.t(String.t()),
          # Request correlation (from, timeout_ref, start_time)
          pending_requests: %{optional(term()) => {GenServer.from(), reference(), integer()}},
          # Heartbeat tracking
          heartbeat_config: :disabled | map(),
          active_heartbeats: MapSet.t(term()),
          last_heartbeat_at: integer() | nil,
          heartbeat_failures: non_neg_integer(),
          heartbeat_timer: reference() | nil,
          heartbeat_ping_payload: binary() | nil,
          heartbeat_ping_sent_at: integer() | nil,
          # Latency tracking
          connect_start_time: integer() | nil,
          latency_stats: LatencyStats.t(),
          # Session recording
          recorder_pid: pid() | nil,
          # Lifecycle callback (invoked after supervised connect)
          on_connect: (pid() -> any()) | nil,
          # Lifecycle callback (invoked on terminate)
          on_disconnect: (pid() -> any()) | nil,
          # Callback used to recreate the client on explicit reconnect
          reconnector: function() | nil
        }

  # Public API
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

  @spec child_spec(keyword()) :: Supervisor.child_spec()
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

  api(:connect, "Establish a WebSocket connection.",
    params: [
      url_or_config: [kind: :value, description: "WebSocket URL string or Config struct"],
      opts: [kind: :value, description: "Connection options keyword list", default: []]
    ],
    returns: %{type: "{:ok, t()} | {:error, term()}", description: "Client struct or error"},
    errors: [:timeout, :invalid_url, :connection_refused]
  )

  @spec connect(String.t() | ZenWebsocket.Config.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(url_or_config, opts \\ [])

  def connect(url, opts) when is_binary(url) do
    case ZenWebsocket.Config.new(url, opts) do
      {:ok, config} -> connect(config, opts)
      error -> error
    end
  end

  def connect(%ZenWebsocket.Config{} = config, opts) do
    CallFacade.start_client(__MODULE__, config, opts, &build_client_struct/2)
  end

  api(:send_message, "Send a message through the WebSocket connection.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"],
      message: [kind: :value, description: "Message binary to send"]
    ],
    returns: %{type: ":ok | {:ok, map()} | {:error, term()}", description: "Success or error"},
    errors: [:not_connected, :process_down]
  )

  @doc """
  Sends a message through the WebSocket connection.

  Returns `:ok`, `{:ok, response}`, or `{:error, reason}`.

  ## Process-down safety

  Client structs hold the GenServer PID by value. If the server process has
  exited, this function returns `{:error, {:not_connected, :process_down}}`
  instead of crashing the caller, including races where the process dies during
  the `GenServer.call/3`. For pool-level failover across multiple candidates,
  use `ClientSupervisor.send_balanced/2` with the `:client_discovery` option.
  """
  @spec send_message(t(), binary()) :: :ok | {:ok, map()} | {:error, term()}
  def send_message(%__MODULE__{server_pid: server_pid}, message) when is_pid(server_pid) do
    CallFacade.safe_call(server_pid, {:send_message, message}, {:error, {:not_connected, :process_down}})
  end

  def send_message(%__MODULE__{gun_pid: gun_pid, stream_ref: stream_ref, state: :connected}, message) do
    :gun.ws_send(gun_pid, stream_ref, {:text, message})
  end

  def send_message(%__MODULE__{state: state}, _message) do
    {:error, {:not_connected, state}}
  end

  api(:close, "Close the WebSocket connection.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: ":ok", description: "Always succeeds"}
  )

  @spec close(t()) :: :ok
  def close(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    GenServer.stop(server_pid)
    :ok
  catch
    :exit, reason ->
      if CallFacade.process_down_exit?(reason) do
        :ok
      else
        exit(reason)
      end
  end

  def close(%__MODULE__{gun_pid: gun_pid, monitor_ref: monitor_ref}) when is_pid(gun_pid) do
    Process.demonitor(monitor_ref, [:flush])
    :gun.close(gun_pid)
  end

  def close(_client), do: :ok

  api(:subscribe, "Subscribe to WebSocket channels.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"],
      channels: [kind: :value, description: "List of channel names to subscribe to"]
    ],
    returns: %{type: ":ok | {:error, term()}", description: "Success or error"},
    errors: [:not_connected]
  )

  @spec subscribe(t(), list()) :: :ok | {:error, term()}
  def subscribe(client, channels) when is_list(channels) do
    message = Jason.encode!(%{method: "public/subscribe", params: %{channels: channels}})
    send_message(client, message)
  end

  api(:get_state, "Get the current connection state.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: ":connecting | :connected | :disconnected", description: "Current connection state"}
  )

  @doc """
  Returns the current connection state.

  Returns `:disconnected` if the server process is no longer alive (see
  "Process-down safety" in `send_message/2`).
  """
  @spec get_state(t()) :: :connecting | :connected | :disconnected
  def get_state(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    CallFacade.safe_call(server_pid, :get_state, :disconnected)
  end

  def get_state(%__MODULE__{state: state}), do: state

  api(:get_heartbeat_health, "Get heartbeat health status.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: "map() | nil", description: "Heartbeat health map or nil if unavailable"}
  )

  @spec get_heartbeat_health(t()) :: map() | nil
  def get_heartbeat_health(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    CallFacade.safe_call(server_pid, :get_heartbeat_health, nil)
  end

  def get_heartbeat_health(%__MODULE__{}), do: nil

  api(:get_state_metrics, "Get detailed metrics about the client's internal state.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: "map() | nil", description: "Metrics map with sizes, memory, process stats, or nil"}
  )

  @doc """
  Gets detailed metrics about the client's internal state.

  Returns a map containing:
  - Data structure sizes (heartbeats, subscriptions, pending requests)
  - Memory usage information
  - Process statistics

  Returns `nil` if the server process is no longer alive (see
  "Process-down safety" in `send_message/2`).
  """
  @spec get_state_metrics(t()) :: map() | nil
  def get_state_metrics(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    CallFacade.safe_call(server_pid, :get_state_metrics, nil)
  end

  def get_state_metrics(%__MODULE__{}), do: nil

  api(:get_latency_stats, "Get latency statistics for request/response round-trip times.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: "map() | nil", description: "Map with p50, p99, last, count or nil"}
  )

  @doc """
  Gets latency statistics for request/response round-trip times.

  Returns a map with p50, p99, last sample, and count, or nil if no samples yet.
  Returns `nil` if the server process is no longer alive (see
  "Process-down safety" in `send_message/2`).
  """
  @spec get_latency_stats(t()) ::
          %{p50: non_neg_integer(), p99: non_neg_integer(), last: non_neg_integer(), count: non_neg_integer()} | nil
  def get_latency_stats(%__MODULE__{server_pid: server_pid}) when is_pid(server_pid) do
    CallFacade.safe_call(server_pid, :get_latency_stats, nil)
  end

  def get_latency_stats(%__MODULE__{}), do: nil

  api(:reconnect, "Force reconnection by closing and re-establishing the connection.",
    params: [
      client: [kind: :value, description: "Client struct from connect/2"]
    ],
    returns: %{type: "{:ok, t()} | {:error, term()}", description: "New client struct or error"},
    errors: [:timeout, :connection_refused]
  )

  @spec reconnect(t()) :: {:ok, t()} | {:error, term()}
  def reconnect(%__MODULE__{} = client) do
    {target, opts} = Reconnect.reconnect_target(client)
    close(client)

    case Reconnect.reconnect_with(target, opts, &connect/2) do
      {:ok, new_client} ->
        {:ok, new_client}

      {:error, reason} ->
        if ErrorHandler.recoverable?(reason) do
          {:error, {:recoverable, reason}}
        else
          {:error, reason}
        end
    end
  end

  # Public because ClientSupervisor.start_client/2 builds the same returned
  # struct after await_connection/3. Keeping this as the single constructor
  # lets reconnect_opts_from_state/1 stay off the Client public surface.
  @doc false
  @spec build_client_struct(state(), pid()) :: t()
  def build_client_struct(state, server_pid) do
    %__MODULE__{
      gun_pid: state.gun_pid,
      stream_ref: state.stream_ref,
      state: state.state,
      url: state.url,
      monitor_ref: state.monitor_ref,
      server_pid: server_pid,
      config: state.config,
      reconnect_opts: Reconnect.reconnect_opts_from_state(state)
    }
  end

  @impl true
  def init({%ZenWebsocket.Config{} = config, opts}) do
    Process.flag(:trap_exit, true)
    {:ok, Connection.initial_state(config, opts), {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: Connection.continue_connect(state)

  def handle_continue({:connection_failed, reason}, state) do
    Retry.continue_failed(state, reason)
  end

  @doc false
  def handle_continue(:reconnect, state), do: Connection.continue_reconnect(state)

  @impl true
  def handle_call(request, from, state), do: Callbacks.handle_call(request, from, state)

  @impl true
  def handle_info(msg, state), do: Callbacks.handle_info(msg, state)

  @impl true
  def terminate(_reason, state) do
    RecorderLifecycle.maybe_stop(state.recorder_pid)
    SafeCallback.invoke(state.on_disconnect, self())
    :ok
  end
end
