defmodule ZenWebsocket.Examples.Docs.JsonRpcClient do
  @moduledoc """
  JSON-RPC client example from documentation.

  Demonstrates how to make JSON-RPC calls over WebSocket connections.
  The ZenWebsocket.Client automatically handles request/response 
  correlation for JSON-RPC messages - no manual correlation needed!
  """

  use ZenWebsocket.JsonRpc

  alias ZenWebsocket.Client
  alias ZenWebsocket.JsonRpc

  require Logger

  # Define some common JSON-RPC methods
  defrpc :get_balance, "get_balance", doc: "Get account balance"
  defrpc :get_server_time, "get_server_time", doc: "Get server timestamp"
  defrpc :echo, "echo", doc: "Echo test method"

  @doc """
  Makes a synchronous JSON-RPC call.

  The Client automatically handles JSON-RPC correlation - when sending a message
  with an "id" field, it tracks the request and returns the correlated response.
  """
  @spec call_method(Client.t(), String.t(), map() | nil, timeout()) ::
          {:ok, term()} | {:error, term()}
  def call_method(client, method, params \\ nil, _timeout \\ 5_000) do
    {:ok, request} = JsonRpc.build_request(method, params)

    # Client.send_message automatically handles correlation for JSON-RPC messages!
    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, response} ->
        # Response is already correlated by Client
        case JsonRpc.match_response(response) do
          {:ok, result} -> {:ok, result}
          {:error, error} -> {:error, error}
        end

      error ->
        error
    end
  end

  @doc """
  Makes an async JSON-RPC call without waiting for response.
  """
  @spec cast_method(Client.t(), String.t(), map() | nil) :: :ok | {:error, term()}
  def cast_method(client, method, params \\ nil) do
    {:ok, request} = JsonRpc.build_request(method, params)

    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Processes incoming WebSocket messages and returns JSON-RPC responses.
  """
  @spec handle_message(map() | String.t()) :: {:ok, map()} | {:error, term()} | :ignore
  def handle_message(%{} = decoded) do
    # JSON frames arrive pre-decoded as maps
    case JsonRpc.match_response(decoded) do
      {:ok, result} ->
        Logger.debug("JSON-RPC result: #{inspect(result)}")
        {:ok, %{id: decoded["id"], result: result}}

      {:error, {code, msg}} ->
        Logger.error("JSON-RPC error: #{code} - #{msg}")
        {:error, %{id: decoded["id"], code: code, message: msg}}

      {:notification, method, params} ->
        Logger.info("JSON-RPC notification: #{method}")
        handle_notification(method, params)
    end
  end

  def handle_message(message) when is_binary(message) do
    # Non-JSON text frames arrive as binary strings
    Logger.warning("Received non-JSON message: #{inspect(message)}")
    :ignore
  end

  # Note: wait_for_response is no longer needed!
  # The Client handles correlation automatically for JSON-RPC messages with IDs.

  # Handle JSON-RPC notifications
  defp handle_notification("heartbeat", %{"type" => "test_request"}) do
    Logger.debug("Received heartbeat test_request")
    {:notification, :heartbeat}
  end

  defp handle_notification(method, params) do
    Logger.debug("Received notification: #{method} with params: #{inspect(params)}")
    {:notification, method, params}
  end
end
