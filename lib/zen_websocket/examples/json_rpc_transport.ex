defmodule ZenWebsocket.Examples.JsonRpcTransport do
  @moduledoc "Shared JSON-RPC send helper used by Deribit example adapters."

  alias ZenWebsocket.Client

  @doc "Sends a JSON-RPC request map over a WebSocket client, normalising `:ok` to `{:ok, %{}}`."
  @spec send_json_rpc(Client.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_json_rpc(client, request) do
    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, response} -> {:ok, response}
      :ok -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end
end
