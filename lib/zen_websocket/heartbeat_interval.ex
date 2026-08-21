defmodule ZenWebsocket.HeartbeatInterval do
  @moduledoc """
  Records application-level heartbeat pongs and emits interval telemetry.
  """

  @doc """
  Updates heartbeat tracking and emits `[:zen_websocket, :heartbeat, :pong]`.

  Measures time between responses (regularity), not true RTT, which would
  require tracking when the request was sent. The caller supplies
  `active_heartbeats` so generic pongs can replace the set while Deribit
  pongs accumulate.
  """
  @spec record_pong(map(), term(), MapSet.t()) :: map()
  def record_pong(state, type, active_heartbeats) do
    now = System.monotonic_time(:millisecond)
    emit_pong(state.last_heartbeat_at, now, type)

    %{
      state
      | active_heartbeats: active_heartbeats,
        last_heartbeat_at: now,
        heartbeat_failures: 0
    }
  end

  defp emit_pong(nil, _now, _type), do: :ok

  defp emit_pong(previous_at, now, type) do
    :telemetry.execute(
      [:zen_websocket, :heartbeat, :pong],
      %{rtt_ms: now - previous_at},
      %{type: type}
    )
  end
end
