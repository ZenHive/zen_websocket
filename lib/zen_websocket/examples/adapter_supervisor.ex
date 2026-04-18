defmodule ZenWebsocket.Examples.AdapterSupervisor do
  @moduledoc """
  Supervisor for WebSocket adapters with fault tolerance.

  This supervisor manages adapter GenServers alongside the ClientSupervisor,
  creating a robust supervision tree where:

  - ClientSupervisor manages Client GenServers
  - AdapterSupervisor manages adapter GenServers
  - Adapters monitor their Clients and handle reconnection

  ## Example

      children = [
        {ZenWebsocket.ClientSupervisor, []},
        {ZenWebsocket.Examples.AdapterSupervisor, [
          adapters: [
            {DeribitGenServerAdapter, [
              name: :deribit_main,
              client_id: "...",
              client_secret: "..."
            ]},
            {DeribitGenServerAdapter, [
              name: :deribit_backup,
              url: "wss://www.deribit.com/ws/api/v2",
              client_id: "...",
              client_secret: "..."
            ]}
          ]
        ]}
      ]
      
      Supervisor.start_link(children, strategy: :one_for_one)
  """

  use Supervisor

  @doc """
  Starts the adapter supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    adapters = Keyword.get(opts, :adapters, [])

    children =
      Enum.map(adapters, fn {adapter_module, adapter_opts} ->
        {adapter_module, adapter_opts}
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
