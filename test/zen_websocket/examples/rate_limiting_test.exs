defmodule ZenWebsocket.Examples.RateLimitingTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.RateLimiter

  describe "rate limiting configuration" do
    test "creates rate limiter with token bucket configuration" do
      name = :test_limiter_1

      config = %{
        tokens: 10,
        refill_rate: 10,
        refill_interval: 100,
        request_cost: &RateLimiter.simple_cost/1
      }

      assert {:ok, ^name} = RateLimiter.init(name, config)
      assert {:ok, %{tokens: 10, queue_size: 0}} = RateLimiter.status(name)
    end

    test "supports burst capacity" do
      name = :test_limiter_burst

      config = %{
        tokens: 20,
        refill_rate: 10,
        refill_interval: 100,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Can burst up to 20 requests
      for _ <- 1..20 do
        assert :ok = RateLimiter.consume(name, %{})
      end

      # 21st request is rate limited
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
    end
  end

  describe "rate limited client integration" do
    @describetag :integration
    test "enforces rate limits on WebSocket messages" do
      limiter_name = :test_client_limiter

      config = %{
        tokens: 5,
        refill_rate: 5,
        refill_interval: 100,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^limiter_name} = RateLimiter.init(limiter_name, config)
      {:ok, client} = Client.connect("wss://echo.websocket.org")

      # Send messages up to limit
      for i <- 1..5 do
        assert :ok = RateLimiter.consume(limiter_name, %{"id" => i})
        assert :ok = Client.send_message(client, "Message #{i}")
      end

      # Next message should be rate limited
      assert {:error, :rate_limited} = RateLimiter.consume(limiter_name, %{"id" => 6})

      # Wait for refill (need at least one full refill interval)
      Process.sleep(200)

      # Manually trigger refill to ensure it happened
      RateLimiter.refill(limiter_name)

      # Should be able to send again
      assert :ok = RateLimiter.consume(limiter_name, %{"id" => 7})
      assert :ok = Client.send_message(client, "Message 7")

      :ok = Client.close(client)
    end

    test "handles different cost functions for API compliance" do
      # Deribit-style credit system
      deribit_limiter = :test_deribit_limiter

      deribit_config = %{
        tokens: 100,
        refill_rate: 20,
        refill_interval: 100,
        request_cost: &RateLimiter.deribit_cost/1
      }

      {:ok, ^deribit_limiter} = RateLimiter.init(deribit_limiter, deribit_config)

      # Public method costs 1 credit
      assert :ok = RateLimiter.consume(deribit_limiter, %{"method" => "public/get_ticker"})
      assert {:ok, %{tokens: 99}} = RateLimiter.status(deribit_limiter)

      # Private read costs 5 credits
      assert :ok = RateLimiter.consume(deribit_limiter, %{"method" => "private/get_positions"})
      assert {:ok, %{tokens: 94}} = RateLimiter.status(deribit_limiter)

      # Trading costs 15 credits
      assert :ok = RateLimiter.consume(deribit_limiter, %{"method" => "private/buy"})
      assert {:ok, %{tokens: 79}} = RateLimiter.status(deribit_limiter)
    end
  end

  describe "queue management" do
    test "queues requests when rate limited" do
      queue_limiter = :test_queue_limiter

      config = %{
        tokens: 2,
        refill_rate: 2,
        refill_interval: 100,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^queue_limiter} = RateLimiter.init(queue_limiter, config)

      # Consume all tokens
      assert :ok = RateLimiter.consume(queue_limiter, %{"id" => 1})
      assert :ok = RateLimiter.consume(queue_limiter, %{"id" => 2})

      # Next requests are queued
      assert {:error, :rate_limited} = RateLimiter.consume(queue_limiter, %{"id" => 3})
      assert {:ok, %{tokens: 0, queue_size: 1}} = RateLimiter.status(queue_limiter)

      assert {:error, :rate_limited} = RateLimiter.consume(queue_limiter, %{"id" => 4})
      assert {:ok, %{tokens: 0, queue_size: 2}} = RateLimiter.status(queue_limiter)
    end

    test "prevents queue overflow" do
      overflow_limiter = :test_overflow_limiter

      config = %{
        tokens: 1,
        refill_rate: 1,
        refill_interval: 1000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^overflow_limiter} = RateLimiter.init(overflow_limiter, config)

      # Consume token
      assert :ok = RateLimiter.consume(overflow_limiter, %{"id" => 0})

      # Fill queue to max (100 items)
      for i <- 1..100 do
        assert {:error, :rate_limited} = RateLimiter.consume(overflow_limiter, %{"id" => i})
      end

      # Queue is full
      assert {:error, :queue_full} = RateLimiter.consume(overflow_limiter, %{"id" => 101})
    end
  end

  describe "real-world rate limiting patterns" do
    @describetag :integration
    test "handles high-frequency trading with rate limits" do
      trading_limiter = :test_trading_limiter

      config = %{
        tokens: 50,
        refill_rate: 50,
        refill_interval: 1000,
        request_cost: fn
          %{"type" => "order"} -> 5
          %{"type" => "cancel"} -> 2
          %{"type" => "query"} -> 1
          _ -> 1
        end
      }

      {:ok, ^trading_limiter} = RateLimiter.init(trading_limiter, config)
      {:ok, client} = Client.connect("wss://echo.websocket.org")

      # Simulate trading session
      _results =
        Enum.reduce(1..5, [], fn i, acc ->
          order = %{"type" => "order", "id" => i, "action" => "buy"}

          case RateLimiter.consume(trading_limiter, order) do
            :ok ->
              case Client.send_message(client, Jason.encode!(order)) do
                :ok -> acc ++ [{:sent, i}]
                # echo response
                {:ok, _} -> acc ++ [{:sent, i}]
              end

            {:error, reason} ->
              acc ++ [{:limited, i, reason}]
          end
        end)

      # Query positions
      for i <- 1..10 do
        query = %{"type" => "query", "id" => i}

        case RateLimiter.consume(trading_limiter, query) do
          :ok ->
            case Client.send_message(client, Jason.encode!(query)) do
              :ok -> :ok
              # echo response
              {:ok, _} -> :ok
            end

          _ ->
            :ok
        end
      end

      # Status check
      {:ok, status} = RateLimiter.status(trading_limiter)
      assert status.tokens < 50
      assert status.tokens >= 0

      :ok = Client.close(client)
    end

    test "implements exchange-specific rate limiting" do
      # Test with Binance-style weight system
      binance_limiter = :test_binance_limiter

      binance_config = %{
        # Binance 1200 weight limit per minute
        tokens: 1200,
        refill_rate: 1200,
        refill_interval: 60_000,
        request_cost: &RateLimiter.binance_cost/1
      }

      {:ok, ^binance_limiter} = RateLimiter.init(binance_limiter, binance_config)

      # Different endpoints have different weights
      assert :ok = RateLimiter.consume(binance_limiter, %{"method" => "ticker"})
      assert {:ok, %{tokens: 1199}} = RateLimiter.status(binance_limiter)

      assert :ok = RateLimiter.consume(binance_limiter, %{"method" => "klines"})
      assert {:ok, %{tokens: 1197}} = RateLimiter.status(binance_limiter)
    end
  end

  describe "Deribit testnet rate limiting" do
    @describetag :integration
    test "respects Deribit credit limits" do
      deribit_limiter = :test_deribit_real_limiter

      deribit_config = %{
        # Deribit credit limit
        tokens: 200,
        # 40 credits per second
        refill_rate: 40,
        refill_interval: 1000,
        request_cost: &RateLimiter.deribit_cost/1
      }

      {:ok, ^deribit_limiter} = RateLimiter.init(deribit_limiter, deribit_config)

      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if is_nil(client_id) or is_nil(client_secret) do
        flunk("""
        Missing Deribit testnet credentials!

        Set these environment variables:
          export DERIBIT_CLIENT_ID="your_client_id"
          export DERIBIT_CLIENT_SECRET="your_client_secret"

        Get credentials at: https://test.deribit.com
        """)
      end

      {:ok, client} = Client.connect("wss://test.deribit.com/ws/api/v2")

      # Auth request
      auth_msg = %{
        "jsonrpc" => "2.0",
        "method" => "public/auth",
        "params" => %{
          "grant_type" => "client_credentials",
          "client_id" => client_id,
          "client_secret" => client_secret
        },
        "id" => 1
      }

      # Check rate limit before sending
      assert :ok = RateLimiter.consume(deribit_limiter, auth_msg)

      # send_message blocks for correlated JSON-RPC (has "id") and returns response
      case Client.send_message(client, Jason.encode!(auth_msg)) do
        :ok -> :ok
        {:ok, _} -> :ok
        error -> flunk("Unexpected error: #{inspect(error)}")
      end

      # Multiple ticker requests
      for i <- 1..5 do
        ticker_msg = %{
          "jsonrpc" => "2.0",
          "method" => "public/get_ticker",
          "params" => %{"instrument_name" => "BTC-PERPETUAL"},
          "id" => i + 1
        }

        case RateLimiter.consume(deribit_limiter, ticker_msg) do
          :ok ->
            case Client.send_message(client, Jason.encode!(ticker_msg)) do
              :ok -> :ok
              {:ok, _} -> :ok
              error -> flunk("Unexpected error: #{inspect(error)}")
            end

          {:error, :rate_limited} ->
            # Expected when we hit limits
            :ok
        end
      end

      :ok = Client.close(client)
    end
  end
end
