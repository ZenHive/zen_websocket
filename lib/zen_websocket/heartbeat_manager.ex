defmodule ZenWebsocket.HeartbeatManager do
  @moduledoc """
  Manages heartbeat lifecycle for WebSocket connections.

  Pure functional module - state ownership stays with Client GenServer.
  Timer ownership stays with Client (Process.send_after needs self()).
  """

  use Descripex, namespace: "/heartbeat"

  alias ZenWebsocket.HeartbeatInterval
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
          optional(:heartbeat_ping_payload) => binary() | nil,
          optional(:heartbeat_ping_sent_at) => integer() | nil,
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

  api(:start_timer, "Start heartbeat timer if configured. Call on connection upgrade.",
    params: [state: [kind: :value, description: "Client state map with heartbeat config"]],
    returns: %{type: "state()", description: "Updated state with timer reference"}
  )

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

  api(:cancel_timer, "Cancel active heartbeat timer. Call on disconnect/error.",
    params: [state: [kind: :value, description: "Client state map with active timer"]],
    returns: %{type: "state()", description: "Updated state with timer and failure count reset"}
  )

  @doc """
  Cancels active heartbeat timer. Call on disconnect/error.

  Returns updated state with timer and failure count reset.
  """
  @spec cancel_timer(state()) :: state()
  def cancel_timer(%{heartbeat_timer: nil} = state), do: state

  def cancel_timer(%{heartbeat_timer: timer_ref} = state) do
    Process.cancel_timer(timer_ref)

    state
    |> Map.put(:heartbeat_timer, nil)
    |> Map.put(:heartbeat_failures, 0)
    |> Map.put(:heartbeat_ping_payload, nil)
    |> Map.put(:heartbeat_ping_sent_at, nil)
  end

  api(:handle_message, "Route incoming heartbeat message to platform-specific handler.",
    params: [
      msg: [kind: :value, description: "Incoming heartbeat message or pong frame"],
      state: [kind: :value, description: "Client state map with heartbeat config"]
    ],
    returns: %{type: "state()", description: "Updated state after processing heartbeat"}
  )

  @doc """
  Routes incoming heartbeat messages to platform-specific handlers.

  Returns updated state after processing heartbeat.
  """
  @spec handle_message(map() | {:pong, binary()}, state()) :: state()
  def handle_message({:pong, payload}, %{heartbeat_config: %{type: :ping_pong}} = state) do
    acknowledge_pong(payload, state)
  end

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

  api(:send_heartbeat, "Send platform-specific heartbeat message.",
    params: [state: [kind: :value, description: "Client state map with heartbeat config and gun connection"]],
    returns: %{type: "state()", description: "Updated state with outbound heartbeat tracking"}
  )

  @doc """
  Sends platform-specific heartbeat message.

  Returns updated state with outbound heartbeat tracking for known types.
  Returns unchanged state for unrecognized or disabled configs.
  """
  @spec send_heartbeat(state()) :: state()
  def send_heartbeat(%{heartbeat_config: %{type: :deribit}} = state) do
    Deribit.send_heartbeat(state)
  end

  def send_heartbeat(%{heartbeat_config: %{type: :ping_pong}} = state) do
    payload = [:positive, :monotonic] |> :erlang.unique_integer() |> Integer.to_string()
    failures = missed_pong_count(state)

    :ok = :gun.ws_send(state.gun_pid, state.stream_ref, {:ping, payload})

    state
    |> Map.put(:heartbeat_ping_payload, payload)
    |> Map.put(:heartbeat_ping_sent_at, System.monotonic_time(:millisecond))
    |> Map.put(:heartbeat_failures, failures)
  end

  def send_heartbeat(state) do
    # Fallback: unrecognized heartbeat types are no-ops (state unchanged)
    state
  end

  api(:get_health, "Return heartbeat health metrics.",
    params: [state: [kind: :value, description: "Client state map with heartbeat fields"]],
    returns: %{
      type: "health()",
      description: "Health metrics including active heartbeats, failure count, and timer status"
    }
  )

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

  defp acknowledge_pong(payload, state) do
    case {Map.get(state, :heartbeat_ping_payload), Map.get(state, :heartbeat_ping_sent_at)} do
      {^payload, sent_at} when is_integer(sent_at) ->
        now = System.monotonic_time(:millisecond)

        :telemetry.execute(
          [:zen_websocket, :heartbeat, :pong],
          %{rtt_ms: now - sent_at},
          %{type: :ping_pong}
        )

        state
        |> Map.put(:active_heartbeats, MapSet.put(state.active_heartbeats, :ping_pong))
        |> Map.put(:last_heartbeat_at, now)
        |> Map.put(:heartbeat_failures, 0)
        |> Map.put(:heartbeat_ping_payload, nil)
        |> Map.put(:heartbeat_ping_sent_at, nil)

      _other ->
        state
    end
  end

  defp missed_pong_count(state) do
    if Map.get(state, :heartbeat_ping_payload) do
      state.heartbeat_failures + 1
    else
      state.heartbeat_failures
    end
  end

  @spec handle_generic_heartbeat(map(), state()) :: state()
  defp handle_generic_heartbeat(%{"method" => "heartbeat", "params" => %{"type" => type}}, state) do
    Logger.info("💚 [PLATFORM HEARTBEAT] Type: #{type}")
    HeartbeatInterval.record_pong(state, type, MapSet.new([type]))
  end

  defp handle_generic_heartbeat(msg, state) do
    Logger.info("❓ [UNKNOWN HEARTBEAT] #{inspect(msg)}")
    state
  end
end
