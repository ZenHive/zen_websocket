defmodule ZenWebsocket.RecorderTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Recorder

  describe "format_entry/3" do
    test "formats text frame as JSON" do
      timestamp = ~U[2026-01-20 15:30:45.123456Z]
      line = Recorder.format_entry(:out, {:text, "hello"}, timestamp)

      assert {:ok, decoded} = Jason.decode(line)
      assert decoded["ts"] == "2026-01-20T15:30:45.123456Z"
      assert decoded["dir"] == "out"
      assert decoded["type"] == "text"
      assert decoded["data"] == "hello"
      refute Map.has_key?(decoded, "binary")
    end

    test "formats binary frame with base64 encoding" do
      timestamp = ~U[2026-01-20 15:30:45Z]
      line = Recorder.format_entry(:in, {:binary, <<1, 2, 3>>}, timestamp)

      assert {:ok, decoded} = Jason.decode(line)
      assert decoded["dir"] == "in"
      assert decoded["type"] == "binary"
      assert decoded["data"] == "AQID"
      assert decoded["binary"] == true
    end

    test "formats close frame with code and reason" do
      timestamp = ~U[2026-01-20 15:30:45Z]
      line = Recorder.format_entry(:in, {:close, 1000, "Normal closure"}, timestamp)

      assert {:ok, decoded} = Jason.decode(line)
      assert decoded["type"] == "close"
      assert {:ok, close_data} = Jason.decode(decoded["data"])
      assert close_data["code"] == 1000
      assert close_data["reason"] == "Normal closure"
    end

    test "uses current time when no timestamp provided" do
      line = Recorder.format_entry(:out, {:text, "test"})

      assert {:ok, decoded} = Jason.decode(line)
      assert is_binary(decoded["ts"])
      # Should be a valid ISO8601 timestamp
      assert {:ok, _, _} = DateTime.from_iso8601(decoded["ts"])
    end
  end

  describe "parse_entry/1" do
    test "parses text entry" do
      line = ~s({"ts":"2026-01-20T15:30:45.123456Z","dir":"out","type":"text","data":"hello"})

      assert {:ok, entry} = Recorder.parse_entry(line)
      assert entry.ts == ~U[2026-01-20 15:30:45.123456Z]
      assert entry.dir == :out
      assert entry.type == :text
      assert entry.data == "hello"
      assert entry.binary == false
    end

    test "parses binary entry and decodes base64" do
      line = ~s({"ts":"2026-01-20T15:30:45Z","dir":"in","type":"binary","data":"AQID","binary":true})

      assert {:ok, entry} = Recorder.parse_entry(line)
      assert entry.dir == :in
      assert entry.type == :binary
      assert entry.data == <<1, 2, 3>>
      assert entry.binary == true
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Recorder.parse_entry("not json")
    end

    test "returns error for invalid timestamp" do
      line = ~s({"ts":"invalid","dir":"out","type":"text","data":"hello"})
      assert {:error, _} = Recorder.parse_entry(line)
    end

    test "returns error for an unrecognized direction" do
      line = ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"sideways","type":"text","data":"hello"})
      assert {:error, :invalid_direction} = Recorder.parse_entry(line)
    end

    test "returns error for an unrecognized frame type" do
      line = ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"ping","data":"hello"})
      assert {:error, :invalid_type} = Recorder.parse_entry(line)
    end

    test "falls back to the raw data when a binary entry has invalid base64" do
      line = ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"in","type":"binary","data":"not-base64!","binary":true})

      assert {:ok, entry} = Recorder.parse_entry(line)
      # Base.decode64/1 fails on this string, so decode_data/1 must fall back
      # to returning the raw (still-encoded) data instead of crashing.
      assert entry.data == "not-base64!"
    end

    test "roundtrip: format then parse" do
      timestamp = ~U[2026-01-20 15:30:45.123456Z]
      original_frame = {:text, "test message"}

      line = Recorder.format_entry(:out, original_frame, timestamp)
      assert {:ok, entry} = Recorder.parse_entry(line)

      assert entry.ts == timestamp
      assert entry.dir == :out
      assert entry.type == :text
      assert entry.data == "test message"
    end
  end

  describe "replay/3" do
    setup do
      path = Path.join(System.tmp_dir!(), "test_replay_#{System.unique_integer()}.jsonl")

      on_exit(fn ->
        File.rm(path)
      end)

      {:ok, path: path}
    end

    test "replays entries to handler function", %{path: path} do
      # Write test data
      lines = [
        ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"hello"}),
        ~s({"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"text","data":"world"})
      ]

      File.write!(path, Enum.join(lines, "\n") <> "\n")

      # Collect entries
      parent = self()

      :ok =
        Recorder.replay(path, fn entry ->
          send(parent, {:entry, entry})
        end)

      assert_receive {:entry, %{dir: :out, data: "hello"}}
      assert_receive {:entry, %{dir: :in, data: "world"}}
    end

    test "skips empty lines", %{path: path} do
      content = """
      {"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"one"}

      {"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"text","data":"two"}

      """

      File.write!(path, content)

      entries =
        Recorder.replay(path, fn entry ->
          send(self(), {:entry, entry})
        end)

      assert entries == :ok
      assert_receive {:entry, %{data: "one"}}
      assert_receive {:entry, %{data: "two"}}
      refute_receive {:entry, _}
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Recorder.replay("/nonexistent/file.jsonl", fn _ -> :ok end)
    end

    test "skips malformed lines instead of raising or aborting the replay", %{path: path} do
      content =
        Enum.join(
          [
            ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"good-one"}),
            "this is not json at all",
            ~s({"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"text","data":"good-two"})
          ],
          "\n"
        ) <> "\n"

      File.write!(path, content)

      assert :ok = Recorder.replay(path, fn entry -> send(self(), {:entry, entry}) end)

      # Both valid entries surface around the bad line, and the handler is
      # never invoked for the malformed one.
      assert_receive {:entry, %{data: "good-one"}}
      assert_receive {:entry, %{data: "good-two"}}
      refute_receive {:entry, _}
    end

    test "realtime: true delays replay to match the original inter-entry timing", %{path: path} do
      lines = [
        ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"first"}),
        ~s({"ts":"2026-01-20T15:30:45.050000Z","dir":"out","type":"text","data":"second"})
      ]

      File.write!(path, Enum.join(lines, "\n") <> "\n")

      started_at = System.monotonic_time(:millisecond)
      assert :ok = Recorder.replay(path, fn entry -> send(self(), {:entry, entry}) end, realtime: true)
      elapsed_ms = System.monotonic_time(:millisecond) - started_at

      assert_receive {:entry, %{data: "first"}}
      assert_receive {:entry, %{data: "second"}}
      # The two entries are 50ms apart in their recorded timestamps, so a
      # realtime replay must take at least that long (a non-realtime replay
      # would finish in well under 1ms).
      assert elapsed_ms >= 40
    end
  end

  describe "metadata/1" do
    setup do
      path = Path.join(System.tmp_dir!(), "test_metadata_#{System.unique_integer()}.jsonl")

      on_exit(fn ->
        File.rm(path)
      end)

      {:ok, path: path}
    end

    test "returns correct counts and duration", %{path: path} do
      lines = [
        ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"one"}),
        ~s({"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"text","data":"two"}),
        ~s({"ts":"2026-01-20T15:30:47.000000Z","dir":"in","type":"text","data":"three"}),
        ~s({"ts":"2026-01-20T15:30:50.000000Z","dir":"out","type":"text","data":"four"})
      ]

      File.write!(path, Enum.join(lines, "\n") <> "\n")

      assert {:ok, meta} = Recorder.metadata(path)
      assert meta.count == 4
      assert meta.inbound == 2
      assert meta.outbound == 2
      assert meta.duration_ms == 5000
      assert meta.first_ts == ~U[2026-01-20 15:30:45.000000Z]
      assert meta.last_ts == ~U[2026-01-20 15:30:50.000000Z]
    end

    test "returns zeros for empty file", %{path: path} do
      File.write!(path, "")

      assert {:ok, meta} = Recorder.metadata(path)
      assert meta.count == 0
      assert meta.duration_ms == 0
      assert meta.first_ts == nil
      assert meta.last_ts == nil
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Recorder.metadata("/nonexistent/file.jsonl")
    end

    test "skips blank and malformed lines when counting", %{path: path} do
      content =
        Enum.join(
          [
            ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"out","type":"text","data":"one"}),
            "",
            "not json",
            ~s({"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"text","data":"two"})
          ],
          "\n"
        ) <> "\n"

      File.write!(path, content)

      assert {:ok, meta} = Recorder.metadata(path)
      # Only the two well-formed entries are counted; the blank and
      # malformed lines contribute nothing (and must not crash the count).
      assert meta.count == 2
      assert meta.inbound == 1
      assert meta.outbound == 1
    end
  end
end
