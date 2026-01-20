defmodule ZenWebsocket.RecorderServerTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.RecorderServer

  setup do
    path = Path.join(System.tmp_dir!(), "test_recorder_#{System.unique_integer()}.jsonl")

    on_exit(fn ->
      File.rm(path)
    end)

    {:ok, path: path}
  end

  describe "start_link/1" do
    test "starts recorder with valid path", %{path: path} do
      assert {:ok, pid} = RecorderServer.start_link(path)
      assert Process.alive?(pid)
      RecorderServer.stop(pid)
    end

    test "returns error for invalid path" do
      assert {:error, :enoent} = RecorderServer.start_link("/nonexistent/dir/file.jsonl")
    end
  end

  describe "record/3" do
    test "records text frames", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      :ok = RecorderServer.record(pid, :out, {:text, "hello"})
      :ok = RecorderServer.record(pid, :in, {:text, "world"})

      RecorderServer.flush(pid)
      RecorderServer.stop(pid)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2

      assert {:ok, entry1} = Jason.decode(Enum.at(lines, 0))
      assert entry1["dir"] == "out"
      assert entry1["data"] == "hello"

      assert {:ok, entry2} = Jason.decode(Enum.at(lines, 1))
      assert entry2["dir"] == "in"
      assert entry2["data"] == "world"
    end

    test "records binary frames with base64", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      :ok = RecorderServer.record(pid, :in, {:binary, <<1, 2, 3>>})
      RecorderServer.flush(pid)
      RecorderServer.stop(pid)

      content = File.read!(path)
      assert {:ok, entry} = Jason.decode(String.trim(content))
      assert entry["type"] == "binary"
      assert entry["data"] == "AQID"
      assert entry["binary"] == true
    end

    test "records close frames", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      :ok = RecorderServer.record(pid, :in, {:close, 1000, "goodbye"})
      RecorderServer.flush(pid)
      RecorderServer.stop(pid)

      content = File.read!(path)
      assert {:ok, entry} = Jason.decode(String.trim(content))
      assert entry["type"] == "close"
    end

    test "is non-blocking (async)", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      # Record many messages quickly - should not block
      start_time = System.monotonic_time(:millisecond)

      for i <- 1..100 do
        RecorderServer.record(pid, :out, {:text, "message #{i}"})
      end

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should complete quickly since it's async (100ms tolerance for slow CI systems)
      assert elapsed < 100

      RecorderServer.stop(pid)
    end
  end

  describe "flush/1" do
    test "writes buffered entries to disk", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      RecorderServer.record(pid, :out, {:text, "buffered"})

      # Before flush, file may be empty or have partial content
      RecorderServer.flush(pid)

      # After flush, content should be written
      content = File.read!(path)
      assert String.contains?(content, "buffered")

      RecorderServer.stop(pid)
    end
  end

  describe "stats/1" do
    test "returns entry count and bytes written", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      RecorderServer.record(pid, :out, {:text, "hello"})
      RecorderServer.record(pid, :out, {:text, "world"})
      RecorderServer.flush(pid)

      stats = RecorderServer.stats(pid)

      assert stats.entries == 2
      assert stats.bytes > 0

      RecorderServer.stop(pid)
    end

    test "returns zeros before any recording", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      stats = RecorderServer.stats(pid)

      assert stats.entries == 0
      assert stats.bytes == 0

      RecorderServer.stop(pid)
    end
  end

  describe "stop/1" do
    test "flushes remaining buffer before stopping", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      RecorderServer.record(pid, :out, {:text, "final message"})

      # Stop without explicit flush
      RecorderServer.stop(pid)

      # Content should still be written
      content = File.read!(path)
      assert String.contains?(content, "final message")
    end
  end

  describe "automatic flush" do
    test "flushes on threshold", %{path: path} do
      {:ok, pid} = RecorderServer.start_link(path)

      # Record more than the flush threshold (100 entries)
      for i <- 1..150 do
        RecorderServer.record(pid, :out, {:text, "msg #{i}"})
      end

      # Give time for async processing
      Process.sleep(50)

      # Should have auto-flushed some entries
      stats = RecorderServer.stats(pid)
      assert stats.entries >= 100

      RecorderServer.stop(pid)
    end
  end
end
