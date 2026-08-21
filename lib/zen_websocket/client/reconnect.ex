defmodule ZenWebsocket.ClientReconnect do
  @moduledoc """
  Explicit reconnect target and option handling for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.ClientCallFacade, as: CallFacade
  alias ZenWebsocket.Config

  @doc """
  Reads reconnect target and opts from a live Client struct or its GenServer.
  """
  @spec reconnect_target(map()) :: {Config.t() | String.t() | nil, keyword()}
  def reconnect_target(%{server_pid: server_pid} = client) when is_pid(server_pid) do
    fallback = {client.config || client.url, client.reconnect_opts}

    case CallFacade.safe_call(server_pid, :get_state_internal, :disconnected) do
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

  @spec maybe_put_reconnect_opt(keyword(), atom(), term()) :: keyword()
  defp maybe_put_reconnect_opt(opts, _key, nil), do: opts
  defp maybe_put_reconnect_opt(opts, :heartbeat_config, :disabled), do: opts
  defp maybe_put_reconnect_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
