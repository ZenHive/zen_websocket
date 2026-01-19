defmodule ZenWebsocket.ClientSupervisor do
  # Supervisor restart policy: allow up to 10 restarts within 60 seconds.
  # This prevents rapid restart loops while allowing recovery from transient failures.
  @moduledoc """
  Optional supervisor for WebSocket client connections.

  Provides supervised client connections with automatic restart on failure.
  Each client runs under its own supervisor for isolation.

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
  """
  @spec start_client(String.t() | ZenWebsocket.Config.t(), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def start_client(url_or_config, opts \\ []) do
    # Add supervision flag to opts
    supervised_opts = Keyword.put(opts, :supervised, true)

    child_spec = %{
      id: make_ref(),
      start: {ZenWebsocket.Client, :start_link, [url_or_config, supervised_opts]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} when is_pid(pid) ->
        # Wait for connection and get the client struct
        timeout = Keyword.get(opts, :timeout, 5000) + @supervision_buffer_ms

        try do
          case GenServer.call(pid, :await_connection, timeout) do
            {:ok, state} ->
              # Build the client struct manually since we have the pid
              client = %ZenWebsocket.Client{
                gun_pid: state.gun_pid,
                stream_ref: state.stream_ref,
                state: state.state,
                url: state.url,
                monitor_ref: state.monitor_ref,
                server_pid: pid
              }

              {:ok, client}

            {:error, reason} ->
              # Stop the supervised child on connection failure
              DynamicSupervisor.terminate_child(__MODULE__, pid)
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            DynamicSupervisor.terminate_child(__MODULE__, pid)
            {:error, :timeout}
        end

      error ->
        error
    end
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
end
