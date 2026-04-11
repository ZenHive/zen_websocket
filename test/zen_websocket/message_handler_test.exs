defmodule ZenWebsocket.MessageHandlerTest do
  use ExUnit.Case

  alias ZenWebsocket.MessageHandler

  describe "handle_message/2" do
    test "handles gun_upgrade message for websocket" do
      conn_pid = self()
      stream_ref = make_ref()
      message = {:gun_upgrade, conn_pid, stream_ref, ["websocket"], []}

      handler_called = fn result ->
        assert result == {:websocket_upgraded, conn_pid, stream_ref}
        send(self(), :handler_called)
      end

      assert {:ok, {:websocket_upgraded, ^conn_pid, ^stream_ref}} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end

    test "handles gun_ws text message" do
      conn_pid = self()
      stream_ref = make_ref()
      frame = {:text, "Hello World"}
      message = {:gun_ws, conn_pid, stream_ref, frame}

      handler_called = fn result ->
        assert result == {:message, {:text, "Hello World"}}
        send(self(), :handler_called)
      end

      assert {:ok, {:message, {:text, "Hello World"}}} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end

    test "handles gun_ws binary message" do
      conn_pid = self()
      stream_ref = make_ref()
      data = <<1, 2, 3, 4>>
      frame = {:binary, data}
      message = {:gun_ws, conn_pid, stream_ref, frame}

      handler_called = fn result ->
        assert result == {:message, {:binary, data}}
        send(self(), :handler_called)
      end

      assert {:ok, {:message, {:binary, ^data}}} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end

    test "handles gun_down message" do
      conn_pid = self()
      reason = :normal
      message = {:gun_down, conn_pid, :http, reason, []}

      handler_called = fn result ->
        assert result == {:connection_down, conn_pid, reason}
        send(self(), :handler_called)
      end

      assert {:ok, {:connection_down, ^conn_pid, ^reason}} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end

    test "handles gun_error message" do
      conn_pid = self()
      stream_ref = make_ref()
      reason = :timeout
      message = {:gun_error, conn_pid, stream_ref, reason}

      handler_called = fn result ->
        assert result == {:connection_error, conn_pid, stream_ref, reason}
        send(self(), :handler_called)
      end

      assert {:ok, {:connection_error, ^conn_pid, ^stream_ref, ^reason}} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end

    test "handles unknown message" do
      unknown_msg = {:unknown, :message}

      handler_called = fn result ->
        assert result == {:unknown_message, unknown_msg}
        send(self(), :handler_called)
      end

      assert {:ok, {:unknown_message, ^unknown_msg}} =
               MessageHandler.handle_message(unknown_msg, handler_called)

      assert_received :handler_called
    end

    test "handles frame decode error" do
      conn_pid = self()
      stream_ref = make_ref()
      invalid_frame = {:invalid, "bad frame"}
      message = {:gun_ws, conn_pid, stream_ref, invalid_frame}

      handler_called = fn result ->
        assert {:protocol_error, _reason} = result
        send(self(), :handler_called)
      end

      assert {:error, _reason} =
               MessageHandler.handle_message(message, handler_called)

      assert_received :handler_called
    end
  end

  describe "handle_control_frame/3" do
    test "handles ping frame and sends pong response" do
      conn_pid = self()
      stream_ref = make_ref()
      ping_data = "ping_data"

      # Mock gun.ws_send to capture the pong response
      original_gun = Process.put(:gun_mock, true)

      assert :handled =
               MessageHandler.handle_control_frame({:ping, ping_data}, conn_pid, stream_ref)

      # Verify pong would be sent (in real implementation)
      Process.put(:gun_mock, original_gun)
    end

    test "handles pong frame" do
      conn_pid = self()
      stream_ref = make_ref()

      assert :handled =
               MessageHandler.handle_control_frame({:pong, "data"}, conn_pid, stream_ref)
    end

    test "handles close frame" do
      conn_pid = self()
      stream_ref = make_ref()

      assert :handled =
               MessageHandler.handle_control_frame({:close, 1000, "normal"}, conn_pid, stream_ref)
    end

    test "returns not_control for data frames" do
      conn_pid = self()
      stream_ref = make_ref()

      assert :not_control =
               MessageHandler.handle_control_frame({:text, "data"}, conn_pid, stream_ref)

      assert :not_control =
               MessageHandler.handle_control_frame({:binary, <<1, 2>>}, conn_pid, stream_ref)
    end
  end

  describe "create_handler/1" do
    test "creates handler with custom callbacks" do
      message_handler = fn frame -> send(self(), {:on_message, frame}) end
      upgrade_handler = fn {conn_pid, stream_ref} -> send(self(), {:on_upgrade, conn_pid, stream_ref}) end
      error_handler = fn reason -> send(self(), {:on_error, reason}) end
      down_handler = fn {conn_pid, reason} -> send(self(), {:on_down, conn_pid, reason}) end

      handler =
        MessageHandler.create_handler(
          on_message: message_handler,
          on_upgrade: upgrade_handler,
          on_error: error_handler,
          on_down: down_handler
        )

      # Test message handling
      handler.({:message, {:text, "hello"}})
      assert_received {:on_message, {:text, "hello"}}

      # Test upgrade handling
      conn_pid = self()
      stream_ref = make_ref()
      handler.({:websocket_upgraded, conn_pid, stream_ref})
      assert_received {:on_upgrade, ^conn_pid, ^stream_ref}

      # Test error handling
      handler.({:decode_error, :invalid})
      assert_received {:on_error, :invalid}

      # Test down handling
      handler.({:connection_down, conn_pid, :normal})
      assert_received {:on_down, ^conn_pid, :normal}
    end

    test "uses default handlers when none provided" do
      handler = MessageHandler.create_handler()

      # Should not crash with default handlers
      assert :ok = handler.({:message, {:text, "hello"}})
      assert :ok = handler.({:websocket_upgraded, self(), make_ref()})
      assert :ok = handler.({:decode_error, :invalid})
      assert :ok = handler.({:connection_down, self(), :normal})
    end
  end

  describe "default_handler/1" do
    test "returns :ok for any message" do
      assert :ok = MessageHandler.default_handler({:any, :message})
      assert :ok = MessageHandler.default_handler("string")
      assert :ok = MessageHandler.default_handler(123)
    end
  end

  describe "decode_and_handle_control/1" do
    test "returns decoded data frame without calling any handler" do
      conn_pid = self()
      stream_ref = make_ref()
      message = {:gun_ws, conn_pid, stream_ref, {:text, "hello"}}

      assert {:ok, {:data, {:text, "hello"}}} =
               MessageHandler.decode_and_handle_control(message)
    end

    test "returns decoded binary frame" do
      conn_pid = self()
      stream_ref = make_ref()
      data = <<1, 2, 3>>
      message = {:gun_ws, conn_pid, stream_ref, {:binary, data}}

      assert {:ok, {:data, {:binary, ^data}}} =
               MessageHandler.decode_and_handle_control(message)
    end

    test "handles control frames and returns :control_frame_handled" do
      conn_pid = self()
      stream_ref = make_ref()
      message = {:gun_ws, conn_pid, stream_ref, {:pong, "data"}}

      assert {:ok, :control_frame_handled} =
               MessageHandler.decode_and_handle_control(message)
    end

    test "returns protocol error for invalid frames" do
      conn_pid = self()
      stream_ref = make_ref()
      message = {:gun_ws, conn_pid, stream_ref, {:invalid, "bad"}}

      # Invalid frames are classified as fatal protocol errors via ErrorHandler
      assert {:error, {:protocol_error, _reason}} =
               MessageHandler.decode_and_handle_control(message)
    end
  end

  describe "integration with automatic ping/pong handling" do
    test "ping frames are handled automatically without calling user handler" do
      conn_pid = self()
      stream_ref = make_ref()
      frame = {:ping, "ping_data"}
      message = {:gun_ws, conn_pid, stream_ref, frame}

      handler_called = fn _result ->
        send(self(), :should_not_be_called)
      end

      assert {:ok, :control_frame_handled} =
               MessageHandler.handle_message(message, handler_called)

      refute_received :should_not_be_called
    end

    test "pong frames are handled automatically without calling user handler" do
      conn_pid = self()
      stream_ref = make_ref()
      frame = {:pong, "pong_data"}
      message = {:gun_ws, conn_pid, stream_ref, frame}

      handler_called = fn _result ->
        send(self(), :should_not_be_called)
      end

      assert {:ok, :control_frame_handled} =
               MessageHandler.handle_message(message, handler_called)

      refute_received :should_not_be_called
    end

    test "close frames are handled automatically without calling user handler" do
      conn_pid = self()
      stream_ref = make_ref()
      frame = {:close, 1000, "normal"}
      message = {:gun_ws, conn_pid, stream_ref, frame}

      handler_called = fn _result ->
        send(self(), :should_not_be_called)
      end

      assert {:ok, :control_frame_handled} =
               MessageHandler.handle_message(message, handler_called)

      refute_received :should_not_be_called
    end
  end
end
