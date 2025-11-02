defmodule ZenWebsocket.Examples.DeribitGenServerAdapter do
  @moduledoc """
  Production-ready supervised Deribit adapter with automatic reconnection.

  Features: Monitor WebSocket client, auto-reconnect, restore auth/subscriptions.
  Only 5 public functions for clean API. See DeribitRpc for available methods.
  """

  use GenServer

  alias ZenWebsocket.Client
  alias ZenWebsocket.Examples.DeribitRpc

  require Logger

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"
  @reconnect_delay 5_000

  @type state :: %{
          client: Client.t() | nil,
          monitor_ref: reference() | nil,
          authenticated: boolean(),
          was_authenticated: boolean(),
          subscriptions: MapSet.t(String.t()),
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          url: String.t(),
          opts: keyword()
        }

  # Client API - Only 5 public functions

  @doc """
  Starts the Deribit adapter GenServer.

  ## Options
  - `:name` - GenServer name (required)
  - `:client_id` - Deribit API client ID
  - `:client_secret` - Deribit API client secret
  - `:url` - WebSocket URL (defaults to test.deribit.com)
  - `:heartbeat_interval` - Heartbeat interval in seconds
  - `:handler` - Optional message handler module

  ## Returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @doc """
  Authenticates with Deribit using configured credentials.

  ## Returns
  - `:ok` on successful authentication
  - `{:error, :not_connected}` if not connected
  - `{:error, :missing_credentials}` if credentials not configured
  """
  @spec authenticate(GenServer.server()) :: :ok | {:error, atom()}
  def authenticate(adapter), do: GenServer.call(adapter, :authenticate)

  @doc """
  Subscribes to Deribit channels for real-time data.

  ## Parameters
  - `adapter` - The adapter GenServer
  - `channels` - List of channel names

  ## Returns
  - `:ok` on successful subscription
  - `{:error, :not_connected}` if not connected
  """
  @spec subscribe(GenServer.server(), list(String.t())) :: :ok | {:error, atom()}
  def subscribe(adapter, channels), do: GenServer.call(adapter, {:subscribe, channels})

  @doc """
  Sends a JSON-RPC request to Deribit.

  ## Parameters
  - `adapter` - The adapter GenServer
  - `method` - RPC method name
  - `params` - Method parameters (default: %{})

  ## Returns
  The response from Deribit or `{:error, :not_connected}`.
  """
  @spec send_request(GenServer.server(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def send_request(adapter, method, params \\ %{}), do: GenServer.call(adapter, {:send_request, method, params})

  @doc """
  Returns the current adapter state.

  ## Returns
  `{:ok, state}` with the internal state map.
  """
  @spec get_state(GenServer.server()) :: {:ok, state()}
  def get_state(adapter), do: GenServer.call(adapter, :get_state)

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      client: nil,
      monitor_ref: nil,
      authenticated: false,
      was_authenticated: false,
      subscriptions: MapSet.new(),
      client_id: opts[:client_id],
      client_secret: opts[:client_secret],
      url: opts[:url] || @deribit_test_url,
      opts: opts
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call(request, _from, state) do
    case {request, state} do
      {:authenticate, %{client: nil}} ->
        {:reply, {:error, :not_connected}, state}

      {:authenticate, %{client_id: nil}} ->
        {:reply, {:error, :missing_credentials}, state}

      {:authenticate, %{client: client}} ->
        with {:ok, auth_req} <- DeribitRpc.auth_request(state.client_id, state.client_secret),
             {:ok, %{"result" => %{"access_token" => _}}} <- send_json_rpc(client, auth_req),
             {:ok, hb_req} <- DeribitRpc.set_heartbeat(30),
             {:ok, _} <- send_json_rpc(client, hb_req) do
          {:reply, :ok, %{state | authenticated: true, was_authenticated: true}}
        else
          error -> {:reply, error, state}
        end

      {{:subscribe, _}, %{client: nil}} ->
        {:reply, {:error, :not_connected}, state}

      {{:subscribe, channels}, %{client: client}} ->
        with {:ok, req} <- DeribitRpc.subscribe(channels),
             {:ok, %{"result" => _}} <- send_json_rpc(client, req) do
          new_subs = Enum.reduce(channels, state.subscriptions, &MapSet.put(&2, &1))
          {:reply, :ok, %{state | subscriptions: new_subs}}
        else
          error -> {:reply, error, state}
        end

      {{:send_request, _, _}, %{client: nil}} ->
        {:reply, {:error, :not_connected}, state}

      {{:send_request, method, params}, %{client: client}} ->
        case DeribitRpc.build_request(method, params) do
          {:ok, req} -> {:reply, send_json_rpc(client, req), state}
          error -> {:reply, error, state}
        end

      {:get_state, _} ->
        {:reply, {:ok, state}, state}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    opts = [
      heartbeat_config: %{type: :deribit, interval: (state.opts[:heartbeat_interval] || 30) * 1000},
      reconnect_on_error: false
    ]

    opts = if h = state.opts[:handler], do: Keyword.put(opts, :handler, h), else: opts

    case Client.connect(state.url, opts) do
      {:ok, client} ->
        ref = Process.monitor(client.server_pid)
        new_state = %{state | client: client, monitor_ref: ref}

        if state.was_authenticated or MapSet.size(state.subscriptions) > 0 do
          send(self(), :restore_state)
        end

        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Connect failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, @reconnect_delay)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{monitor_ref: ref} = state) do
    Logger.warning("Client died: #{inspect(reason)}")
    send(self(), :connect)
    {:noreply, %{state | client: nil, monitor_ref: nil, authenticated: false}}
  end

  @impl true
  def handle_info(:restore_state, state) do
    cond do
      not state.authenticated and state.was_authenticated ->
        {:reply, _, state} = handle_call(:authenticate, nil, state)
        if MapSet.size(state.subscriptions) > 0, do: send(self(), :restore_subs)
        {:noreply, state}

      MapSet.size(state.subscriptions) > 0 ->
        channels = MapSet.to_list(state.subscriptions)
        {:reply, _, state} = handle_call({:subscribe, channels}, nil, %{state | subscriptions: MapSet.new()})
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:restore_subs, %{subscriptions: subs} = state) when map_size(subs) > 0 do
    channels = MapSet.to_list(subs)
    {:reply, _, state} = handle_call({:subscribe, channels}, nil, %{state | subscriptions: MapSet.new()})
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private helper to send JSON-RPC requests
  defp send_json_rpc(client, request) do
    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, response} -> {:ok, response}
      :ok -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end
end
