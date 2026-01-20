defmodule ZenWebsocket.ClientSupervisor do
  @moduledoc """
  Optional supervisor for WebSocket client connections.

  Provides supervised client connections with automatic restart on failure.
  Each client runs under its own supervisor for isolation.

  ## Restart Policy

  Allows up to 10 restarts within 60 seconds. This prevents rapid restart loops
  while allowing recovery from transient failures.

  ## Adding to Your Supervision Tree

      # In your application supervisor
      children = [
        # Start the ClientSupervisor
        ZenWebsocket.ClientSupervisor,
        # Your other children...
      ]
      
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Usage

      # After supervisor is started, create supervised connections
      {:ok, client} = ClientSupervisor.start_client("wss://example.com", 
        retry_count: 5,
        heartbeat_config: %{type: :deribit, interval: 30_000}
      )
      
      # The client will be automatically restarted on crashes
      # with exponential backoff between restarts
  """

  use DynamicSupervisor

  @max_restarts 10
  @restart_window_seconds 60

  # Extra time buffer for DynamicSupervisor child startup overhead
  # beyond the client's own connection timeout.
  @supervision_buffer_ms 1000

  @doc """
  Starts the client supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: @max_restarts,
      max_seconds: @restart_window_seconds
    )
  end

  @doc """
  Starts a supervised WebSocket client.

  The client will be automatically restarted on failure according to the
  supervisor's restart strategy.

  ## Lifecycle Callbacks

  - `:on_connect` - Called with the client PID after successful connection.
    Use to register the client with external registries (`:pg`, `Horde`, etc.).
  - `:on_disconnect` - Called with the client PID when the client terminates.
    Use to unregister from external registries.

  ## Examples

      # Basic usage
      {:ok, client} = ClientSupervisor.start_client("wss://example.com")

      # With lifecycle callbacks for distributed registry
      {:ok, client} = ClientSupervisor.start_client("wss://example.com",
        on_connect: fn pid -> :pg.join(:ws_pool, pid) end,
        on_disconnect: fn pid -> :pg.leave(:ws_pool, pid) end
      )
  """
  @spec start_client(String.t() | ZenWebsocket.Config.t(), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def start_client(url_or_config, opts \\ []) do
    # Extract lifecycle callbacks
    on_connect = Keyword.get(opts, :on_connect)

    # Add supervision flag to opts (on_disconnect is passed through to Client)
    supervised_opts = Keyword.put(opts, :supervised, true)

    child_spec = %{
      id: make_ref(),
      start: {ZenWebsocket.Client, :start_link, [url_or_config, supervised_opts]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} when is_pid(pid) ->
        timeout = Keyword.get(opts, :timeout, 5000) + @supervision_buffer_ms
        await_connection(pid, timeout, on_connect)

      error ->
        error
    end
  end

  # Waits for a supervised client to establish connection and returns the client struct.
  # Terminates the child process on connection failure or timeout.
  # Invokes on_connect callback after successful connection.
  @doc false
  defp await_connection(pid, timeout, on_connect) do
    case GenServer.call(pid, :await_connection, timeout) do
      {:ok, state} ->
        maybe_invoke_callback(on_connect, pid)
        {:ok, build_client_struct(pid, state)}

      {:error, reason} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        {:error, reason}
    end
  catch
    :exit, {:timeout, _} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
      {:error, :timeout}
  end

  # Safely invokes a lifecycle callback, catching and logging any errors.
  @doc false
  defp maybe_invoke_callback(nil, _pid), do: :ok

  defp maybe_invoke_callback(callback, pid) when is_function(callback, 1) do
    callback.(pid)
    :ok
  rescue
    error ->
      require Logger

      Logger.warning("Lifecycle callback error: #{inspect(error)}")
      :ok
  end

  # Builds a Client struct from the GenServer state after successful connection.
  @doc false
  defp build_client_struct(pid, state) do
    %ZenWebsocket.Client{
      gun_pid: state.gun_pid,
      stream_ref: state.stream_ref,
      state: state.state,
      url: state.url,
      monitor_ref: state.monitor_ref,
      server_pid: pid
    }
  end

  @doc """
  Lists all supervised client connections.
  """
  @spec list_clients() :: list(pid())
  def list_clients do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&Process.alive?/1)
  end

  @doc """
  Gracefully stops a supervised client.
  """
  @spec stop_client(pid()) :: :ok | {:error, :not_found}
  def stop_client(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @typedoc "Function that returns a list of client PIDs for load balancing"
  @type discovery_fun :: (-> [pid()])

  @typedoc "Callback invoked on client lifecycle events"
  @type lifecycle_callback :: (pid() -> any())

  @doc """
  Sends a message using health-based load balancing.

  Selects the healthiest connection from the pool and sends the message.
  On failure, records the error and attempts failover to the next healthiest
  connection.

  ## Options

  - `:max_attempts` - Maximum failover attempts (default: 3)
  - `:client_discovery` - Function returning list of PIDs (default: `list_clients/0`)

  ## Examples

      :ok = ClientSupervisor.send_balanced(message)
      {:ok, response} = ClientSupervisor.send_balanced(rpc_message)
      {:error, :no_connections} = ClientSupervisor.send_balanced(message)

      # With custom discovery (e.g., distributed with :pg)
      :ok = ClientSupervisor.send_balanced(message,
        client_discovery: fn -> :pg.get_members(:ws_pool) end
      )
  """
  @spec send_balanced(binary(), keyword()) :: :ok | {:ok, map()} | {:error, term()}
  def send_balanced(message, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    discover_fn = Keyword.get(opts, :client_discovery, &list_clients/0)
    pids = discover_fn.()

    case ZenWebsocket.PoolRouter.select_connection(pids) do
      {:error, :no_connections} ->
        {:error, :no_connections}

      {:ok, selected_pid} ->
        do_send_balanced(message, pids, selected_pid, max_attempts, 1)
    end
  end

  # Recursive helper for send_balanced with failover logic.
  # Attempts to send via selected connection, failing over to next healthiest on error.
  @doc false
  defp do_send_balanced(_message, _pids, _last_pid, max_attempts, attempt) when attempt > max_attempts do
    {:error, :max_attempts_exceeded}
  end

  defp do_send_balanced(message, pids, selected_pid, max_attempts, attempt) do
    # Construct partial client struct with only the fields needed for send_message/2.
    # This is intentional - we only need server_pid for GenServer routing and state
    # for the connected check. Other fields (gun_pid, stream_ref, etc.) are not used
    # by send_message/2 which delegates to the GenServer.
    client = %ZenWebsocket.Client{server_pid: selected_pid, state: :connected}

    case ZenWebsocket.Client.send_message(client, message) do
      :ok ->
        ZenWebsocket.PoolRouter.clear_errors(selected_pid)
        :ok

      {:ok, response} ->
        ZenWebsocket.PoolRouter.clear_errors(selected_pid)
        {:ok, response}

      {:error, reason} = error ->
        ZenWebsocket.PoolRouter.record_error(selected_pid)

        # Emit failover telemetry
        :telemetry.execute(
          [:zen_websocket, :pool, :failover],
          %{attempt: attempt},
          %{failed_pid: selected_pid, reason: reason}
        )

        # Try next connection, excluding the failed one
        remaining_pids = Enum.reject(pids, &(&1 == selected_pid))

        case ZenWebsocket.PoolRouter.select_connection(remaining_pids) do
          {:ok, next_pid} ->
            do_send_balanced(message, remaining_pids, next_pid, max_attempts, attempt + 1)

          {:error, :no_connections} ->
            error
        end
    end
  end
end
