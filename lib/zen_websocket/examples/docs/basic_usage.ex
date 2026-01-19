defmodule ZenWebsocket.Examples.Docs.BasicUsage do
  @moduledoc """
  Basic usage examples from the documentation.
  These examples demonstrate simple WebSocket connections and message handling.
  """

  alias ZenWebsocket.Client
  alias ZenWebsocket.Config

  @deribit_testnet "wss://test.deribit.com/ws/api/v2"

  @doc """
  Simple Deribit testnet connection example.

  Connects to Deribit testnet, sends a public API request, and receives response.
  The default handler automatically sends messages to the calling process.
  """
  def deribit_testnet_example do
    # Connect to Deribit testnet (no auth required for public endpoints)
    {:ok, client} = Client.connect(@deribit_testnet)

    # Send a public/test request (returns server version info)
    request =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "public/test",
        "params" => %{},
        "id" => 1
      })

    # send_message returns {:ok, response} for JSON-RPC calls with correlation
    {:ok, _response} = Client.send_message(client, request)

    # Close the connection
    :ok = Client.close(client)

    {:ok, client}
  end

  @doc """
  Connection with custom headers example.

  Shows how to connect with authorization headers and other custom headers.
  """
  def custom_headers_example(token) do
    config = %Config{
      url: @deribit_testnet,
      headers: [
        {"Authorization", "Bearer #{token}"},
        {"X-API-Version", "2.0"}
      ],
      timeout: 10_000
    }

    {:ok, client} = Client.connect(config)
    {:ok, client}
  end
end
