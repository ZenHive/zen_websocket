defmodule ZenWebsocket.LatencyStats do
  @moduledoc """
  Bounded circular buffer for latency statistics calculation.

  Maintains a fixed-size buffer of latency samples and provides
  percentile calculations (p50, p99) for request/response timing.

  Uses `:queue` for O(1) insertion with eviction of oldest samples
  when capacity is reached. Percentile calculation requires sorting
  (O(n log n)) but operates on bounded data.

  ## Telemetry Integration

  This module is designed to work with ZenWebsocket's telemetry events,
  providing aggregated latency metrics from individual measurements.
  """

  @default_max_size 100

  defstruct samples: :queue.new(), max_size: @default_max_size, count: 0

  @type t :: %__MODULE__{
          samples: :queue.queue(non_neg_integer()),
          max_size: pos_integer(),
          count: non_neg_integer()
        }

  @doc """
  Creates a new latency stats buffer with configurable max size.

  ## Options

  - `max_size` - Maximum number of samples to retain (default: 100)

  ## Examples

      iex> stats = ZenWebsocket.LatencyStats.new()
      iex> stats.max_size
      100

      iex> stats = ZenWebsocket.LatencyStats.new(max_size: 50)
      iex> stats.max_size
      50
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    %__MODULE__{max_size: max_size}
  end

  @doc """
  Adds a latency sample in milliseconds to the buffer.

  Evicts the oldest sample if the buffer is at capacity.

  ## Examples

      iex> stats = ZenWebsocket.LatencyStats.new(max_size: 3)
      iex> stats = ZenWebsocket.LatencyStats.add(stats, 10)
      iex> stats = ZenWebsocket.LatencyStats.add(stats, 20)
      iex> stats.count
      2
  """
  @spec add(t(), non_neg_integer()) :: t()
  def add(%__MODULE__{samples: samples, max_size: max_size, count: count} = stats, sample_ms)
      when is_integer(sample_ms) and sample_ms >= 0 do
    {new_samples, new_count} =
      if count >= max_size do
        # Evict oldest (front of queue), add new (back of queue)
        {{:value, _old}, trimmed} = :queue.out(samples)
        {:queue.in(sample_ms, trimmed), count}
      else
        {:queue.in(sample_ms, samples), count + 1}
      end

    %{stats | samples: new_samples, count: new_count}
  end

  @doc """
  Calculates the specified percentile from buffered samples.

  Returns `nil` if the buffer is empty.

  ## Examples

      iex> stats = ZenWebsocket.LatencyStats.new()
      iex> stats = Enum.reduce(1..100, stats, &ZenWebsocket.LatencyStats.add(&2, &1))
      iex> ZenWebsocket.LatencyStats.percentile(stats, 50)
      50

      iex> ZenWebsocket.LatencyStats.percentile(ZenWebsocket.LatencyStats.new(), 50)
      nil
  """
  @spec percentile(t(), number()) :: non_neg_integer() | nil
  def percentile(%__MODULE__{count: 0}, _percentile), do: nil

  def percentile(%__MODULE__{samples: samples, count: count}, percentile)
      when is_number(percentile) and percentile >= 0 and percentile <= 100 do
    sorted = samples |> :queue.to_list() |> Enum.sort()
    # Calculate index for percentile (0-based)
    index = round(percentile / 100 * (count - 1))
    Enum.at(sorted, index)
  end

  @doc """
  Returns a summary map with p50, p99, last sample, and count.

  Returns `nil` if the buffer is empty.

  ## Examples

      iex> stats = ZenWebsocket.LatencyStats.new()
      iex> stats = Enum.reduce([10, 20, 30, 40, 50], stats, &ZenWebsocket.LatencyStats.add(&2, &1))
      iex> summary = ZenWebsocket.LatencyStats.summary(stats)
      iex> summary.count
      5
      iex> summary.last
      50
  """
  @spec summary(t()) ::
          %{p50: non_neg_integer(), p99: non_neg_integer(), last: non_neg_integer(), count: non_neg_integer()} | nil
  def summary(%__MODULE__{count: 0}), do: nil

  def summary(%__MODULE__{samples: samples, count: count} = stats) do
    # Get last sample (back of queue)
    last = :queue.get_r(samples)

    %{
      p50: percentile(stats, 50),
      p99: percentile(stats, 99),
      last: last,
      count: count
    }
  end
end
