defmodule ZenWebsocket.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for WebSocket API calls.

  Prevents rate limit violations with configurable cost functions
  supporting credit-based (Deribit), weight-based (Binance), and
  simple rate limit (Coinbase) patterns through single algorithm.

  ## Timer Ownership

  The rate limiter schedules periodic refill timers using `Process.send_after/3`.
  These timers are sent to the process that calls `init/1`. The calling process
  must handle `{:refill, name}` messages by calling `refill/1`:

      def handle_info({:refill, name}, state) do
        ZenWebsocket.RateLimiter.refill(name)
        {:noreply, state}
      end

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

  @type pressure_level :: :none | :low | :medium | :high

  @type state :: %{
          tokens: non_neg_integer(),
          last_refill: integer(),
          queue: :queue.queue(),
          pressure_level: pressure_level()
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
      queue: :queue.new(),
      pressure_level: :none
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

    # Cap tokens at bucket capacity (config.tokens) to prevent unbounded accumulation
    new_tokens = min(current_tokens + config.refill_rate, config.tokens)
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
  Returns current token count, queue size, pressure level, and suggested delay.

  The `suggested_delay_ms` provides backpressure guidance:
  - `:high` pressure (75%+) → `refill_interval * 4`
  - `:medium` pressure (50%+) → `refill_interval * 2`
  - `:low` pressure (25%+) → `refill_interval`
  - `:none` → `0`
  """
  @spec status(atom()) ::
          {:ok,
           %{
             tokens: non_neg_integer(),
             queue_size: non_neg_integer(),
             pressure_level: pressure_level(),
             suggested_delay_ms: non_neg_integer()
           }}
  def status(name) do
    [{:tokens, tokens}] = :ets.lookup(name, :tokens)
    [{:state, state}] = :ets.lookup(name, :state)
    [{:config, config}] = :ets.lookup(name, :config)

    pressure_level = Map.get(state, :pressure_level, :none)
    suggested_delay = calculate_suggested_delay(pressure_level, config.refill_interval)

    {:ok,
     %{
       tokens: tokens,
       queue_size: :queue.len(state.queue),
       pressure_level: pressure_level,
       suggested_delay_ms: suggested_delay
     }}
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

  # Pressure thresholds as percentage of max_queue_size
  @pressure_threshold_low 0.25
  @pressure_threshold_medium 0.50
  @pressure_threshold_high 0.75

  # Private functions

  @doc false
  defp calculate_suggested_delay(:high, refill_interval), do: refill_interval * 4
  defp calculate_suggested_delay(:medium, refill_interval), do: refill_interval * 2
  defp calculate_suggested_delay(:low, refill_interval), do: refill_interval
  defp calculate_suggested_delay(:none, _refill_interval), do: 0

  @doc false
  defp calculate_pressure_level(queue_len, max_queue_size) do
    ratio = queue_len / max_queue_size

    cond do
      ratio >= @pressure_threshold_high -> :high
      ratio >= @pressure_threshold_medium -> :medium
      ratio >= @pressure_threshold_low -> :low
      true -> :none
    end
  end

  @doc false
  defp check_and_emit_pressure(name, state, config) do
    max_queue = Map.get(config, :max_queue_size, @default_max_queue_size)
    queue_len = :queue.len(state.queue)
    new_level = calculate_pressure_level(queue_len, max_queue)
    old_level = Map.get(state, :pressure_level, :none)

    if new_level == old_level do
      state
    else
      ratio = queue_len / max_queue

      :telemetry.execute(
        [:zen_websocket, :rate_limiter, :pressure],
        %{queue_size: queue_len, ratio: ratio},
        %{name: name, level: new_level, previous_level: old_level}
      )

      new_state = %{state | pressure_level: new_level}
      :ets.insert(name, {:state, new_state})
      new_state
    end
  end

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

      # Check and emit pressure event after queuing
      check_and_emit_pressure(name, new_state, config)

      {:error, :rate_limited}
    end
  end

  defp process_queue_with_tokens(name, _state, _tokens, _config) do
    [{:tokens, current_tokens}] = :ets.lookup(name, :tokens)
    [{:state, state}] = :ets.lookup(name, :state)
    [{:config, config}] = :ets.lookup(name, :config)

    case :queue.out(state.queue) do
      {{:value, {_request, cost}}, new_queue} when current_tokens >= cost ->
        :ets.update_counter(name, :tokens, {2, -cost})
        new_state = %{state | queue: new_queue}
        :ets.insert(name, {:state, new_state})

        # Check and emit pressure event after dequeue
        check_and_emit_pressure(name, new_state, config)

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
