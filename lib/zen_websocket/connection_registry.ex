defmodule ZenWebsocket.ConnectionRegistry do
  @moduledoc """
  Opt-in ETS connection tracking, without a GenServer.

  Maps a caller-chosen connection id to a Gun pid in a public named ETS table
  (`:zen_websocket_connections`), monitoring each pid so dead connections can be
  swept. The table is created lazily by `init/0` and every other function assumes
  it exists — call `init/0` once (typically from your application start) before
  registering.

  `ZenWebsocket.Client` does not use this registry; it is a utility for consumers
  that want to look connections up by a stable id.
  """

  use Descripex, namespace: "/registry"

  @table_name :zen_websocket_connections

  api(:init, "Create the connection registry ETS table if it does not exist.",
    returns: %{type: ":ok", description: "Always succeeds, idempotent"}
  )

  @doc """
  Initialize the connection registry ETS table.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table])
        :ok

      _ ->
        :ok
    end
  end

  api(:register, "Register a connection id against a Gun pid and monitor the pid.",
    params: [
      connection_id: [kind: :value, description: "Caller-chosen connection identifier string"],
      gun_pid: [kind: :value, description: "Gun connection pid to track"]
    ],
    returns: %{type: ":ok", description: "Always succeeds"}
  )

  @doc """
  Register a connection with monitoring.
  """
  @spec register(String.t(), pid()) :: :ok
  def register(connection_id, gun_pid) when is_binary(connection_id) and is_pid(gun_pid) do
    monitor_ref = Process.monitor(gun_pid)
    :ets.insert(@table_name, {connection_id, gun_pid, monitor_ref})
    :ok
  end

  api(:deregister, "Remove a connection by id and drop its monitor.",
    params: [
      connection_id: [kind: :value, description: "Connection identifier to remove"]
    ],
    returns: %{type: ":ok", description: "Always succeeds, even when the id is unknown"}
  )

  @doc """
  Deregister a connection by ID.
  """
  @spec deregister(String.t()) :: :ok
  def deregister(connection_id) when is_binary(connection_id) do
    case :ets.lookup(@table_name, connection_id) do
      [{^connection_id, _gun_pid, monitor_ref}] ->
        Process.demonitor(monitor_ref, [:flush])
        :ets.delete(@table_name, connection_id)

      [] ->
        :ok
    end

    :ok
  end

  api(:get, "Look up the Gun pid registered for a connection id.",
    params: [
      connection_id: [kind: :value, description: "Connection identifier to look up"]
    ],
    returns: %{type: "{:ok, pid()} | {:error, :not_found}", description: "Registered Gun pid or error"},
    errors: [:not_found]
  )

  @doc """
  Get connection info by ID.
  """
  @spec get(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get(connection_id) when is_binary(connection_id) do
    case :ets.lookup(@table_name, connection_id) do
      [{^connection_id, gun_pid, _monitor_ref}] -> {:ok, gun_pid}
      [] -> {:error, :not_found}
    end
  end

  api(:cleanup_dead, "Remove every registration pointing at a dead Gun pid.",
    params: [
      gun_pid: [kind: :value, description: "Gun pid whose registrations should be swept"]
    ],
    returns: %{type: ":ok", description: "Always succeeds"}
  )

  @doc """
  Cleanup dead connection by PID.
  """
  @spec cleanup_dead(pid()) :: :ok
  def cleanup_dead(gun_pid) when is_pid(gun_pid) do
    matches = :ets.match_object(@table_name, {:_, gun_pid, :_})

    Enum.each(matches, fn {connection_id, _pid, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
      :ets.delete(@table_name, connection_id)
    end)

    :ok
  end

  api(:shutdown, "Drop all monitors and delete the registry ETS table.",
    returns: %{type: ":ok", description: "Always succeeds, even when the table is absent"}
  )

  @doc """
  Cleanup all connections and destroy table.
  """
  @spec shutdown() :: :ok
  def shutdown do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ok

      _ ->
        demonitor_all()
        :ets.delete(@table_name)
        :ok
    end
  end

  @spec demonitor_all() :: :ok
  defp demonitor_all do
    @table_name
    |> :ets.tab2list()
    |> Enum.each(fn {_id, _pid, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
    end)

    :ok
  end
end
