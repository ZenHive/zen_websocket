defmodule ZenWebsocket.HeartbeatManager do
  @moduledoc """
  Manages heartbeat lifecycle for WebSocket connections.

  Pure functional module - state ownership stays with Client GenServer.
  Timer ownership stays with Client (Process.send_after needs self()).
  """

  alias ZenWebsocket.Helpers.Deribit

  require Logger

  # Type definitions for heartbeat-related state fields
  @typedoc "Heartbeat configuration - disabled or platform-specific config map"
  @type heartbeat_config :: :disabled | %{:type => atom(), optional(atom()) => term()}

  @typedoc "Client state map containing heartbeat fields (subset of Client.state)"
  @type state :: %{
          :heartbeat_config => heartbeat_config(),
          :heartbeat_timer => reference() | nil,
          :heartbeat_failures => non_neg_integer(),
          :active_heartbeats => MapSet.t(),
          optional(atom()) => term()
        }

  @typedoc "Health metrics returned by get_health/1"
  @type health :: %{
          active_heartbeats: [term()],
          last_heartbeat_at: integer() | nil,
          failure_count: non_neg_integer(),
          config: heartbeat_config(),
          timer_active: boolean()
        }

  @doc """
  Starts heartbeat timer if configured. Call on connection upgrade.

  Returns updated state with timer reference.
  """
  @spec start_timer(state()) :: state()
  def start_timer(%{heartbeat_config: :disabled} = state), do: state

  def start_timer(%{heartbeat_config: config} = state) when is_map(config) do
    interval = Map.get(config, :interval, state.config.heartbeat_interval)
    timer_ref = Process.send_after(self(), :send_heartbeat, interval)
    %{state | heartbeat_timer: timer_ref}
  end

  def start_timer(state), do: state

  @doc """
  Cancels active heartbeat timer. Call on disconnect/error.

  Returns updated state with timer and failure count reset.
  """
  @spec cancel_timer(state()) :: state()
  def cancel_timer(%{heartbeat_timer: nil} = state), do: state

  def cancel_timer(%{heartbeat_timer: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | heartbeat_timer: nil, heartbeat_failures: 0}
  end

  @doc """
  Routes incoming heartbeat messages to platform-specific handlers.

  Returns updated state after processing heartbeat.
  """
  @spec handle_message(map(), state()) :: state()
  def handle_message(msg, state) do
    case state.heartbeat_config do
      %{type: :deribit} ->
        Deribit.handle_heartbeat(msg, state)

      %{type: :binance} ->
        # Binance uses WebSocket ping/pong frames, not application messages
        state

      _ ->
        handle_generic_heartbeat(msg, state)
    end
  end

  @doc """
  Sends platform-specific heartbeat message.

  Returns updated state with last_heartbeat_at timestamp for known types.
  Returns unchanged state for unrecognized or disabled configs.
  """
  @spec send_heartbeat(state()) :: state()
  def send_heartbeat(%{heartbeat_config: %{type: :deribit}} = state) do
    Deribit.send_heartbeat(state)
  end

  def send_heartbeat(%{heartbeat_config: %{type: :ping_pong}} = state) do
    :ok = :gun.ws_send(state.gun_pid, state.stream_ref, :ping)
    %{state | last_heartbeat_at: System.monotonic_time(:millisecond)}
  end

  def send_heartbeat(state) do
    # Fallback: unrecognized heartbeat types are no-ops (state unchanged)
    state
  end

  @doc """
  Returns heartbeat health metrics map.
  """
  @spec get_health(state()) :: health()
  def get_health(state) do
    %{
      active_heartbeats: MapSet.to_list(Map.get(state, :active_heartbeats, MapSet.new())),
      last_heartbeat_at: Map.get(state, :last_heartbeat_at),
      failure_count: Map.get(state, :heartbeat_failures, 0),
      config: Map.get(state, :heartbeat_config, :disabled),
      timer_active: Map.get(state, :heartbeat_timer) != nil
    }
  end

  # Private helpers

  @spec handle_generic_heartbeat(map(), state()) :: state()
  defp handle_generic_heartbeat(%{"method" => "heartbeat", "params" => %{"type" => type}}, state) do
    Logger.info("💚 [PLATFORM HEARTBEAT] Type: #{type}")
    now = System.monotonic_time(:millisecond)

    # Emit heartbeat interval telemetry if we have a previous timestamp
    # Note: This measures time between heartbeat responses (heartbeat regularity),
    # not true round-trip time which would require tracking when requests are sent
    if state.last_heartbeat_at do
      rtt_ms = now - state.last_heartbeat_at

      :telemetry.execute(
        [:zen_websocket, :heartbeat, :pong],
        %{rtt_ms: rtt_ms},
        %{type: type}
      )
    end

    %{
      state
      | active_heartbeats: MapSet.put(state.active_heartbeats, type),
        last_heartbeat_at: now,
        heartbeat_failures: 0
    }
  end

  defp handle_generic_heartbeat(msg, state) do
    Logger.info("❓ [UNKNOWN HEARTBEAT] #{inspect(msg)}")
    state
  end
end
