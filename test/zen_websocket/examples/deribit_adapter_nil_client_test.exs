defmodule ZenWebsocket.Examples.DeribitAdapterNilClientTest do
  @moduledoc """
  Regression tests for R027: nil-client guards on DeribitAdapter functions.
  Verifies all public functions return {:error, :not_connected} when client is nil.
  """
  use ExUnit.Case, async: true

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

  describe "R027: nil-client guards" do
    test "authenticate/1 returns :not_connected when client is nil" do
      assert {:error, :not_connected} = DeribitAdapter.authenticate(nil_client_adapter())
    end

    test "authenticate/1 returns :not_connected when both client and client_id are nil" do
      adapter = %{nil_client_adapter() | client_id: nil}
      assert {:error, :not_connected} = DeribitAdapter.authenticate(adapter)
    end

    test "subscribe/2 returns :not_connected when client is nil" do
      assert {:error, :not_connected} =
               DeribitAdapter.subscribe(nil_client_adapter(), ["trades.BTC-PERPETUAL.raw"])
    end

    test "unsubscribe/2 returns :not_connected when client is nil" do
      assert {:error, :not_connected} =
               DeribitAdapter.unsubscribe(nil_client_adapter(), ["trades.BTC-PERPETUAL.raw"])
    end

    test "send_request/3 returns :not_connected when client is nil" do
      assert {:error, :not_connected} =
               DeribitAdapter.send_request(nil_client_adapter(), "public/get_time", %{})
    end
  end
end
