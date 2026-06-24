defmodule ZenWebsocket.Examples.UsagePatterns do
  @moduledoc """
  Examples of different WebSocket client usage patterns.
  This module demonstrates three ways to use ZenWebsocket:
  1. Direct connection (no supervision)
  2. Using ClientSupervisor
  3. Direct supervision in your app
  """
  alias ZenWebsocket.Client
  alias ZenWebsocket.ClientSupervisor

  require Logger

  @doc """
  Pattern 1: Direct connection without supervision.

  Best for:
  - Development and testing
  - Short-lived connections
  - Scripts and one-off tasks

  ## Returns
  `:ok` after demonstrating the connection pattern.
  """
  @spec direct_connection_example() :: :ok
  def direct_connection_example do
    # Simple connection
    {:ok, client} = Client.connect("wss://test.deribit.com/ws/api/v2")

    # Send a message
    Client.send_message(client, Jason.encode!(jsonrpc_request("public/test", %{})))

    # Check state
    Logger.debug("Connection state: #{Client.get_state(client)}")

    # Clean up
    Client.close(client)
    :ok
  end

  @doc """
  Pattern 2: Using ClientSupervisor for automatic restarts.

  Best for:
  - Production systems with multiple connections
  - Dynamic connection management
  - When you need a connection pool

  Note: You must add ClientSupervisor to your supervision tree first!

  ## Returns
  `:ok` after demonstrating the supervisor pattern.
  """
  @spec client_supervisor_example() :: :ok
  def client_supervisor_example do
    # This assumes ClientSupervisor is already started in your app
    {:ok, client} =
      ClientSupervisor.start_client("wss://test.deribit.com/ws/api/v2",
        heartbeat_config: %{type: :deribit, interval: 30_000},
        retry_count: 10
      )

    # Client will automatically restart on crashes
    Logger.debug("Supervised client started: #{inspect(client.server_pid)}")

    # List all supervised clients
    clients = ClientSupervisor.list_clients()
    Logger.debug("Active clients: #{length(clients)}")

    # Stop a specific client (won't restart)
    ClientSupervisor.stop_client(client.server_pid)
    :ok
  end

  @doc """
  Pattern 3: Direct supervision in your application.

  Best for:
  - Fixed set of connections
  - When each connection has a specific role
  - Simple production deployments

  Add this to your application supervisor:

      children = [
        {ZenWebsocket.Client, [
          url: "wss://test.deribit.com/ws/api/v2",
          id: :deribit_client,
          heartbeat_config: %{type: :deribit, interval: 30_000}
        ]}
      ]

  ## Returns
  A child specification tuple for use with Supervisor.
  """
  @spec supervised_client_spec() :: {module(), keyword()}
  def supervised_client_spec do
    # This returns a child spec you can add to your supervisor
    {Client,
     [
       url: "wss://test.deribit.com/ws/api/v2",
       id: :my_deribit_client,
       heartbeat_config: %{type: :deribit, interval: 30_000},
       retry_count: 10
     ]}
  end

  @spec jsonrpc_request(String.t(), term()) :: %{jsonrpc: String.t(), method: String.t(), params: term()}
  defp jsonrpc_request(method, params) do
    %{jsonrpc: "2.0", method: method, params: params}
  end

  defmodule ExampleApp do
    @moduledoc """
    Example application module demonstrating all WebSocket connection patterns.

    This module shows how to set up both dynamic (ClientSupervisor) and
    static (direct child specs) WebSocket connections in your supervision tree.
    """
    use Application

    @impl true
    @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
    def start(_type, _args) do
      children = [
        # Pattern 2: Add ClientSupervisor for dynamic connections
        ClientSupervisor,

        # Pattern 3: Add specific clients
        {Client,
         [
           url: "wss://test.deribit.com/ws/api/v2",
           id: :deribit_production,
           heartbeat_config: %{type: :deribit, interval: 30_000}
         ]},
        {Client,
         [
           url: "wss://test.deribit.com/ws/api/v2",
           id: :deribit_test,
           heartbeat_config: %{type: :deribit, interval: 60_000}
         ]}
      ]

      opts = [strategy: :one_for_one, name: ExampleApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
end
