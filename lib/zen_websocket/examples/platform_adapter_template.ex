defmodule ZenWebsocket.Examples.PlatformAdapterTemplate do
  @moduledoc """
  Minimal template for creating platform-specific WebSocket adapters.

  ## Extension Points
  - `handle_message/2` - Process platform-specific messages
  - `format_subscription/1` - Convert channels to platform format
  - `authenticate/2` - Implement platform authentication
  """

  alias ZenWebsocket.Client

  @doc "Connect to platform WebSocket endpoint"
  @spec connect(String.t(), keyword()) :: {:ok, Client.t()} | {:error, term()}
  def connect(url, opts \\ []) do
    Client.connect(url, Keyword.merge([adapter: __MODULE__], opts))
  end

  @doc "Authenticate with platform credentials"
  @spec authenticate(Client.t(), map()) :: :ok | {:ok, map()} | {:error, term()}
  def authenticate(client, credentials) do
    # Platform-specific auth message
    auth_msg = %{method: "auth", params: credentials}
    Client.send_message(client, Jason.encode!(auth_msg))
  end

  @doc "Subscribe to platform channels"
  @spec subscribe(Client.t(), [String.t()]) :: :ok | {:ok, map()} | {:error, term()}
  def subscribe(client, channels) do
    # Platform-specific subscription format
    sub_msg = %{method: "subscribe", channels: channels}
    Client.send_message(client, Jason.encode!(sub_msg))
  end

  @doc "Send platform request"
  @spec request(Client.t(), String.t(), map()) :: :ok | {:ok, map()} | {:error, term()}
  def request(client, method, params \\ %{}) do
    Client.send_message(client, Jason.encode!(%{method: method, params: params}))
  end

  @doc "Handle incoming platform messages"
  @spec handle_message(map(), term()) :: {:ok, term(), term()} | {:error, term(), term()}
  def handle_message(msg, state) do
    # Override for platform-specific message handling
    case msg do
      %{"result" => result} -> {:ok, result, state}
      %{"error" => error} -> {:error, error, state}
      _ -> {:ok, msg, state}
    end
  end
end
