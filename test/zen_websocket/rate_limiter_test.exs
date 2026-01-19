defmodule ZenWebsocket.RateLimiterTest do
  use ExUnit.Case

  alias ZenWebsocket.RateLimiter

  setup do
    name = :"rate_limiter_#{System.unique_integer()}"
    on_exit(fn -> RateLimiter.shutdown(name) end)
    {:ok, name: name}
  end

  describe "token bucket algorithm" do
    test "initializes with configured tokens", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 10,
        refill_interval: 1000,
        request_cost: &RateLimiter.simple_cost/1
      }

      assert {:ok, ^name} = RateLimiter.init(name, config)
      assert {:ok, %{tokens: 100, queue_size: 0}} = RateLimiter.status(name)
    end

    test "consumes tokens based on cost function", %{name: name} do
      config = %{
        tokens: 50,
        refill_rate: 10,
        refill_interval: 1000,
        request_cost: fn _ -> 10 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Consume 10 tokens
      assert :ok = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 40, queue_size: 0}} = RateLimiter.status(name)

      # Consume 40 more tokens
      assert :ok = RateLimiter.consume(name, %{})
      assert :ok = RateLimiter.consume(name, %{})
      assert :ok = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 10, queue_size: 0}} = RateLimiter.status(name)
    end

    test "queues requests when tokens exhausted", %{name: name} do
      config = %{
        tokens: 20,
        refill_rate: 10,
        refill_interval: 1000,
        request_cost: fn _ -> 15 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # First request consumes 15 tokens
      assert :ok = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 5, queue_size: 0}} = RateLimiter.status(name)

      # Second request needs 15 but only 5 available - should queue
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 5, queue_size: 1}} = RateLimiter.status(name)
    end

    test "returns queue_full error when queue limit reached", %{name: name} do
      config = %{
        tokens: 1,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 10 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Fill queue to limit (100)
      for _ <- 1..100 do
        assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      end

      # Next request should fail with queue_full
      assert {:error, :queue_full} = RateLimiter.consume(name, %{})
    end

    test "refills tokens at configured rate", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 25,
        refill_interval: 50,
        request_cost: fn _ -> 50 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Consume 50 tokens
      assert :ok = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 50, queue_size: 0}} = RateLimiter.status(name)

      # Manual refill adds 25 tokens
      RateLimiter.refill(name)
      assert {:ok, %{tokens: 75, queue_size: 0}} = RateLimiter.status(name)
    end

    test "processes queue when tokens available", %{name: name} do
      config = %{
        tokens: 10,
        refill_rate: 20,
        refill_interval: 100,
        request_cost: fn _ -> 15 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Queue request needing 15 tokens
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 10, queue_size: 1}} = RateLimiter.status(name)

      # Refill adds 20 tokens, should process queued request
      RateLimiter.refill(name)
      assert {:ok, %{tokens: 15, queue_size: 0}} = RateLimiter.status(name)
    end
  end

  describe "exchange-specific cost functions" do
    test "deribit_cost calculates based on method type" do
      assert 1 = RateLimiter.deribit_cost(%{"method" => "public/get_instruments"})
      assert 5 = RateLimiter.deribit_cost(%{"method" => "private/get_positions"})
      assert 10 = RateLimiter.deribit_cost(%{"method" => "private/set_heartbeat"})
      assert 15 = RateLimiter.deribit_cost(%{"method" => "private/buy"})
      assert 15 = RateLimiter.deribit_cost(%{"method" => "private/sell"})
      assert 5 = RateLimiter.deribit_cost(%{"method" => "unknown"})
    end

    test "binance_cost calculates based on endpoint" do
      assert 2 = RateLimiter.binance_cost(%{"method" => "klines"})
      assert 1 = RateLimiter.binance_cost(%{"method" => "ticker"})
      assert 1 = RateLimiter.binance_cost(%{"method" => "depth"})
      assert 1 = RateLimiter.binance_cost(%{"method" => "order"})
      assert 1 = RateLimiter.binance_cost(%{"method" => "unknown"})
    end

    test "simple_cost always returns 1" do
      assert 1 = RateLimiter.simple_cost(%{})
      assert 1 = RateLimiter.simple_cost("anything")
      assert 1 = RateLimiter.simple_cost(nil)
    end
  end

  describe "configuration examples" do
    test "deribit configuration with credit system", %{name: name} do
      config = %{
        tokens: 1500,
        refill_rate: 1000,
        refill_interval: 1000,
        request_cost: &RateLimiter.deribit_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Public request costs 1 credit
      assert :ok = RateLimiter.consume(name, %{"method" => "public/ticker"})
      assert {:ok, %{tokens: 1499, queue_size: 0}} = RateLimiter.status(name)

      # Order costs 15 credits
      assert :ok = RateLimiter.consume(name, %{"method" => "private/buy"})
      assert {:ok, %{tokens: 1484, queue_size: 0}} = RateLimiter.status(name)
    end

    test "binance configuration with weight system", %{name: name} do
      config = %{
        tokens: 60,
        refill_rate: 60,
        refill_interval: 1000,
        request_cost: &RateLimiter.binance_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Klines costs 2 weight
      assert :ok = RateLimiter.consume(name, %{"method" => "klines"})
      assert {:ok, %{tokens: 58, queue_size: 0}} = RateLimiter.status(name)
    end

    test "coinbase configuration with simple rate", %{name: name} do
      config = %{
        tokens: 15,
        refill_rate: 15,
        refill_interval: 1000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Each request costs 1 token
      for i <- 1..15 do
        assert :ok = RateLimiter.consume(name, %{id: i})
      end

      assert {:ok, %{tokens: 0, queue_size: 0}} = RateLimiter.status(name)

      # 16th request should be rate limited
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{id: 16})
    end
  end

  describe "concurrent access" do
    test "handles concurrent token consumption", %{name: name} do
      config = %{
        tokens: 1000,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 1 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Spawn 100 concurrent processes each consuming 10 tokens
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            for _ <- 1..10 do
              RateLimiter.consume(name, %{})
            end
          end)
        end

      Task.await_many(tasks)

      # Should have consumed exactly 1000 tokens
      assert {:ok, %{tokens: 0}} = RateLimiter.status(name)
    end
  end

  describe "shutdown/1" do
    test "deletes ETS table", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 10,
        refill_interval: 1000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)
      assert :ets.whereis(name) != :undefined

      :ok = RateLimiter.shutdown(name)
      assert :ets.whereis(name) == :undefined
    end

    test "returns :ok when table already deleted", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 10,
        refill_interval: 1000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)
      :ok = RateLimiter.shutdown(name)

      # Second shutdown should still return :ok
      assert :ok = RateLimiter.shutdown(name)
    end
  end

  describe "configurable max_queue_size" do
    test "respects custom max_queue_size", %{name: name} do
      config = %{
        tokens: 1,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 10 end,
        max_queue_size: 5
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Fill queue to custom limit (5)
      for _ <- 1..5 do
        assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      end

      # Next request should fail with queue_full
      assert {:error, :queue_full} = RateLimiter.consume(name, %{})
    end

    test "uses default max_queue_size of 100 when not specified", %{name: name} do
      config = %{
        tokens: 1,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 10 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Fill queue to default limit (100)
      for _ <- 1..100 do
        assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      end

      # 101st request should fail with queue_full
      assert {:error, :queue_full} = RateLimiter.consume(name, %{})
    end
  end

  describe "telemetry events" do
    setup do
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_websocket, :rate_limiter, :consume],
          [:zen_websocket, :rate_limiter, :queue],
          [:zen_websocket, :rate_limiter, :queue_full],
          [:zen_websocket, :rate_limiter, :refill]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits telemetry on successful consume", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 10,
        refill_interval: 10_000,
        request_cost: fn _ -> 5 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)
      :ok = RateLimiter.consume(name, %{})

      assert_receive {:telemetry, [:zen_websocket, :rate_limiter, :consume], measurements, metadata}

      assert measurements.tokens_remaining == 95
      assert measurements.cost == 5
      assert metadata.name == name
    end

    test "emits telemetry on queue", %{name: name} do
      config = %{
        tokens: 1,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 10 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)
      {:error, :rate_limited} = RateLimiter.consume(name, %{})

      assert_receive {:telemetry, [:zen_websocket, :rate_limiter, :queue], measurements, metadata}
      assert measurements.queue_size == 1
      assert measurements.cost == 10
      assert metadata.name == name
    end

    test "emits telemetry on queue_full", %{name: name} do
      config = %{
        tokens: 1,
        refill_rate: 0,
        refill_interval: 10_000,
        request_cost: fn _ -> 10 end,
        max_queue_size: 2
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Fill the queue
      {:error, :rate_limited} = RateLimiter.consume(name, %{})
      {:error, :rate_limited} = RateLimiter.consume(name, %{})

      # Clear queue events
      receive do
        {:telemetry, [:zen_websocket, :rate_limiter, :queue], _, _} -> :ok
      end

      receive do
        {:telemetry, [:zen_websocket, :rate_limiter, :queue], _, _} -> :ok
      end

      # Trigger queue_full
      {:error, :queue_full} = RateLimiter.consume(name, %{})

      assert_receive {:telemetry, [:zen_websocket, :rate_limiter, :queue_full], measurements, metadata}

      assert measurements.queue_size == 2
      assert metadata.name == name
    end

    test "emits telemetry on refill", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 25,
        refill_interval: 10_000,
        request_cost: fn _ -> 50 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # Consume some tokens
      :ok = RateLimiter.consume(name, %{})

      # Clear consume event
      receive do
        {:telemetry, [:zen_websocket, :rate_limiter, :consume], _, _} -> :ok
      end

      # Trigger refill
      RateLimiter.refill(name)

      assert_receive {:telemetry, [:zen_websocket, :rate_limiter, :refill], measurements, metadata}
      assert measurements.tokens_before == 50
      assert measurements.tokens_after == 75
      assert measurements.refill_rate == 25
      assert metadata.name == name
    end
  end
end
