defmodule ZenWebsocket.PoolRouter do
  @moduledoc """
  Health-based connection routing for WebSocket client pools.

  Provides connection selection based on health scoring that considers:
  - Pending request count (queue depth)
  - Response latency (p99)
  - Recent error count (with 60s decay)
  - Rate limiter pressure level

  ## Health Score Formula (0-100)

      score = 100 - pending_penalty - latency_penalty - error_penalty - pressure_penalty

  Where:
  - `pending_penalty` = min(pending_requests × 10, 40) — 0-40 pts
  - `latency_penalty` = min(p99_ms ÷ 25, 30) — 0-30 pts
  - `error_penalty` = min(error_count × 15, 20) — 0-20 pts
  - `pressure_penalty` = pressure_level_to_points — 0-10 pts

  ## ETS Storage

  Uses `:zen_websocket_pool` ETS table for:
  - Round-robin index for fallback selection
  - Per-connection error tracking with 60-second decay

  ## Performance Notes

  Round-robin selection among equally-healthy connections is O(n) where n is
  the number of connections with the same health score. For typical pools
  (under 100 connections), this is negligible. If you need larger pools,
  consider partitioning into multiple smaller pools.

  ## Configuration

  The error decay period can be configured at compile time:

      config :zen_websocket, :error_decay_ms, 120_000  # 2 minutes

  Default is 60 seconds (60,000 ms).
  """

  alias ZenWebsocket.Client

  # Error tracking decay period in milliseconds (configurable for testing)
  @error_decay_ms Application.compile_env(:zen_websocket, :error_decay_ms, 60_000)

  # ETS table name for pool state
  @table_name :zen_websocket_pool

  # Health score penalties
  @max_pending_penalty 40
  @pending_penalty_per_request 10
  @max_latency_penalty 30
  @latency_divisor 25
  @max_error_penalty 20
  @error_penalty_per_error 15

  @type health_score() :: 0..100

  @doc """
  Selects the healthiest connection from a list of client PIDs.

  Returns the connection with the highest health score, or falls back
  to round-robin selection when health scores are equal.

  ## Examples

      iex> PoolRouter.select_connection([pid1, pid2, pid3])
      {:ok, pid2}

      iex> PoolRouter.select_connection([])
      {:error, :no_connections}
  """
  @spec select_connection([pid()]) :: {:ok, pid()} | {:error, :no_connections}
  def select_connection([]), do: {:error, :no_connections}

  def select_connection(pids) when is_list(pids) do
    ensure_table_exists()

    # Calculate health for all connections
    scored = Enum.map(pids, fn pid -> {pid, calculate_health(pid)} end)

    # Find max health score
    max_health = scored |> Enum.map(&elem(&1, 1)) |> Enum.max()

    # Get all connections with max health (for round-robin among equals)
    best_pids = scored |> Enum.filter(fn {_, h} -> h == max_health end) |> Enum.map(&elem(&1, 0))

    selected =
      case best_pids do
        [single] ->
          single

        multiple ->
          # Round-robin among equally healthy connections
          wrap_at = length(multiple) - 1
          update_op = {2, 1, wrap_at, 0}
          default = {:round_robin_index, 0}
          index = :ets.update_counter(@table_name, :round_robin_index, update_op, default)
          Enum.at(multiple, index)
      end

    :telemetry.execute(
      [:zen_websocket, :pool, :route],
      %{health: max_health, pool_size: length(pids)},
      %{selected: selected}
    )

    {:ok, selected}
  end

  @doc """
  Calculates health score (0-100) for a connection.

  Gathers metrics from the client and applies the scoring formula.
  Returns 100 if metrics cannot be retrieved (optimistic default).
  """
  @spec calculate_health(pid()) :: health_score()
  def calculate_health(pid) when is_pid(pid) do
    ensure_table_exists()

    # Gather metrics from client
    metrics = get_client_metrics(pid)
    error_count = get_error_count(pid)

    # Calculate penalties
    pending_penalty = min(metrics.pending_requests * @pending_penalty_per_request, @max_pending_penalty)
    latency_penalty = min(div(metrics.p99_ms, @latency_divisor), @max_latency_penalty)
    error_penalty = min(error_count * @error_penalty_per_error, @max_error_penalty)
    pressure_penalty = pressure_to_penalty(metrics.pressure_level)

    # Calculate final score (clamped to 0-100)
    score = 100 - pending_penalty - latency_penalty - error_penalty - pressure_penalty
    max(0, round(score))
  end

  @doc """
  Records an error for a connection, incrementing the error count.

  Error counts decay after 60 seconds of no new errors.
  """
  @spec record_error(pid()) :: :ok
  def record_error(pid) when is_pid(pid) do
    ensure_table_exists()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, {:error_count, pid}) do
      [{_, count, _timestamp}] ->
        :ets.insert(@table_name, {{:error_count, pid}, count + 1, now})

      [] ->
        :ets.insert(@table_name, {{:error_count, pid}, 1, now})
    end

    :ok
  end

  @doc """
  Clears the error count for a connection.
  """
  @spec clear_errors(pid()) :: :ok
  def clear_errors(pid) when is_pid(pid) do
    ensure_table_exists()
    :ets.delete(@table_name, {:error_count, pid})
    :ok
  end

  @doc """
  Returns health information for all connections in the pool.
  """
  @spec pool_health([pid()]) :: [%{pid: pid(), health: health_score()}]
  def pool_health(pids) when is_list(pids) do
    health_data = Enum.map(pids, fn pid -> %{pid: pid, health: calculate_health(pid)} end)

    :telemetry.execute(
      [:zen_websocket, :pool, :health],
      %{pool_size: length(pids), avg_health: average_health(health_data)},
      %{}
    )

    health_data
  end

  # Private functions

  # Ensures the ETS table exists, handling race conditions when multiple
  # processes attempt creation simultaneously.
  @doc false
  defp ensure_table_exists do
    if :ets.whereis(@table_name) == :undefined do
      try do
        :ets.new(@table_name, [:named_table, :public, :set])
        :ets.insert(@table_name, {:round_robin_index, 0})
      rescue
        # Another process created the table between our check and creation
        ArgumentError -> :ok
      end
    end
  end

  # Short timeout for client metrics retrieval (100ms)
  # Avoids blocking on non-client processes in unit tests
  @metrics_timeout_ms 100

  @doc false
  defp get_client_metrics(pid) do
    default = %{pending_requests: 0, p99_ms: 0, pressure_level: :none}

    if Process.alive?(pid) do
      # Use Task to enforce short timeout for non-client processes
      task =
        Task.async(fn ->
          try do
            # Construct minimal client struct with server_pid for metrics calls
            client = %Client{server_pid: pid, state: :connected}
            state_metrics = Client.get_state_metrics(client) || %{}
            latency_stats = Client.get_latency_stats(client)

            pending = Map.get(state_metrics, :pending_requests_size, 0)
            p99 = extract_p99(latency_stats)

            %{pending_requests: pending, p99_ms: p99, pressure_level: :none}
          catch
            :exit, _ -> default
          end
        end)

      case Task.yield(task, @metrics_timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, metrics} -> metrics
        nil -> default
      end
    else
      default
    end
  end

  # Extracts p99 latency from stats summary, returns 0 if unavailable
  @doc false
  defp extract_p99(nil), do: 0
  defp extract_p99(%{p99: p99}) when is_number(p99), do: p99

  # Returns the current error count for a connection, applying time-based decay.
  # Errors older than @error_decay_ms are cleared and return 0.
  @doc false
  defp get_error_count(pid) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, {:error_count, pid}) do
      [{_, count, timestamp}] when now - timestamp < @error_decay_ms ->
        count

      [{_, _count, _timestamp}] ->
        # Decay expired, clear and return 0
        :ets.delete(@table_name, {:error_count, pid})
        0

      [] ->
        0
    end
  end

  # Pressure level penalty mapping (0-10 points)
  # Using map lookup to avoid dead code warnings since pressure_level
  # is currently always :none (future expansion for rate limiter integration)
  @pressure_penalties %{high: 10, medium: 6, low: 3, none: 0}

  # Converts a pressure level atom to its penalty score (0-10 points).
  @doc false
  defp pressure_to_penalty(level), do: Map.get(@pressure_penalties, level, 0)

  # Calculates the average health score across all connections in a pool.
  # Returns 0 for empty pools to avoid division by zero.
  @doc false
  defp average_health([]), do: 0

  defp average_health(health_data) do
    total = Enum.reduce(health_data, 0, fn %{health: h}, acc -> acc + h end)
    round(total / length(health_data))
  end
end
