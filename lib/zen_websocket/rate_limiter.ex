defmodule ZenWebsocket.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for WebSocket API calls.

  Prevents rate limit violations with configurable cost functions
  supporting credit-based (Deribit), weight-based (Binance), and
  simple rate limit (Coinbase) patterns through single algorithm.

  ## Memory Characteristics

  Each rate limiter creates one named ETS table containing:
  - Configuration map (~200 bytes)
  - State with queue (grows with queued requests)
  - Token counter (8 bytes)

  **Cleanup:** Call `shutdown/1` when done to delete the ETS table.
  Tables are NOT automatically cleaned up on process termination.
  """

  @type config :: %{
          optional(:max_queue_size) => pos_integer(),
          tokens: pos_integer(),
          refill_rate: pos_integer(),
          refill_interval: pos_integer(),
          request_cost: (term() -> pos_integer())
        }

  @default_max_queue_size 100

  @type state :: %{
          tokens: non_neg_integer(),
          last_refill: integer(),
          queue: :queue.queue()
        }

  @doc """
  Initializes rate limiter with configuration.

  Creates ETS table for state storage and schedules refill timer.
  """
  @spec init(atom(), config()) :: {:ok, atom()} | {:error, term()}
  def init(name, config) do
    table = :ets.new(name, [:named_table, :public, :set])

    state = %{
      last_refill: System.monotonic_time(:millisecond),
      queue: :queue.new()
    }

    :ets.insert(table, {:state, state})
    :ets.insert(table, {:config, config})
    :ets.insert(table, {:tokens, config.tokens})
    schedule_refill(name, config.refill_interval)

    {:ok, name}
  end

  @doc """
  Attempts to consume tokens for a request.

  Returns :ok if tokens available, queues request if not.
  """
  @spec consume(atom(), term()) :: :ok | {:error, :rate_limited | :queue_full}
  def consume(name, request) do
    [{:config, config}] = :ets.lookup(name, :config)
    cost = config.request_cost.(request)

    # Use ETS atomic update for thread-safe token consumption
    case :ets.update_counter(name, :tokens, {2, -cost}, {:tokens, cost}) do
      tokens when tokens >= 0 ->
        :telemetry.execute(
          [:zen_websocket, :rate_limiter, :consume],
          %{tokens_remaining: tokens, cost: cost},
          %{name: name}
        )

        :ok

      _ ->
        # Restore tokens and handle rate limit
        :ets.update_counter(name, :tokens, {2, cost})
        [{:state, state}] = :ets.lookup(name, :state)
        handle_rate_limit(name, state, request, cost, config)
    end
  end

  @doc """
  Refills tokens at configured rate.

  Called by timer process at refill intervals.
  """
  @spec refill(atom()) :: :ok
  def refill(name) do
    [{:config, config}] = :ets.lookup(name, :config)
    [{:tokens, current_tokens}] = :ets.lookup(name, :tokens)

    # The config.tokens is the max capacity, not the refill amount
    new_tokens = current_tokens + config.refill_rate
    :ets.insert(name, {:tokens, new_tokens})

    :telemetry.execute(
      [:zen_websocket, :rate_limiter, :refill],
      %{tokens_before: current_tokens, tokens_after: new_tokens, refill_rate: config.refill_rate},
      %{name: name}
    )

    [{:state, state}] = :ets.lookup(name, :state)
    process_queue_with_tokens(name, state, new_tokens, config)
    schedule_refill(name, config.refill_interval)

    :ok
  end

  @doc """
  Returns current token count and queue size.
  """
  @spec status(atom()) :: {:ok, %{tokens: non_neg_integer(), queue_size: non_neg_integer()}}
  def status(name) do
    [{:tokens, tokens}] = :ets.lookup(name, :tokens)
    [{:state, state}] = :ets.lookup(name, :state)
    {:ok, %{tokens: tokens, queue_size: :queue.len(state.queue)}}
  end

  @doc """
  Cleans up rate limiter resources.

  Deletes the ETS table. Should be called when the rate limiter is no longer needed.
  """
  @spec shutdown(atom()) :: :ok
  def shutdown(name) do
    if :ets.whereis(name) != :undefined, do: :ets.delete(name)
    :ok
  end

  # Private functions

  defp handle_rate_limit(name, state, request, cost, config) do
    max_queue = Map.get(config, :max_queue_size, @default_max_queue_size)
    queue = state.queue
    queue_len = :queue.len(queue)

    if queue_len >= max_queue do
      :telemetry.execute(
        [:zen_websocket, :rate_limiter, :queue_full],
        %{queue_size: queue_len},
        %{name: name}
      )

      {:error, :queue_full}
    else
      :telemetry.execute(
        [:zen_websocket, :rate_limiter, :queue],
        %{queue_size: queue_len + 1, cost: cost},
        %{name: name}
      )

      new_queue = :queue.in({request, cost}, queue)
      new_state = %{state | queue: new_queue}
      :ets.insert(name, {:state, new_state})
      {:error, :rate_limited}
    end
  end

  defp process_queue_with_tokens(name, _state, _tokens, _config) do
    [{:tokens, current_tokens}] = :ets.lookup(name, :tokens)
    [{:state, state}] = :ets.lookup(name, :state)

    case :queue.out(state.queue) do
      {{:value, {_request, cost}}, new_queue} when current_tokens >= cost ->
        :ets.update_counter(name, :tokens, {2, -cost})
        new_state = %{state | queue: new_queue}
        :ets.insert(name, {:state, new_state})
        process_queue_with_tokens(name, new_state, current_tokens - cost, nil)

      _ ->
        :ok
    end
  end

  defp schedule_refill(name, interval) do
    Process.send_after(self(), {:refill, name}, interval)
  end

  # Exchange-specific cost functions

  @doc """
  Deribit credit-based cost function.
  """
  @spec deribit_cost(map()) :: pos_integer()
  def deribit_cost(%{"method" => method}) do
    case method do
      "public/" <> _ -> 1
      "private/get_" <> _ -> 5
      "private/set_" <> _ -> 10
      "private/buy" -> 15
      "private/sell" -> 15
      _ -> 5
    end
  end

  @doc """
  Binance weight-based cost function.
  """
  @spec binance_cost(map()) :: pos_integer()
  def binance_cost(%{"method" => method}) do
    case method do
      "klines" -> 2
      "ticker" -> 1
      "depth" -> 1
      "order" -> 1
      _ -> 1
    end
  end

  @doc """
  Simple cost function for fixed-rate exchanges.
  """
  @spec simple_cost(term()) :: pos_integer()
  def simple_cost(_request), do: 1
end
