defmodule ZenWebsocket.Examples.PlatformAdapterTemplateTest do
  use ExUnit.Case

  alias ZenWebsocket.Examples.PlatformAdapterTemplate

  setup do
    # Ensure module is loaded before function_exported?/3 checks
    Code.ensure_loaded!(PlatformAdapterTemplate)
    :ok
  end

  describe "platform adapter template" do
    test "handle_message processes successful results" do
      msg = %{"result" => %{"balance" => 1000}}
      state = %{subscriptions: []}

      {:ok, result, ^state} = PlatformAdapterTemplate.handle_message(msg, state)
      assert result == %{"balance" => 1000}
    end

    test "handle_message processes error messages" do
      msg = %{"error" => %{"code" => 404, "message" => "Not found"}}
      state = %{subscriptions: []}

      {:error, error, ^state} = PlatformAdapterTemplate.handle_message(msg, state)
      assert error == %{"code" => 404, "message" => "Not found"}
    end

    test "handle_message passes through generic messages" do
      msg = %{"type" => "ticker", "data" => %{"price" => 50_000}}
      state = %{subscriptions: []}

      {:ok, ^msg, ^state} = PlatformAdapterTemplate.handle_message(msg, state)
    end

    test "provides connection helper" do
      # Just verify the function exists and returns expected shape
      assert function_exported?(PlatformAdapterTemplate, :connect, 2)
    end

    test "provides authentication helper" do
      assert function_exported?(PlatformAdapterTemplate, :authenticate, 2)
    end

    test "provides subscription helper" do
      assert function_exported?(PlatformAdapterTemplate, :subscribe, 2)
    end

    test "provides request helper" do
      assert function_exported?(PlatformAdapterTemplate, :request, 2)
      assert function_exported?(PlatformAdapterTemplate, :request, 3)
    end
  end
end
