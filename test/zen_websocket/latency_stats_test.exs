defmodule ZenWebsocket.LatencyStatsTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.LatencyStats

  describe "new/1" do
    test "creates buffer with default max_size of 100" do
      stats = LatencyStats.new()
      assert stats.max_size == 100
      assert stats.count == 0
    end

    test "creates buffer with custom max_size" do
      stats = LatencyStats.new(max_size: 50)
      assert stats.max_size == 50
      assert stats.count == 0
    end
  end

  describe "add/2" do
    test "adds sample to buffer" do
      stats = LatencyStats.new()
      stats = LatencyStats.add(stats, 10)

      assert stats.count == 1
    end

    test "increments count for each sample" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(10)
        |> LatencyStats.add(20)
        |> LatencyStats.add(30)

      assert stats.count == 3
    end

    test "evicts oldest sample when at capacity" do
      stats = LatencyStats.new(max_size: 3)

      stats =
        stats
        |> LatencyStats.add(10)
        |> LatencyStats.add(20)
        |> LatencyStats.add(30)

      assert stats.count == 3

      # Adding 4th sample should evict the first (10)
      stats = LatencyStats.add(stats, 40)
      assert stats.count == 3

      # Verify the oldest sample (10) was evicted
      # p50 of [20, 30, 40] should be 30
      assert LatencyStats.percentile(stats, 50) == 30
    end

    test "maintains bounded size over many additions" do
      stats = LatencyStats.new(max_size: 5)

      # Add 100 samples
      stats = Enum.reduce(1..100, stats, &LatencyStats.add(&2, &1))

      # Should still be at max_size
      assert stats.count == 5

      # Buffer should contain [96, 97, 98, 99, 100]
      summary = LatencyStats.summary(stats)
      assert summary.last == 100
      assert summary.count == 5
    end
  end

  describe "percentile/2" do
    test "returns nil for empty buffer" do
      stats = LatencyStats.new()
      assert LatencyStats.percentile(stats, 50) == nil
      assert LatencyStats.percentile(stats, 99) == nil
    end

    test "returns correct p50 for single sample" do
      stats = LatencyStats.add(LatencyStats.new(), 42)
      assert LatencyStats.percentile(stats, 50) == 42
    end

    test "returns correct p50 for odd number of samples" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(10)
        |> LatencyStats.add(20)
        |> LatencyStats.add(30)

      # Sorted: [10, 20, 30], p50 index = 1 → 20
      assert LatencyStats.percentile(stats, 50) == 20
    end

    test "returns correct p50 for even number of samples" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(10)
        |> LatencyStats.add(20)
        |> LatencyStats.add(30)
        |> LatencyStats.add(40)

      # Sorted: [10, 20, 30, 40], p50 index = round(0.5 * 3) = 2 → 30
      assert LatencyStats.percentile(stats, 50) == 30
    end

    test "returns correct p99 for large sample" do
      # Add samples 1..100
      stats = Enum.reduce(1..100, LatencyStats.new(), &LatencyStats.add(&2, &1))

      # p99 should be near 99
      assert LatencyStats.percentile(stats, 99) == 99
    end

    test "returns correct p0 (minimum)" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(50)
        |> LatencyStats.add(10)
        |> LatencyStats.add(30)

      assert LatencyStats.percentile(stats, 0) == 10
    end

    test "returns correct p100 (maximum)" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(50)
        |> LatencyStats.add(10)
        |> LatencyStats.add(30)

      assert LatencyStats.percentile(stats, 100) == 50
    end

    test "handles unsorted insertion order" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(100)
        |> LatencyStats.add(1)
        |> LatencyStats.add(50)
        |> LatencyStats.add(25)
        |> LatencyStats.add(75)

      # Sorted: [1, 25, 50, 75, 100]
      assert LatencyStats.percentile(stats, 50) == 50
    end
  end

  describe "summary/1" do
    test "returns nil for empty buffer" do
      stats = LatencyStats.new()
      assert LatencyStats.summary(stats) == nil
    end

    test "returns complete summary for non-empty buffer" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(10)
        |> LatencyStats.add(20)
        |> LatencyStats.add(30)
        |> LatencyStats.add(40)
        |> LatencyStats.add(50)

      summary = LatencyStats.summary(stats)

      assert Map.has_key?(summary, :p50)
      assert Map.has_key?(summary, :p99)
      assert Map.has_key?(summary, :last)
      assert Map.has_key?(summary, :count)

      assert summary.count == 5
      assert summary.last == 50
      assert summary.p50 == 30
    end

    test "last value is most recently added" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(100)
        |> LatencyStats.add(200)
        |> LatencyStats.add(150)

      summary = LatencyStats.summary(stats)
      assert summary.last == 150
    end
  end

  describe "edge cases" do
    test "handles max_size of 1" do
      stats = LatencyStats.new(max_size: 1)

      stats = LatencyStats.add(stats, 10)
      assert stats.count == 1
      assert LatencyStats.summary(stats).last == 10

      stats = LatencyStats.add(stats, 20)
      assert stats.count == 1
      assert LatencyStats.summary(stats).last == 20
    end

    test "handles zero value samples" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(0)
        |> LatencyStats.add(0)
        |> LatencyStats.add(0)

      assert LatencyStats.percentile(stats, 50) == 0
      assert LatencyStats.summary(stats).last == 0
    end

    test "handles large latency values" do
      stats =
        LatencyStats.new()
        |> LatencyStats.add(1_000_000)
        |> LatencyStats.add(2_000_000)
        |> LatencyStats.add(3_000_000)

      assert LatencyStats.percentile(stats, 50) == 2_000_000
    end
  end
end
