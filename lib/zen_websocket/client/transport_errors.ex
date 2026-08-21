defmodule ZenWebsocket.Client.TransportErrors do
  @moduledoc """
  Gun error/down logging and retry dispatch for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.Client.Retry, as: Retry
  alias ZenWebsocket.Debug

  @doc """
  Logs a Gun stream error and runs the retry state machine.
  """
  @spec handle_gun_error(map(), pid(), reference(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_gun_error(state, gun_pid, stream_ref, reason) do
    Debug.log(state.config, "❌ [GUN ERROR] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state.config, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(state.config, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🔄 Triggering connection error handling...")

    Retry.handle_connection_error(state, {:gun_error, gun_pid, stream_ref, reason})
  end

  @doc """
  Logs a Gun down event and runs the retry state machine.
  """
  @spec handle_gun_down(map(), pid(), term(), term(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_gun_down(state, gun_pid, protocol, reason, killed_streams) do
    Debug.log(state.config, "📉 [GUN DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(state.config, "   🌐 Protocol: #{inspect(protocol)}")
    Debug.log(state.config, "   💥 Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🚫 Killed Streams: #{inspect(killed_streams)}")
    Debug.log(state.config, "   🔄 Connection lost, triggering error handling...")

    Retry.handle_connection_error(state, {:gun_down, gun_pid, protocol, reason, killed_streams})
  end

  @doc """
  Logs a monitored Gun process exit and runs the retry state machine.
  """
  @spec handle_process_down(map(), pid(), reference(), term()) :: {:noreply, map()} | {:stop, term(), map()}
  def handle_process_down(state, gun_pid, ref, reason) do
    Debug.log(state.config, "💀 [PROCESS DOWN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(state.config, "   🔧 Gun PID: #{inspect(gun_pid)} (monitored process)")
    Debug.log(state.config, "   📍 Monitor Ref: #{inspect(ref)}")
    Debug.log(state.config, "   💥 Exit Reason: #{inspect(reason)}")
    Debug.log(state.config, "   🔄 Process terminated, triggering connection error handling...")

    Retry.handle_connection_error(state, {:connection_down, reason})
  end
end
