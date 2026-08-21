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

  @doc "Maps a transport {:ok, error-body} to {:error, reason} for `with` else clauses."
  @spec rpc_or_error(term()) :: {:error, term()}
  def rpc_or_error({:ok, %{"error" => reason}}), do: {:error, reason}
  def rpc_or_error({:ok, other}), do: {:error, other}
  def rpc_or_error({:error, reason}), do: {:error, reason}
  def rpc_or_error(other), do: {:error, other}
end
