defmodule ZenWebsocket.ConnectionRegistry do
  @moduledoc """
  ETS-based connection tracking without GenServer.
  """

  @table_name :zen_websocket_connections

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

  @doc """
  Register a connection with monitoring.
  """
  @spec register(String.t(), pid()) :: :ok
  def register(connection_id, gun_pid) when is_binary(connection_id) and is_pid(gun_pid) do
    monitor_ref = Process.monitor(gun_pid)
    :ets.insert(@table_name, {connection_id, gun_pid, monitor_ref})
    :ok
  end

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

  # Demonitors all tracked connections before table deletion
  @doc false
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
