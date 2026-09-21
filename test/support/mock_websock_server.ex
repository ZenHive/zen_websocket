defmodule ZenWebsocket.Test.Support.MockWebSockServer do
  @moduledoc """
  A simple WebSocket server for testing ZenWebsocket clients.

  This server:
  - Starts on a dynamic port by default
  - Accepts WebSocket connections
  - Allows custom handlers for incoming frames
  - Can be stopped to simulate disconnections

  ## Usage

  ```elixir
  # Start the server (gets a dynamic port)
  {:ok, server_pid, port} = MockWebSockServer.start_link()

  # Set a custom handler for frames
  MockWebSockServer.set_handler(server_pid, fn
    {:text, "ping"} -> {:reply, {:text, "pong"}}
    {:text, msg} -> {:reply, {:text, "echo: " <> msg}}
  end)

  # Stop the server to simulate a disconnect
  MockWebSockServer.stop(server_pid)
  ```
  """

  use GenServer

  require Logger

  @default_path "/ws"
  defp get_tls_options do
    # Use certificate helper if available
    if Code.ensure_loaded?(ZenWebsocket.Test.Support.CertificateHelper) do
      # Generate temporary self-signed cert for testing
      alias ZenWebsocket.Test.Support.CertificateHelper

      {cert_path, key_path} = CertificateHelper.generate_self_signed_certificate()

      [
        certfile: cert_path,
        keyfile: key_path
      ]
    else
      # Fallback to hard-coded test certificates if they exist
      priv_dir = :code.priv_dir(:zen_websocket)
      cert_file = Path.join([priv_dir, "test_certs", "server.crt"])
      key_file = Path.join([priv_dir, "test_certs", "server.key"])

      if File.exists?(cert_file) and File.exists?(key_file) do
        [
          certfile: cert_file,
          keyfile: key_file
        ]
      else
        raise """
        No TLS certificates available for MockWebSockServer.

        Either:
        1. Install ZenWebsocket.Test.Support.CertificateHelper (recommended)
        2. Provide test certificates at:
           - #{cert_file}
           - #{key_file}
        3. Use protocol: :http instead of :tls for testing
        """
      end
    end
  end

  defmodule WebSocketHandler do
    @moduledoc false
    @behaviour :cowboy_websocket

    alias ZenWebsocket.Test.Support.MockWebSockServer

    def init(req, state) do
      qs = :cowboy_req.qs(req)
      path = :cowboy_req.path(req)
      handler = take_handler(state, websocket_pid(req))
      {:cowboy_websocket, req, Map.merge(state, %{request_path: path, request_query: qs, handler: handler})}
    end

    def websocket_init(state) do
      {:ok, Map.put(state, :handler, take_handler(state, self()))}
    end

    def websocket_handle({:text, "internal:get_handler"}, state) do
      {:ok, Map.put(state, :handler, take_handler(state, self()))}
    end

    def websocket_handle({:text, "internal:get_request_info"}, state) do
      info = Jason.encode!(%{path: state.request_path, query: state.request_query})
      {:reply, {:text, info}, state}
    end

    def websocket_handle(frame, %{parent: _parent, handler: handler} = state) when is_function(handler) do
      case handler.(frame) do
        {:reply, response} ->
          {:reply, response, state}

        :ok ->
          {:ok, state}

        other ->
          Logger.warning("Unknown response from handler: #{inspect(other)}")
          {:ok, state}
      end
    end

    def websocket_handle(frame, %{parent: _parent} = state) do
      # Default handler with common patterns for tests
      case frame do
        {:text, "ping"} -> {:reply, {:text, "pong"}, state}
        {:text, "subscribe:" <> channel} -> {:reply, {:text, "subscribed:#{channel}"}, state}
        {:text, "unsubscribe:" <> channel} -> {:reply, {:text, "unsubscribed:#{channel}"}, state}
        {:text, "authenticate"} -> {:reply, {:text, "authenticated"}, state}
        {:text, msg} -> {:reply, {:text, "echo: #{msg}"}, state}
        {:binary, data} -> {:reply, {:binary, data}, state}
        _ -> {:ok, state}
      end
    end

    def websocket_info({:set_handler, handler}, state) do
      {:ok, Map.put(state, :handler, handler)}
    end

    def websocket_info({:send_text, message}, state) do
      {:reply, {:text, message}, state}
    end

    def websocket_info({:send_binary, data}, state) do
      {:reply, {:binary, data}, state}
    end

    def websocket_info({:trigger_close, code, reason}, state) do
      {:reply, {:close, code, reason}, state}
    end

    def websocket_info(info, state) do
      Logger.debug("WebSocketHandler received unhandled info: #{inspect(info)}")
      {:ok, state}
    end

    def terminate(reason, _req, _state) do
      Logger.debug("WebSocketHandler terminating: #{inspect(reason)}")
      :ok
    end

    # HTTP/1.1 takeover runs in the connection process (`req.pid`), not the
    # stream process that executes init/2. HTTP/2 takeover stays on self().
    defp websocket_pid(%{version: :"HTTP/1.1", pid: pid}) when is_pid(pid), do: pid
    defp websocket_pid(_req), do: self()

    defp take_handler(%{table: table}, ws_pid), do: MockWebSockServer.handshake(table, ws_pid)
    defp take_handler(_state, _ws_pid), do: nil
  end

  def start_link(options \\ []) do
    options =
      case options do
        opts when is_list(opts) -> opts
        port when is_integer(port) -> [port: port]
      end

    with {:ok, pid} <- GenServer.start_link(__MODULE__, options) do
      actual_port = get_port(pid)
      {:ok, pid, actual_port}
    end
  end

  def set_handler(server, handler) when is_function(handler, 1) do
    GenServer.call(server, {:set_handler, handler})
  end

  def get_port(server) do
    GenServer.call(server, :get_port)
  end

  def get_connections(server) do
    GenServer.call(server, :get_connections)
  end

  @doc false
  @spec broadcast_text(pid(), binary()) :: :ok
  def broadcast_text(server, message) when is_binary(message) do
    GenServer.call(server, {:broadcast_text, message})
  end

  @doc false
  @spec handshake(:ets.tid(), pid()) :: (term() -> term()) | nil
  def handshake(table, ws_pid) when is_pid(ws_pid) do
    :ets.insert(table, {{:conn, ws_pid}, true})

    case :ets.lookup(table, :handler) do
      [{:handler, handler}] -> handler
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def stop(server) do
    if Process.alive?(server) do
      GenServer.call(server, :stop, 10_000)
    else
      :ok
    end
  end

  # GenServer callbacks

  def init(options) when is_list(options) do
    port = Keyword.get(options, :port, 0)
    protocol = Keyword.get(options, :protocol, :http)

    # Use a unique name for each server instance to avoid conflicts
    server_name = :"mock_websocket_server_#{System.unique_integer([:positive])}"
    table = :ets.new(:mock_websock_server, [:set, :public])
    :ets.insert(table, {:handler, nil})

    # Define the dispatch rules for cowboy
    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {@default_path, WebSocketHandler, %{parent: self(), handler: nil, table: table}}
         ]}
      ])

    # Start cowboy based on protocol
    {:ok, listener_pid} =
      case protocol do
        :http ->
          :cowboy.start_clear(
            server_name,
            [{:port, port}],
            %{env: %{dispatch: dispatch}}
          )

        :tls ->
          # Get TLS options (in test environment, use simple self-signed cert)
          cert_opts = get_tls_options()

          :cowboy.start_tls(
            server_name,
            [{:port, port} | cert_opts],
            %{env: %{dispatch: dispatch}}
          )

        :http2 ->
          # HTTP/2 over plain TCP (not common in production)
          :cowboy.start_clear(
            server_name,
            [{:port, port}],
            %{env: %{dispatch: dispatch}}
          )

        :https2 ->
          # HTTP/2 over TLS
          cert_opts = get_tls_options()

          :cowboy.start_tls(
            server_name,
            [{:port, port} | cert_opts],
            %{env: %{dispatch: dispatch}}
          )
      end

    # Get the actual port (important when using port 0)
    # The return format appears to be {ip_tuple, port_number}
    {_, actual_port} = :ranch.get_addr(server_name)

    Logger.debug("MockWebSockServer started on port #{actual_port}")

    {:ok,
     %{
       port: actual_port,
       listener_pid: listener_pid,
       connections: %{},
       handler: nil,
       server_name: server_name,
       table: table
     }, {:continue, {:return_port, actual_port}}}
  end

  def handle_continue({:return_port, _port}, state) do
    {:noreply, state}
  end

  def handle_call({:set_handler, handler}, _from, state) do
    :ets.insert(state.table, {:handler, handler})

    Enum.each(live_connection_pids(state), fn ws_pid ->
      send(ws_pid, {:set_handler, handler})
    end)

    {:reply, :ok, %{state | handler: handler}}
  end

  def handle_call({:broadcast_text, message}, _from, state) do
    Enum.each(live_connection_pids(state), fn ws_pid ->
      send(ws_pid, {:send_text, message})
    end)

    {:reply, :ok, state}
  end

  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  def handle_call(:get_connections, _from, state) do
    live_connections =
      state
      |> live_connection_pids()
      |> Map.new(fn pid -> {make_ref(), pid} end)

    {:reply, live_connections, %{state | connections: live_connections}}
  end

  def handle_call(:stop, _from, state) do
    if Map.has_key?(state, :server_name) do
      :ok = :cowboy.stop_listener(state.server_name)
    end

    {:stop, :normal, :ok, state}
  end

  def handle_info({:get_handler_request, ws_pid}, state) do
    handler = handshake(state.table, ws_pid)

    if handler != nil do
      send(ws_pid, {:set_handler, handler})
    end

    {:noreply, state}
  end

  def handle_info(info, state) do
    Logger.debug("MockWebSockServer received unhandled info: #{inspect(info)}")
    {:noreply, state}
  end

  def terminate(_reason, state) do
    if :erlang.function_exported(:cowboy, :stop_listener, 1) and Map.has_key?(state, :server_name) do
      :cowboy.stop_listener(state.server_name)
    end

    if table = Map.get(state, :table) do
      :ets.delete(table)
    end

    :ok
  end

  defp live_connection_pids(%{table: table}) do
    table
    |> :ets.select([{{{:conn, :"$1"}, :_}, [], [:"$1"]}])
    |> Enum.filter(&Process.alive?/1)
  rescue
    ArgumentError -> []
  end
end
