defmodule ZenWebsocket.Examples.SubscriptionManagementTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.Examples.Docs.SubscriptionManagement

  @moduletag :integration

  @echo_server "wss://echo.websocket.org"

  describe "multi_channel_subscription/0" do
    test "creates connection and sends subscription message" do
      {:ok, client, channels} = SubscriptionManagement.multi_channel_subscription()

      assert %Client{} = client
      assert channels == ["trades.BTC-USD", "orderbook.ETH-USD", "ticker.SOL-USD"]

      # Echo server should return our subscription message
      assert_receive {:websocket_message, message}, 2000
      assert is_binary(message)

      # Clean up
      Client.close(client)
    end
  end

  describe "handle_market_data/1" do
    test "processes JSON market update messages" do
      # Simulate market update message
      market_update = %{
        "channel" => "trades.BTC-USD",
        "data" => %{"price" => 50_000, "amount" => 0.5}
      }

      send(self(), {:websocket_message, Jason.encode!(market_update)})

      assert {:market_update, "trades.BTC-USD", %{"price" => 50_000, "amount" => 0.5}} =
               SubscriptionManagement.handle_market_data()
    end

    test "handles regular JSON messages" do
      message = %{"status" => "connected", "version" => "1.0"}
      send(self(), {:websocket_message, Jason.encode!(message)})

      assert {:message, %{"status" => "connected", "version" => "1.0"}} =
               SubscriptionManagement.handle_market_data()
    end

    test "handles non-JSON text messages" do
      send(self(), {:websocket_message, "Plain text message"})

      assert {:text_message, "Plain text message"} =
               SubscriptionManagement.handle_market_data()
    end

    test "handles connection closed messages" do
      send(self(), {:websocket_closed, :normal})

      assert {:closed, :normal} = SubscriptionManagement.handle_market_data()
    end

    test "times out when no message received" do
      assert {:error, :timeout} = SubscriptionManagement.handle_market_data(100)
    end
  end

  describe "subscription_loop/3" do
    test "collects multiple messages from echo server" do
      {:ok, client} = Client.connect(@echo_server)
      channels = ["test.channel"]

      # Send multiple messages
      spawn(fn ->
        Process.sleep(100)

        for i <- 1..3 do
          :ok = Client.send_message(client, "Message #{i}")
          Process.sleep(50)
        end
      end)

      # Collect subscription + 3 messages
      result = SubscriptionManagement.subscription_loop(client, channels, 4)

      case result do
        {:ok, messages} ->
          # Messages might be in different formats from echo server
          assert length(messages) == 4

        {:error, :timeout, messages} ->
          # Echo server might be slow, but we should have some messages
          assert messages != []
      end

      Client.close(client)
    end
  end

  describe "subscription patterns" do
    test "multiple clients can subscribe independently" do
      {:ok, client1} = Client.connect(@echo_server)
      {:ok, client2} = Client.connect(@echo_server)

      # Client 1 subscribes to BTC channels
      btc_sub = %{"action" => "subscribe", "channels" => ["trades.BTC-USD", "orderbook.BTC-USD"]}
      :ok = Client.send_message(client1, Jason.encode!(btc_sub))

      # Client 2 subscribes to ETH channels
      eth_sub = %{"action" => "subscribe", "channels" => ["trades.ETH-USD", "orderbook.ETH-USD"]}
      :ok = Client.send_message(client2, Jason.encode!(eth_sub))

      # Both should receive their subscription confirmations
      assert_receive {:websocket_message, _message1}, 2000
      assert_receive {:websocket_message, _message2}, 2000

      Client.close(client1)
      Client.close(client2)
    end

    test "can unsubscribe from channels" do
      {:ok, client} = Client.connect(@echo_server)

      # Subscribe
      sub_msg = %{"action" => "subscribe", "channels" => ["trades.BTC-USD"]}
      :ok = Client.send_message(client, Jason.encode!(sub_msg))
      assert_receive {:websocket_message, _}, 2000

      # Unsubscribe
      unsub_msg = %{"action" => "unsubscribe", "channels" => ["trades.BTC-USD"]}
      :ok = Client.send_message(client, Jason.encode!(unsub_msg))
      assert_receive {:websocket_message, _}, 2000

      Client.close(client)
    end

    test "handles subscription with custom handler" do
      # Custom handler that filters messages
      pid = self()

      handler = fn
        {:message, {:text, text}} ->
          case Jason.decode(text) do
            {:ok, %{"action" => "subscribe"} = decoded} ->
              send(pid, {:subscription_confirmed, decoded})

            {:error, _} ->
              :ok
          end

        {:message, {:binary, data}} ->
          case Jason.decode(data) do
            {:ok, %{"action" => "subscribe"} = decoded} ->
              send(pid, {:subscription_confirmed, decoded})

            {:error, _} ->
              :ok
          end

        _other ->
          :ok
      end

      {:ok, client} = Client.connect(@echo_server, handler: handler)

      # Send subscription
      sub_msg = %{"action" => "subscribe", "channels" => ["test.channel"]}
      :ok = Client.send_message(client, Jason.encode!(sub_msg))

      # Should receive filtered message
      assert_receive {:subscription_confirmed, %{"action" => "subscribe"}}, 2000

      Client.close(client)
    end
  end

  describe "subscription error handling" do
    test "handles malformed subscription messages gracefully" do
      {:ok, client} = Client.connect(@echo_server)

      # Send malformed JSON
      :ok = Client.send_message(client, "{invalid json")

      # Should still receive the echo
      assert_receive {:websocket_message, _}, 2000

      Client.close(client)
    end

    test "continues receiving after subscription errors" do
      {:ok, client} = Client.connect(@echo_server)

      # Send invalid then valid message
      :ok = Client.send_message(client, "invalid")
      :ok = Client.send_message(client, Jason.encode!(%{"valid" => true}))

      # Should receive both echoes
      assert_receive {:websocket_message, "invalid"}, 2000
      assert_receive {:websocket_message, valid_json}, 2000
      # Echo server might return different format
      assert is_binary(valid_json) or match?({:text, _}, valid_json)

      Client.close(client)
    end
  end
end
