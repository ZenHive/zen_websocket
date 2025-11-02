defmodule ZenWebsocket.Examples.DeribitRpc do
  @moduledoc """
  Shared Deribit JSON-RPC method definitions and request builders.

  This module centralizes all Deribit RPC method definitions
  to avoid duplication across adapter examples.

  Uses `ZenWebsocket.JsonRpc.build_request/2` and returns the
  standard `{:ok, map()}` tuple for consistency with library conventions.
  """

  alias ZenWebsocket.JsonRpc

  # Generic Request Builder

  @doc """
  Builds a generic JSON-RPC request for any Deribit method.

  ## Parameters
  - `method` - The RPC method name
  - `params` - Method parameters (default: %{})

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map.
  """
  @spec build_request(String.t(), map()) :: {:ok, map()}
  def build_request(method, params \\ %{}) do
    JsonRpc.build_request(method, params)
  end

  # Authentication & Session

  @doc """
  Builds an authentication request for Deribit API.

  ## Parameters
  - `client_id` - Your Deribit API client ID
  - `client_secret` - Your Deribit API client secret

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for authentication.
  """
  @spec auth_request(String.t(), String.t()) :: {:ok, map()}
  def auth_request(client_id, client_secret) do
    JsonRpc.build_request("public/auth", %{
      grant_type: "client_credentials",
      client_id: client_id,
      client_secret: client_secret
    })
  end

  @doc """
  Sets the heartbeat interval for the WebSocket connection.

  ## Parameters
  - `interval` - Heartbeat interval in seconds (default: 30)

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for setting heartbeat.
  """
  @spec set_heartbeat(integer()) :: {:ok, map()}
  def set_heartbeat(interval \\ 30) do
    JsonRpc.build_request("public/set_heartbeat", %{interval: interval})
  end

  @doc """
  Builds a test request to verify the connection is alive.

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for connection testing.
  """
  @spec test_request() :: {:ok, map()}
  def test_request do
    JsonRpc.build_request("public/test", %{})
  end

  # Subscriptions

  @doc """
  Subscribes to one or more channels for real-time data.

  ## Parameters
  - `channels` - List of channel names to subscribe to

  ## Example
      subscribe(["book.BTC-PERPETUAL.raw", "ticker.ETH-PERPETUAL.raw"])

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for subscription.
  """
  @spec subscribe(list(String.t())) :: {:ok, map()}
  def subscribe(channels) when is_list(channels) do
    JsonRpc.build_request("public/subscribe", %{channels: channels})
  end

  @doc """
  Unsubscribes from one or more channels.

  ## Parameters
  - `channels` - List of channel names to unsubscribe from

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for unsubscription.
  """
  @spec unsubscribe(list(String.t())) :: {:ok, map()}
  def unsubscribe(channels) when is_list(channels) do
    JsonRpc.build_request("public/unsubscribe", %{channels: channels})
  end

  # Market Data

  @doc """
  Retrieves available trading instruments for a currency.

  ## Parameters
  - `currency` - Currency code (e.g., "BTC", "ETH")

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for retrieving instruments.
  """
  @spec get_instruments(String.t()) :: {:ok, map()}
  def get_instruments(currency) do
    JsonRpc.build_request("public/get_instruments", %{currency: currency})
  end

  @doc """
  Retrieves the order book for a specific instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `depth` - Order book depth (default: 10)

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for order book data.
  """
  @spec get_order_book(String.t(), integer()) :: {:ok, map()}
  def get_order_book(instrument, depth \\ 10) do
    JsonRpc.build_request("public/get_order_book", %{
      instrument_name: instrument,
      depth: depth
    })
  end

  @doc """
  Gets ticker data for a specific instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for ticker data.
  """
  @spec ticker(String.t()) :: {:ok, map()}
  def ticker(instrument) do
    JsonRpc.build_request("public/ticker", %{instrument_name: instrument})
  end

  # Trading (Private)

  @doc """
  Creates a buy order for the specified instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Order amount in contracts
  - `opts` - Additional order options (type, price, etc.)

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for buy order.
  """
  @spec buy(String.t(), number(), map()) :: {:ok, map()}
  def buy(instrument, amount, opts \\ %{}) do
    params =
      Map.merge(
        %{
          instrument_name: instrument,
          amount: amount
        },
        opts
      )

    JsonRpc.build_request("private/buy", params)
  end

  @doc """
  Creates a sell order for the specified instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Order amount in contracts
  - `opts` - Additional order options (type, price, etc.)

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for sell order.
  """
  @spec sell(String.t(), number(), map()) :: {:ok, map()}
  def sell(instrument, amount, opts \\ %{}) do
    params =
      Map.merge(
        %{
          instrument_name: instrument,
          amount: amount
        },
        opts
      )

    JsonRpc.build_request("private/sell", params)
  end

  @doc """
  Cancels an existing order by ID.

  ## Parameters
  - `order_id` - The order ID to cancel

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for order cancellation.
  """
  @spec cancel(String.t()) :: {:ok, map()}
  def cancel(order_id) do
    JsonRpc.build_request("private/cancel", %{order_id: order_id})
  end

  @doc """
  Retrieves all open orders with optional filters.

  ## Parameters
  - `opts` - Optional filters (instrument, type, etc.)

  ## Returns
  `{:ok, request}` tuple with JSON-RPC request map for retrieving open orders.
  """
  @spec get_open_orders(map()) :: {:ok, map()}
  def get_open_orders(opts \\ %{}) do
    JsonRpc.build_request("private/get_open_orders", opts)
  end
end
