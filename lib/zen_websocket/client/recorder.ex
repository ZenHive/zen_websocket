defmodule ZenWebsocket.ClientRecorder do
  @moduledoc """
  Session recorder lifecycle and frame writes for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.Recorder
  alias ZenWebsocket.RecorderServer

  require Logger

  @doc """
  Starts a session recorder when `record_to` is a path.
  """
  @spec maybe_start(String.t() | nil) :: pid() | nil
  def maybe_start(nil), do: nil

  def maybe_start(path) when is_binary(path) do
    case RecorderServer.start_link(path) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        Logger.warning("Failed to start session recorder: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Records a frame when a recorder process exists.
  """
  @spec maybe_record(pid() | nil, Recorder.direction(), term()) :: :ok
  def maybe_record(nil, _direction, _frame), do: :ok

  def maybe_record(recorder_pid, direction, frame) do
    RecorderServer.record(recorder_pid, direction, frame)
  end

  @doc """
  Stops a session recorder if it is still alive.
  """
  @spec maybe_stop(pid() | nil) :: :ok
  def maybe_stop(nil), do: :ok

  def maybe_stop(recorder_pid) do
    if Process.alive?(recorder_pid) do
      RecorderServer.stop(recorder_pid)
    end

    :ok
  end
end
