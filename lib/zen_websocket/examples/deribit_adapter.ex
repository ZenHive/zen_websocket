defmodule ZenWebsocket.Examples.DeribitAdapter do
  @moduledoc """
  Simplified Deribit WebSocket API adapter.

  Uses DeribitRpc for all RPC operations and provides
  5 essential functions for Deribit integration.
  """

  alias ZenWebsocket.Client
  alias ZenWebsocket.Examples.DeribitRpc

  require Logger

  defstruct [:client, :authenticated, :subscriptions, :client_id, :client_secret]

  @type t :: %__MODULE__{
          client: Client.t() | nil,
          authenticated: boolean(),
          subscriptions: MapSet.t(),
          client_id: String.t() | nil,
          client_secret: String.t() | nil
        }

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  @doc """
  Connect to Deribit WebSocket API.

  Options:
  - `:client_id` - Client ID for authentication
  - `:client_secret` - Client secret for authentication
  - `:url` - WebSocket URL (defaults to test.deribit.com)
  - `:handler` - Message handler function
  - `:heartbeat_interval` - Heartbeat interval in seconds (default: 30)
  """
  @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
  def connect(opts \\ []) do
    url = Keyword.get(opts, :url, @deribit_test_url)
    heartbeat_interval = Keyword.get(opts, :heartbeat_interval, 30) * 1000

    connect_opts = [
      heartbeat_config: %{
        type: :deribit,
        interval: heartbeat_interval
      }
    ]

    connect_opts =
      if handler = opts[:handler],
        do: Keyword.put(connect_opts, :handler, handler),
        else: connect_opts

    case Client.connect(url, connect_opts) do
      {:ok, client} ->
        {:ok,
         %__MODULE__{
           client: client,
           authenticated: false,
           subscriptions: MapSet.new(),
           client_id: opts[:client_id],
           client_secret: opts[:client_secret]
         }}

      error ->
        error
    end
  end

  @doc """
  Authenticate with Deribit using client credentials.
  """
  @spec authenticate(t()) :: {:ok, t()} | {:error, term()}
  def authenticate(%__MODULE__{client_id: nil}), do: {:error, :missing_credentials}

  def authenticate(%__MODULE__{client: client} = adapter) do
    with {:ok, auth_req} <- DeribitRpc.auth_request(adapter.client_id, adapter.client_secret),
         {:ok, %{"result" => %{"access_token" => _}}} <- send_json_rpc(client, auth_req),
         {:ok, hb_req} <- DeribitRpc.set_heartbeat(30),
         {:ok, _} <- send_json_rpc(client, hb_req) do
      {:ok, %{adapter | authenticated: true}}
    end
  end

  @doc """
  Subscribe to Deribit channels.
  """
  @spec subscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def subscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
    with {:ok, request} <- DeribitRpc.subscribe(channels),
         {:ok, %{"result" => _}} <- send_json_rpc(client, request) do
      new_subs = Enum.reduce(channels, subs, &MapSet.put(&2, &1))
      {:ok, %{adapter | subscriptions: new_subs}}
    end
  end

  @doc """
  Unsubscribe from Deribit channels.
  """
  @spec unsubscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def unsubscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
    with {:ok, request} <- DeribitRpc.unsubscribe(channels),
         {:ok, %{"result" => _}} <- send_json_rpc(client, request) do
      new_subs = Enum.reduce(channels, subs, &MapSet.delete(&2, &1))
      {:ok, %{adapter | subscriptions: new_subs}}
    end
  end

  @doc """
  Send a request to Deribit API using any supported method.
  """
  @spec send_request(t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def send_request(%__MODULE__{client: client}, method, params \\ %{}) do
    with {:ok, request} <- DeribitRpc.build_request(method, params) do
      send_json_rpc(client, request)
    end
  end

  # Private helper to send JSON-RPC requests
  defp send_json_rpc(client, request) do
    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, response} -> {:ok, response}
      :ok -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end
end
