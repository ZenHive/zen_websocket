defmodule ZenWebsocket.Examples.BatchSubscriptionManagerTest do
  @moduledoc """
  Regression tests for R028: BatchSubscriptionManager error handling.
  Uses a nil-client adapter to trigger real subscribe failures.
  """
  use ExUnit.Case, async: true

  alias ZenWebsocket.Examples.BatchSubscriptionManager
  alias ZenWebsocket.Examples.DeribitAdapter

  defp nil_client_adapter do
    %DeribitAdapter{
      client: nil,
      authenticated: false,
      subscriptions: MapSet.new(),
      client_id: "test_id",
      client_secret: "test_secret"
    }
  end

  describe "R028: subscribe failure handling" do
    test "marks request as failed when subscribe returns error" do
      {:ok, manager} =
        BatchSubscriptionManager.start_link(
          adapter: nil_client_adapter(),
          batch_size: 2,
          batch_delay: 50
        )

      {:ok, request_id} =
        BatchSubscriptionManager.subscribe_batch(manager, [
          "trades.BTC-PERPETUAL.raw",
          "trades.ETH-PERPETUAL.raw"
        ])

      # Allow the async batch processing to fire
      Process.sleep(100)

      {:ok, status} = BatchSubscriptionManager.get_status(manager, request_id)
      assert status.failed == true
      assert status.error == :not_connected
      assert status.completed == 0
    end

    test "stops processing subsequent batches after failure" do
      {:ok, manager} =
        BatchSubscriptionManager.start_link(
          adapter: nil_client_adapter(),
          batch_size: 1,
          batch_delay: 50
        )

      {:ok, request_id} =
        BatchSubscriptionManager.subscribe_batch(manager, [
          "trades.BTC-PERPETUAL.raw",
          "trades.ETH-PERPETUAL.raw",
          "trades.SOL-PERPETUAL.raw"
        ])

      # Wait long enough for all batches to have fired if not stopped
      Process.sleep(300)

      {:ok, status} = BatchSubscriptionManager.get_status(manager, request_id)
      assert status.failed == true
      # Should still show pending since processing stopped
      assert status.pending == 3
      assert status.completed == 0
    end
  end
end
