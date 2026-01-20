defmodule ZenWebsocket.Recorder do
  @moduledoc """
  Pure functions for WebSocket session recording and replay.

  Records WebSocket frames to JSONL format (one JSON object per line) for
  debugging, testing, and analysis. Each entry includes timestamp, direction,
  frame type, and data.

  ## JSONL Format

      {"ts":"2026-01-20T15:30:45.123456Z","dir":"out","type":"text","data":"..."}
      {"ts":"2026-01-20T15:30:45.234567Z","dir":"in","type":"text","data":"..."}
      {"ts":"2026-01-20T15:30:46.000000Z","dir":"in","type":"binary","data":"base64...","binary":true}

  ## Usage

      # Format an entry for recording
      line = Recorder.format_entry(:out, {:text, "hello"}, DateTime.utc_now())

      # Parse an entry from a recording
      {:ok, entry} = Recorder.parse_entry(line)

      # Replay a recording
      Recorder.replay("/tmp/session.jsonl", fn entry ->
        # Process each entry (e.g., send to handler, accumulate stats)
        handle_entry(entry)
      end)

      # Get metadata about a recording
      {:ok, meta} = Recorder.metadata("/tmp/session.jsonl")
      # => %{count: 150, duration_ms: 5234, first_ts: ~U[...], last_ts: ~U[...]}
  """

  @type direction :: :in | :out
  @type frame :: {:text, binary()} | {:binary, binary()} | {:close, integer(), binary()}

  @type entry :: %{
          ts: DateTime.t(),
          dir: direction(),
          type: :text | :binary | :close,
          data: binary(),
          binary: boolean()
        }

  @doc """
  Formats a WebSocket frame as a JSONL line for recording.

  ## Parameters

  - `direction` - `:in` for received frames, `:out` for sent frames
  - `frame` - The WebSocket frame tuple `{:text, data}`, `{:binary, data}`, or `{:close, code, reason}`
  - `timestamp` - The timestamp for this entry (default: current UTC time)

  ## Examples

      iex> line = Recorder.format_entry(:out, {:text, "hello"}, ~U[2026-01-20 15:30:45.123456Z])
      ~s({"ts":"2026-01-20T15:30:45.123456Z","dir":"out","type":"text","data":"hello"})

      iex> line = Recorder.format_entry(:in, {:binary, <<1, 2, 3>>}, ~U[2026-01-20 15:30:45Z])
      ~s({"ts":"2026-01-20T15:30:45.000000Z","dir":"in","type":"binary","data":"AQID","binary":true})
  """
  @spec format_entry(direction(), frame(), DateTime.t()) :: binary()
  def format_entry(direction, frame, timestamp \\ DateTime.utc_now())

  def format_entry(direction, {:text, data}, timestamp) do
    Jason.encode!(%{ts: format_timestamp(timestamp), dir: Atom.to_string(direction), type: "text", data: data})
  end

  def format_entry(direction, {:binary, data}, timestamp) do
    Jason.encode!(%{
      ts: format_timestamp(timestamp),
      dir: Atom.to_string(direction),
      type: "binary",
      data: Base.encode64(data),
      binary: true
    })
  end

  def format_entry(direction, {:close, code, reason}, timestamp) do
    Jason.encode!(%{
      ts: format_timestamp(timestamp),
      dir: Atom.to_string(direction),
      type: "close",
      data: Jason.encode!(%{code: code, reason: reason})
    })
  end

  @doc """
  Parses a JSONL line back into an entry map.

  ## Examples

      iex> {:ok, entry} = Recorder.parse_entry(~s({"ts":"2026-01-20T15:30:45.123456Z","dir":"out","type":"text","data":"hello"}))
      iex> entry.dir
      :out
      iex> entry.data
      "hello"
  """
  @spec parse_entry(binary()) :: {:ok, entry()} | {:error, term()}
  def parse_entry(line) do
    with {:ok, raw} <- Jason.decode(line),
         {:ok, ts} <- parse_timestamp(raw["ts"]),
         {:ok, dir} <- parse_direction(raw["dir"]),
         {:ok, type} <- parse_type(raw["type"]) do
      entry = %{
        ts: ts,
        dir: dir,
        type: type,
        data: decode_data(raw),
        binary: raw["binary"] == true
      }

      {:ok, entry}
    end
  end

  defp parse_direction(dir) when dir in ["in", "out"] do
    {:ok, String.to_existing_atom(dir)}
  end

  defp parse_direction(_), do: {:error, :invalid_direction}

  defp parse_type(type) when type in ["text", "binary", "close"] do
    {:ok, String.to_existing_atom(type)}
  end

  defp parse_type(_), do: {:error, :invalid_type}

  @doc """
  Replays a recorded session by streaming the file and calling the handler for each entry.

  ## Options

  - `:realtime` - If true, delays between entries match the original timing (default: false)

  ## Examples

      # Fast replay
      Recorder.replay("/tmp/session.jsonl", fn entry ->
        IO.puts("\#{entry.dir}: \#{entry.type}")
      end)

      # Realtime replay
      Recorder.replay("/tmp/session.jsonl", &IO.inspect/1, realtime: true)
  """
  # sobelow_skip ["Traversal.FileModule"]
  # ^ Path is user-controlled by design - this is a library API
  @spec replay(binary(), (entry() -> any()), keyword()) :: :ok | {:error, term()}
  def replay(path, handler_fn, opts \\ []) do
    realtime = Keyword.get(opts, :realtime, false)

    case File.open(path, [:read, :utf8]) do
      {:ok, file} ->
        result = do_replay(file, handler_fn, realtime, nil)
        File.close(file)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets metadata about a recorded session.

  Returns information about the recording including entry count, duration,
  and timestamp range.

  ## Examples

      {:ok, meta} = Recorder.metadata("/tmp/session.jsonl")
      # => %{
      #      count: 150,
      #      duration_ms: 5234,
      #      first_ts: ~U[2026-01-20 15:30:45.123456Z],
      #      last_ts: ~U[2026-01-20 15:30:50.357456Z],
      #      inbound: 100,
      #      outbound: 50
      #    }
  """
  # sobelow_skip ["Traversal.FileModule"]
  # ^ Path is user-controlled by design - this is a library API
  @spec metadata(binary()) :: {:ok, map()} | {:error, term()}
  def metadata(path) do
    case File.open(path, [:read, :utf8]) do
      {:ok, file} ->
        result = collect_metadata(file, nil)
        File.close(file)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp format_timestamp(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp parse_timestamp(ts_string) when is_binary(ts_string) do
    case DateTime.from_iso8601(ts_string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_data(%{"binary" => true, "data" => data}) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  defp decode_data(%{"data" => data}), do: data

  defp do_replay(file, handler_fn, realtime, prev_ts) do
    case IO.read(file, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        {:error, {:read_error, reason}}

      line ->
        process_replay_line(file, handler_fn, realtime, prev_ts, line)
    end
  end

  defp process_replay_line(file, handler_fn, realtime, prev_ts, line) do
    line = String.trim_trailing(line, "\n")

    case parse_replay_line(line, prev_ts) do
      :skip ->
        do_replay(file, handler_fn, realtime, prev_ts)

      {:ok, entry} ->
        maybe_delay_realtime(realtime, prev_ts, entry.ts)
        handler_fn.(entry)
        do_replay(file, handler_fn, realtime, entry.ts)
    end
  end

  defp parse_replay_line("", _prev_ts), do: :skip

  defp parse_replay_line(line, _prev_ts) do
    case parse_entry(line) do
      {:ok, entry} -> {:ok, entry}
      {:error, _} -> :skip
    end
  end

  defp maybe_delay_realtime(true, prev_ts, current_ts) when not is_nil(prev_ts) do
    delay_ms = DateTime.diff(current_ts, prev_ts, :millisecond)
    if delay_ms > 0, do: Process.sleep(delay_ms)
  end

  defp maybe_delay_realtime(_realtime, _prev_ts, _current_ts), do: :ok

  defp collect_metadata(file, acc) do
    case IO.read(file, :line) do
      :eof -> finalize_metadata(acc)
      {:error, reason} -> {:error, reason}
      line -> process_metadata_line(file, acc, line)
    end
  end

  defp process_metadata_line(file, acc, line) do
    new_acc =
      line
      |> String.trim_trailing("\n")
      |> parse_metadata_line(acc)

    collect_metadata(file, new_acc)
  end

  defp parse_metadata_line("", acc), do: acc

  defp parse_metadata_line(line, acc) do
    case parse_entry(line) do
      {:ok, entry} -> update_metadata_acc(acc, entry)
      {:error, _} -> acc
    end
  end

  defp update_metadata_acc(nil, entry) do
    %{
      count: 1,
      first_ts: entry.ts,
      last_ts: entry.ts,
      inbound: if(entry.dir == :in, do: 1, else: 0),
      outbound: if(entry.dir == :out, do: 1, else: 0)
    }
  end

  defp update_metadata_acc(acc, entry) do
    %{
      acc
      | count: acc.count + 1,
        last_ts: entry.ts,
        inbound: acc.inbound + if(entry.dir == :in, do: 1, else: 0),
        outbound: acc.outbound + if(entry.dir == :out, do: 1, else: 0)
    }
  end

  defp finalize_metadata(nil) do
    {:ok,
     %{
       count: 0,
       duration_ms: 0,
       first_ts: nil,
       last_ts: nil,
       inbound: 0,
       outbound: 0
     }}
  end

  defp finalize_metadata(acc) do
    duration_ms = DateTime.diff(acc.last_ts, acc.first_ts, :millisecond)

    {:ok,
     %{
       count: acc.count,
       duration_ms: duration_ms,
       first_ts: acc.first_ts,
       last_ts: acc.last_ts,
       inbound: acc.inbound,
       outbound: acc.outbound
     }}
  end
end
