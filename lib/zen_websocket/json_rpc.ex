defmodule ZenWebsocket.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 request builder and response matcher.

  Simple API builder for WebSocket APIs using JSON-RPC 2.0 protocol.
  Generates request functions with automatic ID tracking and correlation.
  """

  use Descripex, namespace: "/jsonrpc"

  api(:build_request, "Build a JSON-RPC 2.0 request with unique ID.",
    params: [
      method: [kind: :value, description: "RPC method name string"],
      params: [kind: :value, description: "Optional params map for the request", default: nil]
    ],
    returns: %{
      type: "{:ok, map()}",
      description: "JSON-RPC 2.0 request map with jsonrpc, id, method, and optional params"
    }
  )

  @doc """
  Builds a JSON-RPC 2.0 request with unique ID.

  ## Examples
      iex> {:ok, request} = JsonRpc.build_request("public/auth", %{grant_type: "client_credentials"})
      iex> request["method"]
      "public/auth"
  """
  @spec build_request(String.t(), map() | nil) :: {:ok, map()}
  def build_request(method, params \\ nil) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => generate_id(),
      "method" => method
    }

    request = if params, do: Map.put(request, "params", params), else: request
    {:ok, request}
  end

  @doc """
  Imports the `defrpc/2` and `defrpc/3` macros for defining JSON-RPC methods.
  """
  defmacro __using__(_opts) do
    quote do
      import ZenWebsocket.JsonRpc, only: [defrpc: 2, defrpc: 3]
    end
  end

  @doc """
  Generates RPC method functions with automatic request building.

  ## Examples
      defmodule MyApi do
        use ZenWebsocket.JsonRpc

        defrpc :authenticate, "public/auth"
        defrpc :subscribe, "public/subscribe"
        defrpc :get_order_book, "public/get_order_book"
      end
  """
  defmacro defrpc(name, method, opts \\ []) do
    doc = Keyword.get(opts, :doc, "Calls #{method} via JSON-RPC 2.0")

    quote do
      @doc unquote(doc)
      def unquote(name)(params \\ %{}) do
        ZenWebsocket.JsonRpc.build_request(unquote(method), params)
      end
    end
  end

  api(:match_response, "Match a JSON-RPC response as result, error, or notification.",
    params: [
      response: [kind: :value, description: "Decoded JSON-RPC response map"]
    ],
    returns: %{
      type: "{:ok, term()} | {:error, {integer(), String.t()}} | {:notification, String.t(), map()}",
      description: "Matched result, error tuple, or notification with method and params"
    }
  )

  @doc """
  Matches a JSON-RPC response to determine if it's a result or error.

  Returns:
  - `{:ok, result}` for successful responses
  - `{:error, {code, message}}` for JSON-RPC errors
  - `{:notification, method, params}` for notifications
  """
  @spec match_response(map()) :: {:ok, term()} | {:error, {integer(), String.t()}} | {:notification, String.t(), map()}
  def match_response(%{"result" => result}), do: {:ok, result}

  def match_response(%{"error" => %{"code" => code, "message" => message}}) do
    {:error, {code, message}}
  end

  def match_response(%{"method" => method, "params" => params}) do
    {:notification, method, params}
  end

  # Generate unique request ID
  defp generate_id do
    :erlang.unique_integer([:positive])
  end
end
