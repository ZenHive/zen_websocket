defmodule ZenWebsocket.RecorderServer do
  @moduledoc """
  Async GenServer for recording WebSocket sessions to JSONL files.

  Provides non-blocking recording with buffered I/O to minimize performance
  impact on the WebSocket client. Records are batched and flushed periodically
  or when the buffer reaches a threshold.

  ## Usage

  This module is typically used internally by `ZenWebsocket.Client` when the
  `record_to` config option is set. You can also use it directly:

      {:ok, recorder} = RecorderServer.start_link("/tmp/session.jsonl")
      RecorderServer.record(recorder, :out, {:text, "hello"})
      RecorderServer.record(recorder, :in, {:text, "world"})
      RecorderServer.flush(recorder)
      stats = RecorderServer.stats(recorder)
      RecorderServer.stop(recorder)
  """

  use GenServer

  alias ZenWebsocket.Recorder

  require Logger

  @flush_interval_ms 1000
  @flush_threshold 100

  @type stats :: %{entries: non_neg_integer(), bytes: non_neg_integer()}

  # Public API

  @doc """
  Starts a RecorderServer linked to the current process.

  Opens the file at `path` for writing. Returns `{:error, reason}` if
  the file cannot be opened.
  """
  @spec start_link(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(path) when is_binary(path) do
    # Validate parent directory exists before starting GenServer
    # (actual file open happens in init/1 to avoid opening file twice)
    parent_dir = Path.dirname(path)

    if File.dir?(parent_dir) do
      GenServer.start_link(__MODULE__, path)
    else
      {:error, :enoent}
    end
  end

  @doc """
  Records a WebSocket frame asynchronously.

  This is a non-blocking operation - it sends a message to the GenServer
  and returns immediately. The frame will be buffered and written to disk
  during the next flush.

  ## Parameters

  - `server` - The RecorderServer pid
  - `direction` - `:in` for received frames, `:out` for sent frames
  - `frame` - The WebSocket frame `{:text, data}`, `{:binary, data}`, or `{:close, code, reason}`
  """
  @spec record(pid(), Recorder.direction(), Recorder.frame()) :: :ok
  def record(server, direction, frame) when is_pid(server) do
    send(server, {:record, direction, frame, DateTime.utc_now()})
    :ok
  end

  @doc """
  Forces an immediate flush of the buffer to disk.

  This is a synchronous operation that blocks until all buffered
  records have been written.
  """
  @spec flush(pid()) :: :ok
  def flush(server) when is_pid(server) do
    GenServer.call(server, :flush)
  end

  @doc """
  Stops the recorder, flushing any remaining buffer and closing the file.
  """
  @spec stop(pid()) :: :ok
  def stop(server) when is_pid(server) do
    GenServer.stop(server, :normal)
  end

  @doc """
  Returns recording statistics.

  ## Returns

  A map with:
  - `:entries` - Total number of entries recorded
  - `:bytes` - Total bytes written to disk
  """
  @spec stats(pid()) :: stats()
  def stats(server) when is_pid(server) do
    GenServer.call(server, :stats)
  end

  # GenServer callbacks

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  # ^ Path is user-controlled by design - this is a library API
  def init(path) do
    case File.open(path, [:write, :utf8]) do
      {:ok, file} ->
        schedule_flush()

        state = %{
          file: file,
          path: path,
          buffer: [],
          buffer_length: 0,
          entries: 0,
          bytes: 0
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:record, direction, frame, timestamp}, state) do
    line = Recorder.format_entry(direction, frame, timestamp)
    new_buffer = [line | state.buffer]
    new_buffer_length = state.buffer_length + 1

    new_state = %{state | buffer: new_buffer, buffer_length: new_buffer_length}

    if new_buffer_length >= @flush_threshold do
      {:noreply, do_flush(new_state)}
    else
      {:noreply, new_state}
    end
  end

  def handle_info(:scheduled_flush, state) do
    schedule_flush()
    {:noreply, do_flush(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, do_flush(state)}
  end

  def handle_call(:stats, _from, state) do
    stats = %{entries: state.entries, bytes: state.bytes}
    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Final flush and close
    state = do_flush(state)
    File.close(state.file)
    :ok
  end

  # Private functions

  defp schedule_flush do
    Process.send_after(self(), :scheduled_flush, @flush_interval_ms)
  end

  defp do_flush(%{buffer: []} = state), do: state

  defp do_flush(state) do
    %{
      buffer: buffer,
      buffer_length: buffer_length,
      file: file,
      entries: entries,
      bytes: bytes
    } = state

    # Write lines in order (buffer is reversed)
    lines = buffer |> Enum.reverse() |> Enum.join("\n")
    content = lines <> "\n"

    # IO.write/2 returns :ok or raises - we let it crash on I/O errors
    # since recording is non-critical and the supervisor can restart
    :ok = IO.write(file, content)

    written_bytes = byte_size(content)

    %{
      state
      | buffer: [],
        buffer_length: 0,
        entries: entries + buffer_length,
        bytes: bytes + written_bytes
    }
  end
end
