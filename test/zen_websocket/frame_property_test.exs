defmodule ZenWebsocket.FramePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ZenWebsocket.Frame

  @ws_types [:text, :binary, :ping, :pong]

  describe "Gun-format round-trip" do
    property "decode({:ws, type, data}) returns {:ok, {type, data}}" do
      check all type <- StreamData.member_of(@ws_types),
                data <- StreamData.binary() do
        assert Frame.decode({:ws, type, data}) == {:ok, {type, data}}
      end
    end

    property "decode({:ws, :close, _}) returns {:ok, {:close, <<>>}} regardless of payload" do
      check all data <- StreamData.binary() do
        assert Frame.decode({:ws, :close, data}) == {:ok, {:close, <<>>}}
      end
    end
  end

  describe "direct-format round-trip" do
    property "decode({type, data}) returns {:ok, {type, data}} unchanged" do
      check all type <- StreamData.member_of(@ws_types),
                data <- StreamData.binary() do
        assert Frame.decode({type, data}) == {:ok, {type, data}}
      end
    end
  end

  describe "constructor round-trips" do
    property "Frame.text/1 round-trips through decode/1" do
      check all s <- StreamData.string(:utf8) do
        assert Frame.decode({:ws, :text, s}) == {:ok, Frame.text(s)}
      end
    end

    property "Frame.binary/1 round-trips through decode/1" do
      check all data <- StreamData.binary() do
        assert Frame.decode({:ws, :binary, data}) == {:ok, Frame.binary(data)}
      end
    end

    property "Frame.pong/1 round-trips through decode/1" do
      check all payload <- StreamData.binary() do
        assert Frame.decode({:ws, :pong, payload}) == {:ok, Frame.pong(payload)}
      end
    end
  end

  describe "close-frame normalization" do
    property "decode({:close, code, reason}) discards the integer code" do
      check all code <- StreamData.integer(),
                reason <- StreamData.binary() do
        assert Frame.decode({:close, code, reason}) == {:ok, {:close, reason}}
      end
    end

    property "decode({:close, reason}) preserves the reason" do
      check all reason <- StreamData.binary() do
        assert Frame.decode({:close, reason}) == {:ok, {:close, reason}}
      end
    end
  end

  @unknown_atoms [:foo, :bar, :baz, :unknown, :nope, :weird]
  @frame_atoms [:text, :binary, :ping, :pong, :close, :ws]

  describe "totality on unknown shapes" do
    property "decode/1 of arbitrary non-frame terms returns {:error, _} without raising" do
      atom_gen = StreamData.member_of(@unknown_atoms ++ @frame_atoms)

      check all term <-
                  StreamData.one_of([
                    atom_gen,
                    StreamData.integer(),
                    StreamData.binary(),
                    StreamData.list_of(StreamData.integer(), max_length: 5),
                    StreamData.tuple({atom_gen, StreamData.binary()}),
                    StreamData.tuple({atom_gen, atom_gen, StreamData.binary()})
                  ]) do
        if known_frame?(term) do
          assert {:ok, _} = Frame.decode(term)
        else
          assert {:error, msg} = Frame.decode(term)
          assert is_binary(msg)
        end
      end
    end
  end

  defp known_frame?({:ws, type, _}) when type in [:text, :binary, :ping, :pong, :close], do: true
  defp known_frame?({type, _}) when type in [:text, :binary, :ping, :pong, :close], do: true
  defp known_frame?({:close, code, _}) when is_integer(code), do: true
  defp known_frame?(_), do: false
end
