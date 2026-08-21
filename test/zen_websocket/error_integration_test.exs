defmodule ZenWebsocket.ErrorIntegrationTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client
  alias ZenWebsocket.ErrorHandler

  @moduletag :integration

  @test_ws_url "wss://test.deribit.com/ws/api/v2"
  @invalid_url "wss://invalid-domain-that-does-not-exist.com/ws"

  describe "connection errors" do
    test "handles invalid domain gracefully" do
      assert {:error, reason} = Client.connect(@invalid_url)

      {category, _} = ErrorHandler.categorize_error(reason)
      assert category == :recoverable

      # Test that we can at least handle the error properly
      result = ErrorHandler.handle_error(reason)
      assert result == :reconnect
      assert ErrorHandler.recoverable?(reason)
    end

    test "handles connection timeout" do
      config = ZenWebsocket.Config.new!(@test_ws_url, timeout: 1)

      assert {:error, reason} = Client.connect(config)

      assert reason in [:timeout, :connection_failed, {:error, :timeout}],
             "Expected timeout or connection_failed, got: #{inspect(reason)}"

      assert ErrorHandler.recoverable?(reason)
      assert ErrorHandler.handle_error(reason) == :reconnect
    end

    test "reconnect function handles errors properly" do
      {:ok, client} = Client.connect(@test_ws_url)
      :ok = Client.close(client)

      assert {:ok, new_client} = Client.reconnect(client)
      assert Client.get_state(new_client) == :connected
      :ok = Client.close(new_client)
    end
  end

  describe "authentication errors with Deribit" do
    test "handles invalid credentials gracefully" do
      {:ok, client} = Client.connect(@test_ws_url)

      # Send invalid authentication request
      invalid_auth_message =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 1,
          method: "public/auth",
          params: %{
            grant_type: "client_credentials",
            client_id: "invalid_client_id",
            client_secret: "invalid_secret"
          }
        })

      assert {:ok, %{"id" => 1, "error" => %{"code" => 13_004, "message" => "invalid_credentials"}}} =
               Client.send_message(client, invalid_auth_message)

      # We can't easily test the error response in this simple test,
      # but we've verified the message sending mechanism works

      Client.close(client)
    end
  end

  describe "protocol errors" do
    test "handles malformed JSON gracefully" do
      {:ok, client} = Client.connect(@test_ws_url)

      # Invalid JSON is still a valid WebSocket text frame. extract_id/1 returns
      # :no_id, so send_message/2 is fire-and-forget and Gun returns :ok.
      invalid_json = "{ invalid json structure"
      assert :ok = Client.send_message(client, invalid_json)
      assert Client.get_state(client) == :connected

      Client.close(client)
    end

    test "ErrorHandler categorizes frame errors correctly" do
      frame_error = {:error, {:bad_frame, :invalid_opcode}}

      assert {:fatal, ^frame_error} = ErrorHandler.categorize_error(frame_error)
      assert ErrorHandler.handle_error(frame_error) == :stop
      refute ErrorHandler.recoverable?(frame_error)
    end
  end

  describe "error recovery patterns" do
    test "connection errors are marked as recoverable" do
      connection_errors = [
        {:error, :econnrefused},
        {:error, :timeout},
        {:error, :nxdomain},
        {:gun_down, self(), :http, :closed, []},
        {:gun_error, self(), make_ref(), :timeout}
      ]

      for error <- connection_errors do
        assert ErrorHandler.recoverable?(error), "Expected #{inspect(error)} to be recoverable"
        assert ErrorHandler.handle_error(error) == :reconnect
      end
    end

    test "protocol and auth errors are not recoverable" do
      non_recoverable_errors = [
        {:error, :invalid_frame},
        {:error, :unauthorized},
        {:error, :invalid_credentials},
        {:error, {:bad_frame, :invalid_opcode}}
      ]

      for error <- non_recoverable_errors do
        refute ErrorHandler.recoverable?(error), "Expected #{inspect(error)} to not be recoverable"
        assert ErrorHandler.handle_error(error) == :stop
      end
    end
  end
end
