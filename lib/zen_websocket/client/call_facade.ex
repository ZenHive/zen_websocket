defmodule ZenWebsocket.Client.CallFacade do
  @moduledoc """
  Process-down-safe GenServer.call helpers used by `ZenWebsocket.Client`.

  Touches no Gun state. Every public Client accessor that talks to the
  connection process goes through `safe_call/3`.
  """

  alias ZenWebsocket.Config

  # GenServer.call needs extra time beyond the underlying operation timeout.
  # This buffer accounts for message passing and scheduling overhead.
  @genserver_call_buffer_ms 100

  # Minimum timeout ensures connection attempts have reasonable time,
  # even if user specifies a very short timeout.
  @minimum_connection_timeout_ms 1000

  @doc """
  Starts the Client GenServer, installs the default parent handler when
  none is provided, and awaits the WebSocket upgrade.
  """
  @spec start_client(module(), Config.t(), keyword(), (map(), pid() -> struct())) ::
          {:ok, struct()} | {:error, term()}
  def start_client(server_module, config, opts, builder) do
    opts = with_default_handler(opts, self())

    case GenServer.start(server_module, {config, opts}) do
      {:ok, server_pid} ->
        timeout = max(config.timeout + @genserver_call_buffer_ms, @minimum_connection_timeout_ms)
        finish_connect(server_pid, timeout, builder)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a parent-process message handler when `:handler` is absent from `opts`.
  """
  @spec with_default_handler(keyword(), pid()) :: keyword()
  def with_default_handler(opts, parent_pid) do
    if Keyword.has_key?(opts, :handler) do
      opts
    else
      default_handler = fn
        {:message, data} -> send(parent_pid, {:websocket_message, data})
        {:binary, data} -> send(parent_pid, {:websocket_message, data})
        {:unmatched_response, response} -> send(parent_pid, {:websocket_unmatched_response, response})
        {:protocol_error, reason} -> send(parent_pid, {:websocket_protocol_error, reason})
        _other -> :ok
      end

      Keyword.put(opts, :handler, default_handler)
    end
  end

  @doc """
  `GenServer.call/2` that returns `fallback` when the server process is down.
  """
  @spec safe_call(pid(), term(), term()) :: term()
  def safe_call(server_pid, request, fallback) do
    GenServer.call(server_pid, request)
  catch
    :exit, reason ->
      if process_down_exit?(reason) do
        fallback
      else
        exit(reason)
      end
  end

  @doc """
  True when a `GenServer.call/2` exit means the target process is gone.
  """
  @spec process_down_exit?(term()) :: boolean()
  def process_down_exit?({:noproc, _details}), do: true
  def process_down_exit?({:normal, _details}), do: true
  def process_down_exit?({:shutdown, _details}), do: true
  def process_down_exit?({{:shutdown, _reason}, _details}), do: true
  def process_down_exit?(_reason), do: false

  @doc """
  Unwraps a `GenServer.call/3` exit into the error reason returned to callers.
  """
  @spec unwrap_call_exit(term()) :: term()
  def unwrap_call_exit({:timeout, _details}), do: :timeout
  def unwrap_call_exit({reason, {GenServer, :call, _details}}), do: reason
  def unwrap_call_exit({reason, {:gen_server, :call, _details}}), do: reason
  def unwrap_call_exit(reason), do: reason

  @doc """
  Reads reconnect target and opts from a live Client struct or its GenServer.
  """
  @spec reconnect_target(map()) :: {Config.t() | String.t() | nil, keyword()}
  def reconnect_target(%{server_pid: server_pid} = client) when is_pid(server_pid) do
    fallback = {client.config || client.url, client.reconnect_opts}

    case safe_call(server_pid, :get_state_internal, :disconnected) do
      {:ok, state} -> {state.config, reconnect_opts_from_state(state)}
      _ -> fallback
    end
  end

  def reconnect_target(%{} = client) do
    {client.config || client.url, client.reconnect_opts}
  end

  @doc """
  Re-opens a connection via `connect_fun` or a caller-supplied `:reconnector`.
  """
  @spec reconnect_with(
          Config.t() | String.t() | nil,
          keyword(),
          (term(), keyword() -> {:ok, struct()} | {:error, term()})
        ) :: {:ok, struct()} | {:error, term()}
  def reconnect_with(nil, _opts, _connect_fun), do: {:error, {:not_connected, :missing_config}}

  def reconnect_with(target, opts, connect_fun) do
    case Keyword.pop(opts, :reconnector) do
      {reconnector, reconnect_opts} when is_function(reconnector, 2) ->
        reconnector.(target, reconnect_opts)

      {_reconnector, reconnect_opts} ->
        connect_fun.(target, reconnect_opts)
    end
  end

  @doc """
  Builds the keyword list stored on the Client struct for a later reconnect.
  """
  @spec reconnect_opts_from_state(map()) :: keyword()
  def reconnect_opts_from_state(state) do
    []
    |> maybe_put_reconnect_opt(:handler, state.handler)
    |> maybe_put_reconnect_opt(:heartbeat_config, state.heartbeat_config)
    |> maybe_put_reconnect_opt(:on_connect, state.on_connect)
    |> maybe_put_reconnect_opt(:on_disconnect, state.on_disconnect)
    |> maybe_put_reconnect_opt(:reconnector, state.reconnector)
  end

  @spec finish_connect(pid(), timeout(), (map(), pid() -> struct())) :: {:ok, struct()} | {:error, term()}
  defp finish_connect(server_pid, timeout, builder) do
    case await_connected(server_pid, timeout) do
      {:ok, state} ->
        {:ok, builder.(state, server_pid)}

      {:error, reason} ->
        stop_client_process(server_pid)
        {:error, reason}
    end
  end

  @spec await_connected(pid(), timeout()) :: {:ok, map()} | {:error, term()}
  defp await_connected(server_pid, timeout) do
    GenServer.call(server_pid, :await_connection, timeout)
  catch
    :exit, reason -> {:error, unwrap_call_exit(reason)}
  end

  @spec stop_client_process(pid()) :: :ok
  defp stop_client_process(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @spec maybe_put_reconnect_opt(keyword(), atom(), term()) :: keyword()
  defp maybe_put_reconnect_opt(opts, _key, nil), do: opts
  defp maybe_put_reconnect_opt(opts, :heartbeat_config, :disabled), do: opts
  defp maybe_put_reconnect_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
