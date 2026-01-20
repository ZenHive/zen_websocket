defmodule ZenWebsocket.FrameTest do
  use ExUnit.Case

  alias ZenWebsocket.Frame

  describe "encoding frames" do
    test "text/1 creates text frame" do
      frame = Frame.text("hello world")
      assert frame == {:text, "hello world"}
    end

    test "binary/1 creates binary frame" do
      data = <<1, 2, 3, 4>>
      frame = Frame.binary(data)
      assert frame == {:binary, data}
    end

    test "ping/0 creates ping frame" do
      frame = Frame.ping()
      assert frame == {:ping, <<>>}
    end

    test "pong/1 creates pong frame with payload" do
      frame = Frame.pong("ping-data")
      assert frame == {:pong, "ping-data"}
    end

    test "pong/0 creates pong frame without payload" do
      frame = Frame.pong()
      assert frame == {:pong, <<>>}
    end
  end

  describe "decoding frames" do
    test "decode/1 handles text frames" do
      {:ok, frame} = Frame.decode({:ws, :text, "hello"})
      assert frame == {:text, "hello"}
    end

    test "decode/1 handles binary frames" do
      data = <<1, 2, 3>>
      {:ok, frame} = Frame.decode({:ws, :binary, data})
      assert frame == {:binary, data}
    end

    test "decode/1 handles ping frames" do
      {:ok, frame} = Frame.decode({:ws, :ping, "ping-data"})
      assert frame == {:ping, "ping-data"}
    end

    test "decode/1 handles pong frames" do
      {:ok, frame} = Frame.decode({:ws, :pong, "pong-data"})
      assert frame == {:pong, "pong-data"}
    end

    test "decode/1 handles close frames" do
      {:ok, frame} = Frame.decode({:ws, :close, <<1000::16>>})
      assert frame == {:close, <<>>}
    end

    test "decode/1 handles unknown frames gracefully" do
      {:error, message} = Frame.decode({:unknown, :frame})
      assert message =~ "Unknown frame type"
    end
  end

  describe "decoding direct frame format" do
    test "decode/1 handles direct text frames" do
      {:ok, frame} = Frame.decode({:text, "direct text"})
      assert frame == {:text, "direct text"}
    end

    test "decode/1 handles direct binary frames" do
      data = <<5, 6, 7>>
      {:ok, frame} = Frame.decode({:binary, data})
      assert frame == {:binary, data}
    end

    test "decode/1 handles direct ping frames" do
      {:ok, frame} = Frame.decode({:ping, "ping-payload"})
      assert frame == {:ping, "ping-payload"}
    end

    test "decode/1 handles direct pong frames" do
      {:ok, frame} = Frame.decode({:pong, "pong-payload"})
      assert frame == {:pong, "pong-payload"}
    end

    test "decode/1 handles close with code and reason" do
      {:ok, frame} = Frame.decode({:close, 1000, "normal closure"})
      assert frame == {:close, "normal closure"}
    end

    test "decode/1 handles close with just reason" do
      {:ok, frame} = Frame.decode({:close, "going away"})
      assert frame == {:close, "going away"}
    end
  end
end
