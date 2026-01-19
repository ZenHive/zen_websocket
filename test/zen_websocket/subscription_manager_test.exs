defmodule ZenWebsocket.SubscriptionManagerTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.SubscriptionManager

  # Helper to build test state with required fields
  defp build_state(overrides \\ %{}) do
    default_config = %ZenWebsocket.Config{
      url: "wss://test.example.com",
      timeout: 5000,
      retry_count: 3,
      retry_delay: 1000,
      max_backoff: 30_000,
      heartbeat_interval: 30_000,
      request_timeout: 10_000,
      reconnect_on_error: true,
      restore_subscriptions: true
    }

    Map.merge(
      %{
        config: default_config,
        subscriptions: MapSet.new()
      },
      overrides
    )
  end

  describe "add/2" do
    test "adds channel to empty subscription set" do
      state = build_state()
      result = SubscriptionManager.add(state, "ticker.BTC-PERPETUAL")

      assert MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
      assert MapSet.size(result.subscriptions) == 1
    end

    test "adds channel to existing subscription set" do
      state = build_state(%{subscriptions: MapSet.new(["ticker.ETH-PERPETUAL"])})
      result = SubscriptionManager.add(state, "ticker.BTC-PERPETUAL")

      assert MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
      assert MapSet.member?(result.subscriptions, "ticker.ETH-PERPETUAL")
      assert MapSet.size(result.subscriptions) == 2
    end

    test "adding same channel twice is idempotent" do
      state = build_state()

      result =
        state
        |> SubscriptionManager.add("ticker.BTC-PERPETUAL")
        |> SubscriptionManager.add("ticker.BTC-PERPETUAL")

      assert MapSet.size(result.subscriptions) == 1
    end
  end

  describe "remove/2" do
    test "removes channel from subscription set" do
      state = build_state(%{subscriptions: MapSet.new(["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"])})
      result = SubscriptionManager.remove(state, "ticker.BTC-PERPETUAL")

      refute MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
      assert MapSet.member?(result.subscriptions, "ticker.ETH-PERPETUAL")
      assert MapSet.size(result.subscriptions) == 1
    end

    test "removing non-existent channel is no-op" do
      state = build_state(%{subscriptions: MapSet.new(["ticker.ETH-PERPETUAL"])})
      result = SubscriptionManager.remove(state, "ticker.BTC-PERPETUAL")

      assert result.subscriptions == state.subscriptions
    end

    test "removing from empty set is no-op" do
      state = build_state()
      result = SubscriptionManager.remove(state, "ticker.BTC-PERPETUAL")

      assert MapSet.size(result.subscriptions) == 0
    end
  end

  describe "list/1" do
    test "returns empty list for no subscriptions" do
      state = build_state()
      result = SubscriptionManager.list(state)

      assert result == []
    end

    test "returns list of all subscriptions" do
      channels = ["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL", "book.BTC-PERPETUAL.100ms"]
      state = build_state(%{subscriptions: MapSet.new(channels)})

      result = SubscriptionManager.list(state)

      assert Enum.sort(result) == Enum.sort(channels)
      assert length(result) == 3
    end
  end

  describe "build_restore_message/1" do
    test "returns nil when restore_subscriptions is false" do
      config = %ZenWebsocket.Config{
        url: "wss://test.example.com",
        timeout: 5000,
        retry_count: 3,
        retry_delay: 1000,
        max_backoff: 30_000,
        heartbeat_interval: 30_000,
        request_timeout: 10_000,
        reconnect_on_error: true,
        restore_subscriptions: false
      }

      state = %{
        config: config,
        subscriptions: MapSet.new(["ticker.BTC-PERPETUAL"])
      }

      assert SubscriptionManager.build_restore_message(state) == nil
    end

    test "returns nil when no subscriptions to restore" do
      state = build_state()

      assert SubscriptionManager.build_restore_message(state) == nil
    end

    test "returns JSON subscribe message with all channels" do
      channels = ["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"]
      state = build_state(%{subscriptions: MapSet.new(channels)})

      result = SubscriptionManager.build_restore_message(state)

      assert is_binary(result)
      decoded = Jason.decode!(result)
      assert decoded["method"] == "public/subscribe"
      assert Enum.sort(decoded["params"]["channels"]) == Enum.sort(channels)
    end

    test "single subscription returns valid message" do
      state = build_state(%{subscriptions: MapSet.new(["ticker.BTC-PERPETUAL"])})

      result = SubscriptionManager.build_restore_message(state)

      decoded = Jason.decode!(result)
      assert decoded["method"] == "public/subscribe"
      assert decoded["params"]["channels"] == ["ticker.BTC-PERPETUAL"]
    end
  end

  describe "handle_message/2" do
    test "adds channel from subscription confirmation" do
      state = build_state()

      msg = %{
        "method" => "subscription",
        "params" => %{
          "channel" => "ticker.BTC-PERPETUAL",
          "data" => %{"price" => 50_000}
        }
      }

      result = SubscriptionManager.handle_message(msg, state)

      assert MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
    end

    test "handles message without channel" do
      state = build_state()
      msg = %{"method" => "subscription", "params" => %{}}

      result = SubscriptionManager.handle_message(msg, state)

      assert result == state
    end

    test "handles message without params" do
      state = build_state()
      msg = %{"method" => "subscription"}

      result = SubscriptionManager.handle_message(msg, state)

      assert result == state
    end

    test "handles completely unexpected message format" do
      state = build_state()
      msg = %{"unknown" => "format"}

      result = SubscriptionManager.handle_message(msg, state)

      assert result == state
    end
  end

  describe "telemetry events" do
    setup do
      # Attach telemetry handler for testing
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach("test-sub-add", [:zen_websocket, :subscription_manager, :add], handler, nil)
      :telemetry.attach("test-sub-remove", [:zen_websocket, :subscription_manager, :remove], handler, nil)
      :telemetry.attach("test-sub-restore", [:zen_websocket, :subscription_manager, :restore], handler, nil)

      on_exit(fn ->
        :telemetry.detach("test-sub-add")
        :telemetry.detach("test-sub-remove")
        :telemetry.detach("test-sub-restore")
      end)

      :ok
    end

    test "emits telemetry event on add" do
      state = build_state()
      SubscriptionManager.add(state, "ticker.BTC-PERPETUAL")

      assert_receive {:telemetry_event, [:zen_websocket, :subscription_manager, :add], %{count: 1},
                      %{channel: "ticker.BTC-PERPETUAL"}}
    end

    test "emits telemetry event on remove" do
      state = build_state(%{subscriptions: MapSet.new(["ticker.BTC-PERPETUAL"])})
      SubscriptionManager.remove(state, "ticker.BTC-PERPETUAL")

      assert_receive {:telemetry_event, [:zen_websocket, :subscription_manager, :remove], %{count: 1},
                      %{channel: "ticker.BTC-PERPETUAL"}}
    end

    test "emits telemetry event on restore" do
      channels = ["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"]
      state = build_state(%{subscriptions: MapSet.new(channels)})

      SubscriptionManager.build_restore_message(state)

      assert_receive {:telemetry_event, [:zen_websocket, :subscription_manager, :restore], %{channel_count: 2},
                      %{channels: received_channels}}

      assert Enum.sort(received_channels) == Enum.sort(channels)
    end

    test "does not emit restore telemetry when no subscriptions" do
      state = build_state()
      SubscriptionManager.build_restore_message(state)

      refute_receive {:telemetry_event, [:zen_websocket, :subscription_manager, :restore], _, _}
    end

    test "does not emit restore telemetry when restore disabled" do
      config = %ZenWebsocket.Config{
        url: "wss://test.example.com",
        timeout: 5000,
        retry_count: 3,
        retry_delay: 1000,
        max_backoff: 30_000,
        heartbeat_interval: 30_000,
        request_timeout: 10_000,
        reconnect_on_error: true,
        restore_subscriptions: false
      }

      state = %{config: config, subscriptions: MapSet.new(["ticker.BTC-PERPETUAL"])}
      SubscriptionManager.build_restore_message(state)

      refute_receive {:telemetry_event, [:zen_websocket, :subscription_manager, :restore], _, _}
    end
  end

  describe "integration scenarios" do
    test "full subscribe -> disconnect -> restore cycle" do
      # Initial state
      state = build_state()

      # Subscribe to multiple channels
      state =
        SubscriptionManager.handle_message(
          %{"params" => %{"channel" => "ticker.BTC-PERPETUAL"}},
          state
        )

      state =
        SubscriptionManager.handle_message(
          %{"params" => %{"channel" => "ticker.ETH-PERPETUAL"}},
          state
        )

      assert MapSet.size(state.subscriptions) == 2

      # Build restore message (simulating reconnection)
      restore_msg = SubscriptionManager.build_restore_message(state)
      assert is_binary(restore_msg)

      decoded = Jason.decode!(restore_msg)
      assert length(decoded["params"]["channels"]) == 2
    end

    test "unsubscribe removes from restore set" do
      state =
        build_state(%{
          subscriptions: MapSet.new(["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"])
        })

      # Unsubscribe from one channel
      state = SubscriptionManager.remove(state, "ticker.BTC-PERPETUAL")

      # Restore should only include remaining channel
      restore_msg = SubscriptionManager.build_restore_message(state)
      decoded = Jason.decode!(restore_msg)
      assert decoded["params"]["channels"] == ["ticker.ETH-PERPETUAL"]
    end
  end
end
