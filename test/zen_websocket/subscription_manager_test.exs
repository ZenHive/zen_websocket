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
      assert [_, _, _] = result
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
    test "does not add a data-tick channel that was never subscribed" do
      state = build_state()

      msg = %{
        "method" => "subscription",
        "params" => %{
          "channel" => "ticker.ETH-PERPETUAL.100ms",
          "data" => %{"price" => 50_000}
        }
      }

      result = SubscriptionManager.handle_message(msg, state)

      refute MapSet.member?(result.subscriptions, "ticker.ETH-PERPETUAL.100ms")
      assert MapSet.size(result.subscriptions) == 0
    end

    test "does not re-add a data tick after remove/2" do
      state = build_state(%{subscriptions: MapSet.new(["book.BTC-PERPETUAL.raw"])})
      state = SubscriptionManager.remove(state, "book.BTC-PERPETUAL.raw")
      assert SubscriptionManager.list(state) == []

      tick = %{
        "method" => "subscription",
        "params" => %{"channel" => "book.BTC-PERPETUAL.raw", "data" => %{}}
      }

      result = SubscriptionManager.handle_message(tick, state)

      assert SubscriptionManager.list(result) == []
      assert SubscriptionManager.build_restore_message(result) == nil
    end

    test "subscribe without an id adds channels immediately" do
      state = build_state()

      msg = %{
        "method" => "public/subscribe",
        "params" => %{"channels" => ["ticker.BTC-PERPETUAL"]}
      }

      result = SubscriptionManager.handle_message(msg, state)

      assert MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
    end

    test "does not auto-track a non-Deribit params.channel shape" do
      state = build_state()

      result =
        SubscriptionManager.handle_message(%{"params" => %{"channel" => "trades.BTC-USD"}}, state)

      refute MapSet.member?(result.subscriptions, "trades.BTC-USD")
      assert SubscriptionManager.list(result) == []
      assert SubscriptionManager.build_restore_message(result) == nil
    end

    test "id-less public/subscribe stays tracked after a server rejection" do
      state = build_state()

      state =
        SubscriptionManager.handle_message(
          %{
            "method" => "public/subscribe",
            "params" => %{"channels" => ["ticker.BTC-PERPETUAL"]}
          },
          state
        )

      result =
        SubscriptionManager.handle_message(
          %{"id" => nil, "error" => %{"code" => 13_009, "message" => "unauthorized"}},
          state
        )

      assert MapSet.member?(result.subscriptions, "ticker.BTC-PERPETUAL")
      restore = Jason.decode!(SubscriptionManager.build_restore_message(result))
      assert "ticker.BTC-PERPETUAL" in restore["params"]["channels"]
    end

    test "registers a channel from a realistic Deribit subscribe confirmation" do
      state = build_state()

      outbound = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "public/subscribe",
        "params" => %{"channels" => ["book.BTC-PERPETUAL.raw"]}
      }

      confirmation = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "result" => ["book.BTC-PERPETUAL.raw"]
      }

      state = SubscriptionManager.handle_message(outbound, state)
      result = SubscriptionManager.handle_message(confirmation, state)

      assert MapSet.member?(result.subscriptions, "book.BTC-PERPETUAL.raw")
    end

    test "does not track an id/result list that is not a pending subscribe" do
      state = build_state()

      confirmation = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "result" => ["book.BTC-PERPETUAL.raw"]
      }

      result = SubscriptionManager.handle_message(confirmation, state)

      refute MapSet.member?(result.subscriptions, "book.BTC-PERPETUAL.raw")
    end

    test "a JSON-RPC error drops the pending subscribe so a later result does not add" do
      state = build_state()

      state =
        SubscriptionManager.handle_message(
          %{
            "id" => 7,
            "method" => "public/subscribe",
            "params" => %{"channels" => ["book.BTC-PERPETUAL.raw"]}
          },
          state
        )

      state =
        SubscriptionManager.handle_message(
          %{"id" => 7, "error" => %{"code" => 13_009, "message" => "unauthorized"}},
          state
        )

      result =
        SubscriptionManager.handle_message(%{"id" => 7, "result" => ["book.BTC-PERPETUAL.raw"]}, state)

      refute MapSet.member?(result.subscriptions, "book.BTC-PERPETUAL.raw")
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
      state = build_state()

      state =
        SubscriptionManager.handle_message(
          %{
            "id" => 1,
            "method" => "public/subscribe",
            "params" => %{"channels" => ["ticker.BTC-PERPETUAL"]}
          },
          state
        )

      state =
        SubscriptionManager.handle_message(%{"id" => 1, "result" => ["ticker.BTC-PERPETUAL"]}, state)

      state =
        SubscriptionManager.handle_message(
          %{
            "id" => 2,
            "method" => "public/subscribe",
            "params" => %{"channels" => ["ticker.ETH-PERPETUAL"]}
          },
          state
        )

      state =
        SubscriptionManager.handle_message(%{"id" => 2, "result" => ["ticker.ETH-PERPETUAL"]}, state)

      assert MapSet.size(state.subscriptions) == 2

      restore_msg = SubscriptionManager.build_restore_message(state)
      assert is_binary(restore_msg)

      decoded = Jason.decode!(restore_msg)
      assert [_, _] = decoded["params"]["channels"]
    end

    test "unsubscribe removes from restore set" do
      state =
        build_state(%{
          subscriptions: MapSet.new(["ticker.BTC-PERPETUAL", "ticker.ETH-PERPETUAL"])
        })

      state =
        SubscriptionManager.handle_message(
          %{
            "id" => 3,
            "method" => "public/unsubscribe",
            "params" => %{"channels" => ["ticker.BTC-PERPETUAL"]}
          },
          state
        )

      state =
        SubscriptionManager.handle_message(%{"id" => 3, "result" => ["ticker.BTC-PERPETUAL"]}, state)

      restore_msg = SubscriptionManager.build_restore_message(state)
      decoded = Jason.decode!(restore_msg)
      assert decoded["params"]["channels"] == ["ticker.ETH-PERPETUAL"]
    end

    test "an unsubscribed channel is not restored on reconnect" do
      state = build_state(%{subscriptions: MapSet.new(["book.BTC-PERPETUAL.raw"])})

      state =
        SubscriptionManager.handle_message(
          %{
            "id" => 4,
            "method" => "public/unsubscribe",
            "params" => %{"channels" => ["book.BTC-PERPETUAL.raw"]}
          },
          state
        )

      state =
        SubscriptionManager.handle_message(
          %{
            "jsonrpc" => "2.0",
            "id" => 4,
            "result" => ["book.BTC-PERPETUAL.raw"]
          },
          state
        )

      assert SubscriptionManager.list(state) == []
      assert SubscriptionManager.build_restore_message(state) == nil
    end
  end
end
