defmodule ZenWebsocket.MessageHandler do
  @moduledoc """
  Message handling utilities for WebSocket connections.

  - Parse incoming WebSocket frames and Gun messages
  - Route messages to user-provided handler functions  
  - Handle control frames (ping/pong) automatically
  - Process WebSocket upgrade responses
  """

  alias ZenWebsocket.Frame

  @doc """
  Handle incoming Gun messages and WebSocket frames.
  Routes messages to appropriate handler function.
  """
  def handle_message(message, handler_fun \\ &default_handler/1)

  def handle_message({:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}, handler_fun) do
    result = {:websocket_upgraded, conn_pid, stream_ref}
    handler_fun.(result)
    {:ok, result}
  end

  def handle_message({:gun_ws, conn_pid, stream_ref, frame}, handler_fun) do
    case Frame.decode(frame) do
      {:ok, decoded_frame} ->
        case handle_control_frame(decoded_frame, conn_pid, stream_ref) do
          :handled ->
            {:ok, :control_frame_handled}

          :not_control ->
            result = {:message, decoded_frame}
            handler_fun.(result)
            {:ok, result}
        end

      {:error, reason} ->
        protocol_error = {:error, {:bad_frame, reason}}

        case ZenWebsocket.ErrorHandler.handle_error(protocol_error) do
          :stop ->
            error = {:protocol_error, reason}
            handler_fun.(error)
            {:error, {:protocol_error, reason}}

          _ ->
            error = {:decode_error, reason}
            handler_fun.(error)
            {:error, reason}
        end
    end
  end

  def handle_message({:gun_down, conn_pid, _protocol, reason, _killed_streams}, handler_fun) do
    result = {:connection_down, conn_pid, reason}
    handler_fun.(result)
    {:ok, result}
  end

  def handle_message({:gun_error, conn_pid, stream_ref, reason}, handler_fun) do
    result = {:connection_error, conn_pid, stream_ref, reason}
    handler_fun.(result)
    {:ok, result}
  end

  def handle_message(unknown_message, handler_fun) do
    result = {:unknown_message, unknown_message}
    handler_fun.(result)
    {:ok, result}
  end

  @doc """
  Decode a WebSocket frame and handle control frames automatically.
  Returns decoded data frames without invoking any handler callback.

  Used by the Client GenServer which has its own routing layer (route_data_frame)
  for JSON parsing, subscription routing, and heartbeat handling.
  """
  @spec decode_and_handle_control(tuple()) ::
          {:ok, {:data, {atom(), binary()}}}
          | {:ok, :control_frame_handled}
          | {:error, {:protocol_error, term()}}
          | {:error, {:decode_error, term()}}
  def decode_and_handle_control({:gun_ws, conn_pid, stream_ref, frame}) do
    case Frame.decode(frame) do
      {:ok, decoded_frame} ->
        case handle_control_frame(decoded_frame, conn_pid, stream_ref) do
          :handled -> {:ok, :control_frame_handled}
          :not_control -> {:ok, {:data, decoded_frame}}
        end

      {:error, reason} ->
        # Classify via ErrorHandler: bad_frame errors are fatal protocol errors
        case ZenWebsocket.ErrorHandler.handle_error({:error, {:bad_frame, reason}}) do
          :stop -> {:error, {:protocol_error, reason}}
          _ -> {:error, {:decode_error, reason}}
        end
    end
  end

  @doc """
  Handle WebSocket control frames automatically.
  Returns :handled for control frames, :not_control for data frames.
  """
  def handle_control_frame({:ping, data}, conn_pid, stream_ref) do
    :gun.ws_send(conn_pid, stream_ref, Frame.pong(data))
    :handled
  end

  def handle_control_frame({:pong, _data}, _conn_pid, _stream_ref) do
    :handled
  end

  def handle_control_frame({:close, _code, _reason}, _conn_pid, _stream_ref) do
    :handled
  end

  def handle_control_frame({:close, _reason}, _conn_pid, _stream_ref) do
    :handled
  end

  def handle_control_frame(_frame, _conn_pid, _stream_ref) do
    :not_control
  end

  @doc """
  Default message handler that simply logs messages.
  """
  def default_handler(_message) do
    :ok
  end

  @doc """
  Create a callback function for handling specific message types.
  """
  def create_handler(opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_handler/1)
    on_upgrade = Keyword.get(opts, :on_upgrade, &default_handler/1)
    on_error = Keyword.get(opts, :on_error, &default_handler/1)
    on_down = Keyword.get(opts, :on_down, &default_handler/1)

    fn
      {:message, frame} -> on_message.(frame)
      {:websocket_upgraded, conn_pid, stream_ref} -> on_upgrade.({conn_pid, stream_ref})
      {:decode_error, reason} -> on_error.(reason)
      {:protocol_error, reason} -> on_error.({:protocol_error, reason})
      {:connection_error, conn_pid, stream_ref, reason} -> on_error.({conn_pid, stream_ref, reason})
      {:connection_down, conn_pid, reason} -> on_down.({conn_pid, reason})
      {:unknown_message, msg} -> on_error.(msg)
      other -> on_error.(other)
    end
  end
end
