defmodule ZenWebsocket.DiscoverableTest do
  @moduledoc """
  Tests for the Descripex.Discoverable integration on the root ZenWebsocket module.
  Verifies the three-level progressive disclosure API: describe/0, describe/1, describe/2.
  """

  use ExUnit.Case, async: true

  describe "describe/0 — library overview" do
    test "returns a list of module entries" do
      result = ZenWebsocket.describe()
      assert is_list(result)
      assert result != []
    end

    test "includes all registered discoverable modules" do
      result = ZenWebsocket.describe()
      module_names = Enum.map(result, & &1.module)

      # Client API modules
      assert ZenWebsocket.Client in module_names
      assert ZenWebsocket.Config in module_names
      assert ZenWebsocket.ClientSupervisor in module_names

      # Infrastructure modules
      assert ZenWebsocket.RateLimiter in module_names
      assert ZenWebsocket.PoolRouter in module_names
      assert ZenWebsocket.ConnectionRegistry in module_names

      # Observability modules
      assert ZenWebsocket.ErrorHandler in module_names
      assert ZenWebsocket.LatencyStats in module_names
      assert ZenWebsocket.Recorder in module_names
      assert ZenWebsocket.RecorderServer in module_names
      assert ZenWebsocket.Testing in module_names

      # Protocol modules
      assert ZenWebsocket.Frame in module_names
      assert ZenWebsocket.JsonRpc in module_names
      assert ZenWebsocket.MessageHandler in module_names
    end

    test "does not list Client-owned internal managers" do
      module_names = Enum.map(ZenWebsocket.describe(), & &1.module)

      refute ZenWebsocket.Reconnection in module_names
      refute ZenWebsocket.HeartbeatManager in module_names
      refute ZenWebsocket.SubscriptionManager in module_names
      refute ZenWebsocket.RequestCorrelator in module_names
    end
  end

  describe "describe/1 — module function list" do
    test "returns function details for a descripex-annotated module" do
      result = ZenWebsocket.describe(:client)
      assert is_list(result)
      assert result != []

      function_names = Enum.map(result, & &1.name)
      assert :connect in function_names
      assert :send_message in function_names
      assert :start_link in function_names
      assert :child_spec in function_names
    end

    test "returns the standalone connection registry API" do
      result = ZenWebsocket.describe(:connection_registry)
      function_names = Enum.map(result, & &1.name)

      assert :register in function_names
      assert :get in function_names
    end

    test "raises on unknown module shortname" do
      assert_raise ArgumentError, fn ->
        ZenWebsocket.describe(:nonexistent_module)
      end
    end
  end

  describe "describe/2 — full function detail" do
    test "returns full detail for a descripex-annotated function" do
      result = ZenWebsocket.describe(:client, :connect)
      assert is_map(result)
      assert result.name == :connect
    end

    test "returns nil for unknown function" do
      assert is_nil(ZenWebsocket.describe(:client, :nonexistent_function))
    end
  end
end
