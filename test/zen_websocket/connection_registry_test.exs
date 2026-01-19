defmodule ZenWebsocket.ConnectionRegistryTest do
  use ExUnit.Case

  alias ZenWebsocket.ConnectionRegistry

  setup do
    ConnectionRegistry.init()
    on_exit(fn -> ConnectionRegistry.shutdown() end)
    :ok
  end

  describe "connection registration" do
    test "register/2 stores connection with monitoring" do
      pid = spawn(fn -> :timer.sleep(1000) end)
      :ok = ConnectionRegistry.register("conn-1", pid)

      {:ok, ^pid} = ConnectionRegistry.get("conn-1")
    end

    test "get/1 returns error for non-existent connection" do
      {:error, :not_found} = ConnectionRegistry.get("non-existent")
    end

    test "deregister/1 removes connection and stops monitoring" do
      pid = spawn(fn -> :timer.sleep(1000) end)
      :ok = ConnectionRegistry.register("conn-1", pid)

      {:ok, ^pid} = ConnectionRegistry.get("conn-1")
      :ok = ConnectionRegistry.deregister("conn-1")

      {:error, :not_found} = ConnectionRegistry.get("conn-1")
    end

    test "deregister/1 handles non-existent connections gracefully" do
      :ok = ConnectionRegistry.deregister("non-existent")
    end
  end

  describe "multiple connections" do
    test "handles multiple concurrent connections" do
      pid1 = spawn(fn -> :timer.sleep(1000) end)
      pid2 = spawn(fn -> :timer.sleep(1000) end)

      :ok = ConnectionRegistry.register("conn-1", pid1)
      :ok = ConnectionRegistry.register("conn-2", pid2)

      {:ok, ^pid1} = ConnectionRegistry.get("conn-1")
      {:ok, ^pid2} = ConnectionRegistry.get("conn-2")

      ConnectionRegistry.deregister("conn-1")
      ConnectionRegistry.deregister("conn-2")
    end
  end

  describe "process cleanup" do
    test "cleanup_dead/1 removes connections by PID" do
      pid = spawn(fn -> :timer.sleep(100) end)
      :ok = ConnectionRegistry.register("conn-1", pid)

      {:ok, ^pid} = ConnectionRegistry.get("conn-1")

      :ok = ConnectionRegistry.cleanup_dead(pid)
      {:error, :not_found} = ConnectionRegistry.get("conn-1")
    end

    test "cleanup_dead/1 handles non-existent PIDs gracefully" do
      fake_pid = spawn(fn -> :ok end)
      Process.exit(fake_pid, :kill)

      :ok = ConnectionRegistry.cleanup_dead(fake_pid)
    end
  end

  describe "shutdown" do
    test "shutdown/0 cleans up table on application shutdown" do
      pid = spawn(fn -> :timer.sleep(100) end)
      :ok = ConnectionRegistry.register("conn-1", pid)

      :ok = ConnectionRegistry.shutdown()
      :ok = ConnectionRegistry.init()

      {:error, :not_found} = ConnectionRegistry.get("conn-1")
    end

    test "shutdown/0 handles missing table gracefully" do
      :ok = ConnectionRegistry.shutdown()
      :ok = ConnectionRegistry.shutdown()
    end
  end

  describe "monitor cleanup verification" do
    test "cleanup_dead/1 properly demonitors before deletion" do
      pid = spawn(fn -> :timer.sleep(5000) end)
      :ok = ConnectionRegistry.register("conn-1", pid)

      :ok = ConnectionRegistry.cleanup_dead(pid)

      Process.exit(pid, :kill)
      refute_receive {:DOWN, _, :process, ^pid, _}, 100
    end

    test "cleanup_dead/1 handles multiple connections to same PID" do
      pid = spawn(fn -> :timer.sleep(5000) end)
      :ok = ConnectionRegistry.register("conn-1", pid)
      :ok = ConnectionRegistry.register("conn-2", pid)

      :ok = ConnectionRegistry.cleanup_dead(pid)

      {:error, :not_found} = ConnectionRegistry.get("conn-1")
      {:error, :not_found} = ConnectionRegistry.get("conn-2")

      Process.exit(pid, :kill)
      refute_receive {:DOWN, _, :process, ^pid, _}, 100
    end

    test "shutdown/0 demonitors all connections before table deletion" do
      pid1 = spawn(fn -> :timer.sleep(5000) end)
      pid2 = spawn(fn -> :timer.sleep(5000) end)

      :ok = ConnectionRegistry.register("conn-1", pid1)
      :ok = ConnectionRegistry.register("conn-2", pid2)

      :ok = ConnectionRegistry.shutdown()

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)

      refute_receive {:DOWN, _, :process, _, _}, 100
    end
  end
end
