defmodule ZenWebsocket.CorrelationTest do
  @moduledoc """
  Tests for request/response correlation in WebSocket Client using real APIs.
  """

  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @deribit_test_url "wss://test.deribit.com/ws/api/v2"

  describe "request/response correlation" do
    test "correlates JSON-RPC request with response" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Send request with ID
      request =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/test",
          "params" => %{},
          "id" => 1
        })

      # Should receive correlated response with same ID
      assert {:ok, %{"id" => 1, "jsonrpc" => "2.0", "result" => %{"version" => _}}} =
               Client.send_message(client, request)

      Client.close(client)
    end

    test "returns timeout error when response doesn't arrive" do
      # Use mock server that doesn't respond to test timeout
      {:ok, server, port} = MockWebSockServer.start_link()

      # Set handler to ignore messages with ID 2 (don't respond)
      MockWebSockServer.set_handler(server, fn
        {:text, msg} ->
          case Jason.decode(msg) do
            {:ok, %{"id" => 2}} ->
              # Ignore this request - don't respond
              :ok

            {:ok, _other} ->
              # Respond to other requests normally
              {:reply, {:text, Jason.encode!(%{"id" => 1, "result" => "ok"})}}

            _ ->
              :ok
          end

        _ ->
          :ok
      end)

      url = "ws://localhost:#{port}/ws"
      {:ok, client} = Client.connect(url, request_timeout: 100)

      request =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "test",
          "params" => %{},
          "id" => 2
        })

      # Server ignores ID 2, so we should get timeout
      assert {:error, :timeout} = Client.send_message(client, request)

      Client.close(client)
      MockWebSockServer.stop(server)
    end

    test "handles non-JSON messages without correlation" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Plain text message - no correlation, returns immediately
      assert :ok = Client.send_message(client, "plain text message")

      Client.close(client)
    end

    test "handles JSON messages without ID field" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # JSON notification without ID - no correlation
      notification =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/subscribe",
          "params" => %{"channels" => ["deribit_price_index.btc_usd"]}
        })

      # Should return immediately without waiting for response
      assert :ok = Client.send_message(client, notification)

      Client.close(client)
    end

    test "handles multiple concurrent requests" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Send multiple requests concurrently
      tasks =
        for id <- 1..5 do
          Task.async(fn ->
            request =
              Jason.encode!(%{
                "jsonrpc" => "2.0",
                "method" => "public/get_time",
                "params" => %{},
                "id" => id
              })

            Client.send_message(client, request)
          end)
        end

      # All requests should receive their correlated responses
      results = Task.await_many(tasks, 10_000)

      for {result, index} <- Enum.with_index(results, 1) do
        assert {:ok, %{"result" => timestamp, "id" => ^index}} = result
        assert is_integer(timestamp)
      end

      Client.close(client)
    end

    test "handles string IDs in correlation" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Test with string ID
      request =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/test",
          "params" => %{},
          "id" => "test-id-123"
        })

      assert {:ok, %{"id" => "test-id-123", "result" => _}} =
               Client.send_message(client, request)

      Client.close(client)
    end

    test "different requests with same method get correct responses" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Send two requests with same method but different IDs
      request1 =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/get_currencies",
          "params" => %{},
          "id" => 100
        })

      request2 =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "public/get_currencies",
          "params" => %{},
          "id" => 200
        })

      # Send both requests
      task1 = Task.async(fn -> Client.send_message(client, request1) end)
      task2 = Task.async(fn -> Client.send_message(client, request2) end)

      # Both should get their correctly correlated responses
      {:ok, %{"id" => 100, "result" => currencies1}} = Task.await(task1)
      {:ok, %{"id" => 200, "result" => currencies2}} = Task.await(task2)

      # Results should be the same (same method) but IDs different
      assert currencies1 == currencies2
      assert is_list(currencies1)

      Client.close(client)
    end
  end

  describe "correlation edge cases" do
    test "handles rapid fire requests" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Send 20 requests as fast as possible
      tasks =
        for id <- 1000..1019 do
          Task.async(fn ->
            request =
              Jason.encode!(%{
                "jsonrpc" => "2.0",
                "method" => "public/test",
                "params" => %{},
                "id" => id
              })

            Client.send_message(client, request)
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All should succeed with correct IDs
      for {result, offset} <- Enum.with_index(results) do
        expected_id = 1000 + offset
        assert {:ok, %{"id" => ^expected_id}} = result
      end

      Client.close(client)
    end

    test "mixed correlated and non-correlated messages" do
      {:ok, client} = Client.connect(@deribit_test_url)

      # Mix of messages with and without IDs
      tasks = [
        Task.async(fn ->
          # With ID
          req = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "public/test", "params" => %{}, "id" => 1})
          Client.send_message(client, req)
        end),
        Task.async(fn ->
          # Without ID (notification)
          notif = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "heartbeat", "params" => %{"type" => "test"}})
          Client.send_message(client, notif)
        end),
        Task.async(fn ->
          # With ID
          req = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "public/get_time", "params" => %{}, "id" => 2})
          Client.send_message(client, req)
        end)
      ]

      [res1, res2, res3] = Task.await_many(tasks)

      # First should get response with ID 1
      assert {:ok, %{"id" => 1}} = res1

      # Second should return :ok (no correlation)
      assert :ok = res2

      # Third should get response with ID 2
      assert {:ok, %{"id" => 2}} = res3

      Client.close(client)
    end
  end
end
