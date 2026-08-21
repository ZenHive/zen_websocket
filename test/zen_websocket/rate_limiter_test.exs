defmodule ZenWebsocket.RateLimiterTest do
  use ExUnit.Case

  alias ZenWebsocket.RateLimiter

  @race_capacity 10_000_000
  @race_starting_tokens 5_000_000
  @race_refill_rate 10
  @race_refills 400
  @race_consumes 4_000
  @race_rounds 15
  @race_timeout_ms 30_000

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

      assert {:ok, %{tokens: 100, queue_size: 0, pressure_level: :none, suggested_delay_ms: 0}} =
               RateLimiter.status(name)
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

    test "does not retain requests when tokens are exhausted", %{name: name} do
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

      assert {:error, :rate_limited} = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 5, queue_size: 0}} = RateLimiter.status(name)
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

    test "refill does not spend tokens on requests that were never sent", %{name: name} do
      config = %{
        tokens: 2,
        refill_rate: 5,
        refill_interval: 60_000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      assert :ok = RateLimiter.consume(name, %{})
      assert :ok = RateLimiter.consume(name, %{})
      assert {:ok, %{tokens: 0, queue_size: 0}} = RateLimiter.status(name)

      for id <- 1..3 do
        assert {:error, :rate_limited} = RateLimiter.consume(name, %{id: id})
      end

      RateLimiter.refill(name)
      assert {:ok, %{tokens: 2, queue_size: 0}} = RateLimiter.status(name)

      assert :ok = RateLimiter.consume(name, %{id: 1})
      assert :ok = RateLimiter.consume(name, %{id: 2})
      assert {:ok, %{tokens: 0, queue_size: 0}} = RateLimiter.status(name)
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

    @tag timeout: 120_000
    test "overlapping consumes and refills preserve every token", %{name: name} do
      config = %{
        tokens: @race_capacity,
        refill_rate: @race_refill_rate,
        refill_interval: 60_000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      for _round <- 1..@race_rounds do
        :ets.insert(name, {:tokens, @race_starting_tokens})
        start_ref = make_ref()

        refiller =
          Task.async(fn ->
            receive do
              {:start, ^start_ref} ->
                Enum.each(1..@race_refills, fn _ -> RateLimiter.refill(name) end)
            end
          end)

        consumers =
          for _ <- 1..@race_consumes do
            Task.async(fn ->
              receive do
                {:start, ^start_ref} -> RateLimiter.consume(name, %{})
              end
            end)
          end

        {first_consumers, second_consumers} = Enum.split(consumers, div(@race_consumes, 2))
        Enum.each(first_consumers, &send(&1.pid, {:start, start_ref}))
        send(refiller.pid, {:start, start_ref})
        Enum.each(second_consumers, &send(&1.pid, {:start, start_ref}))

        [_refiller_result | consume_results] =
          Task.await_many([refiller | consumers], @race_timeout_ms)

        assert Enum.all?(consume_results, &(&1 == :ok))

        expected_tokens =
          @race_starting_tokens + @race_refills * @race_refill_rate - @race_consumes

        assert {:ok, %{tokens: tokens}} = RateLimiter.status(name)
        assert tokens <= @race_capacity
        assert tokens == expected_tokens
      end
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

  describe "telemetry events" do
    setup do
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_websocket, :rate_limiter, :consume],
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

  describe "recovery scenarios" do
    test "consume/2 succeeds again after refill", %{name: name} do
      config = %{
        tokens: 40,
        refill_rate: 40,
        refill_interval: 60_000,
        request_cost: fn _ -> 10 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      for id <- 1..4, do: assert(:ok = RateLimiter.consume(name, %{id: id}))
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{id: 5})
      assert {:error, :rate_limited} = RateLimiter.consume(name, %{id: 6})

      RateLimiter.refill(name)

      assert {:ok, %{tokens: 40, queue_size: 0}} = RateLimiter.status(name)

      assert :ok = RateLimiter.consume(name, %{id: 7})
      assert :ok = RateLimiter.consume(name, %{id: 8})
    end

    test "refill caps tokens at bucket capacity", %{name: name} do
      config = %{
        tokens: 10,
        refill_rate: 100,
        refill_interval: 60_000,
        request_cost: &RateLimiter.simple_cost/1
      }

      {:ok, ^name} = RateLimiter.init(name, config)
      RateLimiter.refill(name)
      RateLimiter.refill(name)

      {:ok, %{tokens: 10}} = RateLimiter.status(name)
    end

    test "concurrent consume calls don't lose tokens", %{name: name} do
      config = %{
        tokens: 100,
        refill_rate: 0,
        refill_interval: 60_000,
        request_cost: fn _ -> 1 end
      }

      {:ok, ^name} = RateLimiter.init(name, config)

      # 50 concurrent tasks each consuming 1 token
      tasks = for _ <- 1..50, do: Task.async(fn -> RateLimiter.consume(name, %{}) end)
      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))

      {:ok, %{tokens: 50}} = RateLimiter.status(name)
    end
  end
end
