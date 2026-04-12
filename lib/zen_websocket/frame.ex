defmodule ZenWebsocket.Frame do
  @moduledoc """
  WebSocket frame encoding and decoding utilities.
  """

  use Descripex, namespace: "/frame"

  @type frame_type :: :text | :binary | :ping | :pong | :close
  @type frame :: {frame_type(), binary()}

  api(:text, "Encode a text message as a WebSocket frame.",
    params: [message: [kind: :value, description: "Text message string"]],
    returns: %{type: "frame()", description: "{:text, message} frame tuple"}
  )

  @doc """
  Encode text message as WebSocket frame.
  """
  @spec text(String.t()) :: frame()
  def text(message) when is_binary(message) do
    {:text, message}
  end

  api(:binary, "Encode binary data as a WebSocket frame.",
    params: [data: [kind: :value, description: "Binary data to encode"]],
    returns: %{type: "frame()", description: "{:binary, data} frame tuple"}
  )

  @doc """
  Encode binary message as WebSocket frame.
  """
  @spec binary(binary()) :: frame()
  def binary(data) when is_binary(data) do
    {:binary, data}
  end

  api(:ping, "Create a WebSocket ping frame.", returns: %{type: "frame()", description: "{:ping, <<>>} frame tuple"})

  @doc """
  Create ping frame.
  """
  @spec ping() :: frame()
  def ping do
    {:ping, <<>>}
  end

  api(:pong, "Create a WebSocket pong frame with optional payload.",
    params: [payload: [kind: :value, description: "Pong payload bytes", default: "<<>>"]],
    returns: %{type: "frame()", description: "{:pong, payload} frame tuple"}
  )

  @doc """
  Create pong frame with payload.
  """
  @spec pong(binary()) :: frame()
  def pong(payload \\ <<>>) when is_binary(payload) do
    {:pong, payload}
  end

  api(:decode, "Decode an incoming WebSocket frame from Gun or direct format.",
    params: [frame: [kind: :value, description: "Raw frame tuple ({:ws, type, data} or {type, data})"]],
    returns: %{type: "{:ok, frame()} | {:error, String.t()}", description: "Decoded frame or error"},
    errors: [:unknown_frame_type]
  )

  @doc """
  Decode incoming WebSocket frame.
  Handles both Gun WebSocket format {:ws, type, data} and direct frame format {:type, data}.
  """
  @spec decode(tuple()) :: {:ok, frame()} | {:error, String.t()}
  def decode({:ws, :text, data}), do: {:ok, {:text, data}}
  def decode({:ws, :binary, data}), do: {:ok, {:binary, data}}
  def decode({:ws, :ping, data}), do: {:ok, {:ping, data}}
  def decode({:ws, :pong, data}), do: {:ok, {:pong, data}}
  def decode({:ws, :close, _}), do: {:ok, {:close, <<>>}}

  # Handle direct frame format (for testing and compatibility)
  def decode({:text, data}), do: {:ok, {:text, data}}
  def decode({:binary, data}), do: {:ok, {:binary, data}}
  def decode({:ping, data}), do: {:ok, {:ping, data}}
  def decode({:pong, data}), do: {:ok, {:pong, data}}
  def decode({:close, code, reason}) when is_integer(code), do: {:ok, {:close, reason}}
  def decode({:close, reason}), do: {:ok, {:close, reason}}

  def decode(frame), do: {:error, "Unknown frame type: #{inspect(frame)}"}
end
