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
  - Token counter (8 bytes)

  **Cleanup:** Call `shutdown/1` when done to delete the ETS table.
  Tables are NOT automatically cleaned up on process termination.
  """

  use Descripex, namespace: "/rate_limiting"

  @type config :: %{
          tokens: pos_integer(),
          refill_rate: pos_integer(),
          refill_interval: pos_integer(),
          request_cost: (term() -> pos_integer())
        }

  @type pressure_level :: :none | :low | :medium | :high

  api(:init, "Initialize a token bucket rate limiter with ETS storage.",
    params: [
      name: [kind: :value, description: "Unique atom name for the rate limiter ETS table"],
      config: [kind: :value, description: "Configuration map with tokens, refill_rate, refill_interval, request_cost"]
    ],
    returns: %{type: "{:ok, atom()} | {:error, term()}", description: "The rate limiter name on success"}
  )

  @doc """
  Initializes rate limiter with configuration.

  Creates ETS table for state storage and schedules refill timer.
  """
  @spec init(atom(), config()) :: {:ok, atom()} | {:error, term()}
  def init(name, config) do
    table = :ets.new(name, [:named_table, :public, :set])

    :ets.insert(table, {:config, config})
    :ets.insert(table, {:tokens, config.tokens})
    schedule_refill(name, config.refill_interval)

    {:ok, name}
  end

  api(:consume, "Attempt to consume tokens for a request.",
    params: [
      name: [kind: :value, description: "Rate limiter name"],
      request: [kind: :value, description: "Request term passed to the cost function"]
    ],
    returns: %{
      type: ":ok | {:error, :rate_limited}",
      description: "Ok if tokens are available, otherwise rate limited"
    }
  )

  @doc """
  Attempts to consume tokens for a request.

  Returns `:ok` if tokens are available. Rate-limited requests remain the
  caller's responsibility and are not retained by the limiter.
  """
  @spec consume(atom(), term()) :: :ok | {:error, :rate_limited}
  def consume(name, request) do
    [{:config, config}] = :ets.lookup(name, :config)
    cost = config.request_cost.(request)

    case take_tokens(name, cost) do
      {:ok, tokens} ->
        :telemetry.execute(
          [:zen_websocket, :rate_limiter, :consume],
          %{tokens_remaining: tokens, cost: cost},
          %{name: name}
        )

        :ok

      :error ->
        {:error, :rate_limited}
    end
  end

  api(:refill, "Refill tokens at the configured rate.",
    params: [
      name: [kind: :value, description: "Rate limiter name"]
    ],
    returns: %{type: ":ok", description: "Always succeeds"}
  )

  @doc """
  Refills tokens at configured rate.

  Called by timer process at refill intervals.
  """
  @spec refill(atom()) :: :ok
  def refill(name) do
    [{:config, config}] = :ets.lookup(name, :config)
    {current_tokens, new_tokens} = refill_tokens(name, config.refill_rate, config.tokens)

    :telemetry.execute(
      [:zen_websocket, :rate_limiter, :refill],
      %{tokens_before: current_tokens, tokens_after: new_tokens, refill_rate: config.refill_rate},
      %{name: name}
    )

    schedule_refill(name, config.refill_interval)

    :ok
  end

  api(:status, "Get current rate limiter status.",
    params: [
      name: [kind: :value, description: "Rate limiter name"]
    ],
    returns: %{
      type: "{:ok, map()}",
      description: "Map with tokens and compatibility status fields"
    }
  )

  @doc """
  Returns the current token count. Queue-related fields remain at their neutral
  values for response compatibility; this limiter does not retain requests.
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

    {:ok,
     %{
       tokens: tokens,
       queue_size: 0,
       pressure_level: :none,
       suggested_delay_ms: 0
     }}
  end

  api(:shutdown, "Clean up rate limiter resources by deleting the ETS table.",
    params: [
      name: [kind: :value, description: "Rate limiter name to shut down"]
    ],
    returns: %{type: ":ok", description: "Always succeeds, even if table already deleted"}
  )

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

  defp take_tokens(name, cost) do
    [{:tokens, current_tokens}] = :ets.lookup(name, :tokens)

    if current_tokens < cost do
      :error
    else
      remaining_tokens = current_tokens - cost

      if replace_tokens(name, current_tokens, remaining_tokens) do
        {:ok, remaining_tokens}
      else
        take_tokens(name, cost)
      end
    end
  end

  defp refill_tokens(name, refill_rate, capacity) do
    [{:tokens, current_tokens}] = :ets.lookup(name, :tokens)
    new_tokens = min(current_tokens + refill_rate, capacity)

    if replace_tokens(name, current_tokens, new_tokens) do
      {current_tokens, new_tokens}
    else
      refill_tokens(name, refill_rate, capacity)
    end
  end

  defp replace_tokens(name, current_tokens, new_tokens) do
    match_spec = [{{:tokens, current_tokens}, [], [{{:tokens, new_tokens}}]}]
    :ets.select_replace(name, match_spec) == 1
  end

  defp schedule_refill(name, interval) do
    Process.send_after(self(), {:refill, name}, interval)
  end

  # Exchange-specific cost functions

  api(:deribit_cost, "Calculate token cost for a Deribit API request using credit-based pricing.",
    params: [
      request: [kind: :value, description: "Request map with a \"method\" key"]
    ],
    returns: %{type: "pos_integer()", description: "Token cost (1 public, 5 read, 10 write, 15 trade)"}
  )

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

  api(:binance_cost, "Calculate token cost for a Binance API request using weight-based pricing.",
    params: [
      request: [kind: :value, description: "Request map with a \"method\" key"]
    ],
    returns: %{type: "pos_integer()", description: "Token cost (2 for klines, 1 for most others)"}
  )

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

  api(:simple_cost, "Fixed cost function returning 1 for every request.",
    params: [
      request: [kind: :value, description: "Any request term (ignored)"]
    ],
    returns: %{type: "pos_integer()", description: "Always returns 1"}
  )

  @doc """
  Simple cost function for fixed-rate exchanges.
  """
  @spec simple_cost(term()) :: pos_integer()
  def simple_cost(_request), do: 1
end
