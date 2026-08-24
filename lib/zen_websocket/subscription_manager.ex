defmodule ZenWebsocket.SubscriptionManager do
  @moduledoc """
  Tracks Deribit-dialect JSON-RPC subscriptions for reconnect restoration.

  Only `public/subscribe` and `public/unsubscribe` with `params.channels` are
  auto-tracked (plus their id-keyed confirmations and rejections). Other
  venues' subscribe shapes are ignored and are not automatically restored;
  `build_restore_message/1` always emits Deribit's payload.

  `Client.subscribe/2` sends no JSON-RPC id, so channels are recorded at send
  time. A server-side rejection leaves them in the restore set. Id-carrying
  requests wait for a result or error.

  Pure functional module — state ownership stays with Client GenServer.

  Internal to ZenWebsocket: not listed in `ZenWebsocket.describe/0`. Consumers
  use `Client.subscribe/2` (and id-carrying `public/subscribe` via
  `Client.send_message/2`); this module only mutates Client-owned state.

  ## Telemetry Events

  The following telemetry events are emitted:

  * `[:zen_websocket, :subscription_manager, :add]` - Emitted when a channel is added.
    * Measurements: `%{count: 1}`
    * Metadata: `%{channel: channel}`

  * `[:zen_websocket, :subscription_manager, :remove]` - Emitted when a channel is removed.
    * Measurements: `%{count: 1}`
    * Metadata: `%{channel: channel}`

  * `[:zen_websocket, :subscription_manager, :restore]` - Emitted when subscriptions are restored.
    * Measurements: `%{channel_count: integer()}`
    * Metadata: `%{channels: [String.t()]}`
  """

  use Descripex, namespace: "/subscriptions"

  require Logger

  @typedoc "Client state map containing subscription fields (subset of Client.state)"
  @type state :: %{
          :subscriptions => MapSet.t(String.t()),
          :config => %{:restore_subscriptions => boolean(), optional(atom()) => term()},
          optional(atom()) => term()
        }

  api(:add, "Add a channel to the tracked subscription set.",
    params: [
      state: [kind: :exchange_data, description: "Client state map containing subscription fields"],
      channel: [kind: :value, description: "Channel name to subscribe to"]
    ],
    returns: %{type: "state()", description: "Updated state with channel added to subscriptions"}
  )

  @doc """
  Adds a channel to the tracked subscription set.

  Used after a subscribe operation is confirmed or when it has no correlation ID.
  """
  @spec add(state(), String.t()) :: state()
  def add(state, channel) when is_binary(channel) do
    new_subscriptions = MapSet.put(state.subscriptions, channel)

    :telemetry.execute(
      [:zen_websocket, :subscription_manager, :add],
      %{count: 1},
      %{channel: channel}
    )

    %{state | subscriptions: new_subscriptions}
  end

  api(:remove, "Remove a channel from the tracked subscription set.",
    params: [
      state: [kind: :exchange_data, description: "Client state map containing subscription fields"],
      channel: [kind: :value, description: "Channel name to unsubscribe from"]
    ],
    returns: %{type: "state()", description: "Updated state with channel removed from subscriptions"}
  )

  @doc """
  Removes a channel from the tracked subscription set.

  Used after an unsubscribe operation is confirmed or when it has no correlation ID.
  """
  @spec remove(state(), String.t()) :: state()
  def remove(state, channel) when is_binary(channel) do
    new_subscriptions = MapSet.delete(state.subscriptions, channel)

    :telemetry.execute(
      [:zen_websocket, :subscription_manager, :remove],
      %{count: 1},
      %{channel: channel}
    )

    %{state | subscriptions: new_subscriptions}
  end

  api(:list, "List all currently tracked subscriptions.",
    params: [
      state: [kind: :exchange_data, description: "Client state map containing subscription fields"]
    ],
    returns: %{type: "[String.t()]", description: "List of subscribed channel names"}
  )

  @doc """
  Lists all currently tracked subscriptions.
  """
  @spec list(state()) :: [String.t()]
  def list(state) do
    MapSet.to_list(state.subscriptions)
  end

  api(:build_restore_message, "Build a restore message for reconnection.",
    params: [
      state: [kind: :exchange_data, description: "Client state map containing subscription fields and config"]
    ],
    returns: %{type: "binary() | nil", description: "JSON-encoded subscribe message, or nil if no restore needed"}
  )

  @doc """
  Builds a restore message for reconnection.

  Returns nil if:
  - No subscriptions to restore
  - `restore_subscriptions` config is false

  Returns JSON-encoded subscribe message otherwise.
  """
  @spec build_restore_message(state()) :: binary() | nil
  def build_restore_message(%{config: %{restore_subscriptions: false}}), do: nil

  def build_restore_message(state) do
    channels = list(state)

    if Enum.empty?(channels) do
      nil
    else
      Logger.info("🔄 [SUBSCRIPTION RESTORE] Restoring #{length(channels)} channel(s)")

      :telemetry.execute(
        [:zen_websocket, :subscription_manager, :restore],
        %{channel_count: length(channels)},
        %{channels: channels}
      )

      Jason.encode!(%{method: "public/subscribe", params: %{channels: channels}})
    end
  end

  api(:handle_message, "Track Deribit public/subscribe and public/unsubscribe requests and confirmations.",
    params: [
      msg: [
        kind: :exchange_data,
        description: "Inbound Deribit subscribe/unsubscribe request, confirmation, or error map"
      ],
      state: [kind: :exchange_data, description: "Client state map containing subscription fields"]
    ],
    returns: %{type: "state()", description: "Updated pending or confirmed subscription state"}
  )

  @doc """
  Tracks Deribit `public/subscribe` and `public/unsubscribe` requests.

  Requests with no `id` (including `Client.subscribe/2`) apply immediately.
  Id-carrying requests wait for a result or error. Data ticks and non-Deribit
  subscribe shapes are ignored.
  """
  @spec handle_message(map(), state()) :: state()
  def handle_message(%{"method" => "public/" <> op, "params" => %{"channels" => channels}} = msg, state)
      when op in ["subscribe", "unsubscribe"] and is_list(channels) do
    track_outbound(state, Map.get(msg, "id"), subscription_op(op), channels)
  end

  def handle_message(%{"id" => id, "result" => channels}, state) when is_list(channels) do
    apply_pending_result(state, id, channels)
  end

  def handle_message(%{"id" => id, "error" => _}, state) do
    pending = Map.get(state, :pending_subscription_ops, %{})
    Map.put(state, :pending_subscription_ops, Map.delete(pending, id))
  end

  def handle_message(_msg, state), do: state

  defp subscription_op("subscribe"), do: :add
  defp subscription_op("unsubscribe"), do: :remove

  defp track_outbound(state, nil, op, channels), do: apply_channels(state, op, channels)

  defp track_outbound(state, id, op, _channels) do
    pending = Map.get(state, :pending_subscription_ops, %{})
    Map.put(state, :pending_subscription_ops, Map.put(pending, id, op))
  end

  defp apply_pending_result(state, id, channels) do
    pending = Map.get(state, :pending_subscription_ops, %{})
    {op, pending} = Map.pop(pending, id)
    apply_channels(Map.put(state, :pending_subscription_ops, pending), op, channels)
  end

  defp apply_channels(state, :add, channels), do: Enum.reduce(channels, state, &put_channel(&2, &1, :add))
  defp apply_channels(state, :remove, channels), do: Enum.reduce(channels, state, &put_channel(&2, &1, :remove))
  defp apply_channels(state, _op, _channels), do: state

  defp put_channel(state, channel, :add) when is_binary(channel) do
    Logger.debug("📡 [SUBSCRIPTION] Confirmed: #{channel}")
    add(state, channel)
  end

  defp put_channel(state, channel, :remove) when is_binary(channel), do: remove(state, channel)
  defp put_channel(state, _channel, _op), do: state
end
