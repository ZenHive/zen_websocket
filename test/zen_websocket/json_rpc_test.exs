defmodule ZenWebsocket.JsonRpcTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.JsonRpc

  describe "build_request/2" do
    test "builds request with method and params" do
      {:ok, request} = JsonRpc.build_request("public/auth", %{grant_type: "client_credentials"})

      assert request["jsonrpc"] == "2.0"
      assert request["method"] == "public/auth"
      assert request["params"] == %{grant_type: "client_credentials"}
      assert is_integer(request["id"])
      assert request["id"] > 0
    end

    test "builds request with method only" do
      {:ok, request} = JsonRpc.build_request("public/test")

      assert request["jsonrpc"] == "2.0"
      assert request["method"] == "public/test"
      refute Map.has_key?(request, "params")
      assert is_integer(request["id"])
    end

    test "generates unique IDs" do
      {:ok, req1} = JsonRpc.build_request("method1")
      {:ok, req2} = JsonRpc.build_request("method2")

      assert req1["id"] != req2["id"]
    end
  end

  describe "match_response/1" do
    test "matches successful result" do
      response = %{"jsonrpc" => "2.0", "id" => 123, "result" => %{"token" => "abc123"}}
      assert {:ok, %{"token" => "abc123"}} = JsonRpc.match_response(response)
    end

    test "matches error response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 123,
        "error" => %{"code" => -32_600, "message" => "Invalid request"}
      }

      assert {:error, {-32_600, "Invalid request"}} = JsonRpc.match_response(response)
    end

    test "matches notification" do
      response = %{
        "jsonrpc" => "2.0",
        "method" => "heartbeat",
        "params" => %{"type" => "test_request"}
      }

      assert {:notification, "heartbeat", %{"type" => "test_request"}} = JsonRpc.match_response(response)
    end

    test "matches result with extra fields" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 123,
        "result" => %{"data" => "value"},
        "usIn" => 1_234_567_890,
        "usOut" => 1_234_567_900,
        "usDiff" => 10
      }

      assert {:ok, %{"data" => "value"}} = JsonRpc.match_response(response)
    end

    test "matches null result" do
      response = %{"jsonrpc" => "2.0", "id" => 123, "result" => nil}
      assert {:ok, nil} = JsonRpc.match_response(response)
    end

    test "matches empty map result" do
      response = %{"jsonrpc" => "2.0", "id" => 123, "result" => %{}}
      assert {:ok, %{}} = JsonRpc.match_response(response)
    end
  end

  describe "match_response/1 edge cases" do
    test "returns function clause error for missing result and error" do
      response = %{"jsonrpc" => "2.0", "id" => 123}

      assert_raise FunctionClauseError, fn ->
        JsonRpc.match_response(response)
      end
    end

    test "returns function clause error for empty map" do
      assert_raise FunctionClauseError, fn ->
        JsonRpc.match_response(%{})
      end
    end

    test "notification without params raises" do
      response = %{"jsonrpc" => "2.0", "method" => "heartbeat"}

      assert_raise FunctionClauseError, fn ->
        JsonRpc.match_response(response)
      end
    end
  end

  describe "build_request/2 edge cases" do
    test "nil params excludes params key from request" do
      {:ok, request} = JsonRpc.build_request("test/method", nil)

      refute Map.has_key?(request, "params")
      assert request["method"] == "test/method"
    end

    test "empty map params includes params key" do
      {:ok, request} = JsonRpc.build_request("test/method", %{})

      assert Map.has_key?(request, "params")
      assert request["params"] == %{}
    end

    test "empty string method is allowed" do
      {:ok, request} = JsonRpc.build_request("")

      assert request["method"] == ""
      assert request["jsonrpc"] == "2.0"
      assert is_integer(request["id"])
      assert request["id"] > 0
    end

    test "build_request/1 and build_request/2 with nil are equivalent" do
      {:ok, request1} = JsonRpc.build_request("test/method")
      {:ok, request2} = JsonRpc.build_request("test/method", nil)

      # Both should exclude params key
      refute Map.has_key?(request1, "params")
      refute Map.has_key?(request2, "params")

      # Both should have the same structure (except unique IDs)
      assert request1["method"] == request2["method"]
      assert request1["jsonrpc"] == request2["jsonrpc"]
    end
  end

  describe "defrpc macro" do
    defmodule TestApi do
      @moduledoc false
      use JsonRpc

      defrpc(:authenticate, "public/auth")
      defrpc(:subscribe, "public/subscribe", doc: "Subscribe to market data channels")
    end

    test "generates function that builds request" do
      {:ok, request} = TestApi.authenticate(%{grant_type: "client_credentials"})

      assert request["method"] == "public/auth"
      assert request["params"] == %{grant_type: "client_credentials"}
    end

    test "generated function works without params" do
      {:ok, request} = TestApi.authenticate()

      assert request["method"] == "public/auth"
      assert request["params"] == %{}
    end
  end
end
