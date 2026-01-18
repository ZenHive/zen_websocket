defmodule ZenWebsocket.Examples.Docs.SubscriptionManagement do
  @moduledoc """
  Examples of subscription management with WebSocket connections.
  """

  alias ZenWebsocket.Client

  @doc """
  Subscribe to multiple data streams using echo server.
  """
  def multi_channel_subscription do
    {:ok, client} = Client.connect("wss://echo.websocket.org")

    # Subscribe to multiple channels
    channels = ["trades.BTC-USD", "orderbook.ETH-USD", "ticker.SOL-USD"]

    # Send subscription message (echo server will echo it back)
    subscription_message = %{
      "action" => "subscribe",
      "channels" => channels
    }

    :ok = Client.send_message(client, Jason.encode!(subscription_message))

    # Return client and channels for verification
    {:ok, client, channels}
  end

  @doc """
  Process market data updates with pattern matching.
  """
  def handle_market_data(timeout \\ 5000) do
    receive do
      {:websocket_message, message} when is_binary(message) ->
        case Jason.decode(message) do
          {:ok, %{"channel" => channel, "data" => data}} ->
            {:market_update, channel, data}

          {:ok, decoded} ->
            {:message, decoded}

          {:error, _} ->
            {:text_message, message}
        end

      {:websocket_closed, reason} ->
        {:closed, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Subscribe and process messages in a loop.
  """
  def subscription_loop(client, channels, message_count \\ 5) do
    # Subscribe to channels
    subscription = %{"action" => "subscribe", "channels" => channels}
    :ok = Client.send_message(client, Jason.encode!(subscription))

    # Collect messages
    collect_messages(message_count, [])
  end

  defp collect_messages(0, acc), do: {:ok, Enum.reverse(acc)}

  defp collect_messages(count, acc) do
    receive do
      {:websocket_message, message} ->
        collect_messages(count - 1, [message | acc])
    after
      1000 -> {:error, :timeout, Enum.reverse(acc)}
    end
  end
end
