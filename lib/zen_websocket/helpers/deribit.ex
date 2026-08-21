defmodule ZenWebsocket.Helpers.Deribit do
  @moduledoc """
  Helper functions for Deribit-specific WebSocket operations.
  """

  alias ZenWebsocket.HeartbeatInterval

  require Logger

  # Deribit public/test heartbeat request — sent both as a test_request response
  # and as an outbound ping; encoded once at compile time.
  @test_request Jason.encode!(%{jsonrpc: "2.0", method: "public/test", params: %{}})

  @doc """
  Handles Deribit test_request heartbeat messages.
  """
  @spec handle_heartbeat(map(), map()) :: map()
  def handle_heartbeat(%{"params" => %{"type" => "test_request"}}, state) do
    Logger.info("🚨 [DERIBIT TEST_REQUEST] Auto-responding...")
    Logger.info("📤 [HEARTBEAT RESPONSE] #{DateTime.to_string(DateTime.utc_now())}")
    Logger.info("   ✅ Sending automatic public/test response")

    :ok = :gun.ws_send(state.gun_pid, state.stream_ref, {:text, @test_request})

    HeartbeatInterval.record_pong(
      state,
      :deribit_test_request,
      MapSet.put(state.active_heartbeats, :deribit_test_request)
    )
  end

  @doc false
  # Catch-all clause for non-test_request heartbeat messages
  def handle_heartbeat(_msg, state), do: state

  @doc """
  Sends Deribit heartbeat ping message.
  """
  @spec send_heartbeat(map()) :: map()
  def send_heartbeat(state) do
    :ok = :gun.ws_send(state.gun_pid, state.stream_ref, {:text, @test_request})

    %{state | last_heartbeat_at: System.monotonic_time(:millisecond)}
  end
end
