defmodule ZenWebsocket.MessageHandlerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ZenWebsocket.MessageHandler
  alias ZenWebsocket.Test.Support.GunStub

  describe "routing totality" do
    property "arbitrary non-Gun tuples route to :unknown_message without raising" do
      check all size <- StreamData.integer(0..6),
                elements <- StreamData.list_of(StreamData.term(), length: size) do
        msg = List.to_tuple(elements)

        # Only skip tuples that actually match a real handle_message/2 clause.
        # Malformed gun-headed tuples (wrong arity, wrong upgrade marker) must
        # still route through the catchall to :unknown_message.
        if !matches_real_clause?(msg) do
          assert {:ok, {:unknown_message, ^msg}} =
                   MessageHandler.handle_message(msg, &noop/1)
        end
      end
    end
  end

  describe "gun_down" do
    property "always routes to :connection_down regardless of reason term" do
      check all reason <- StreamData.term() do
        pid = self()
        msg = GunStub.gun_down(reason: reason, conn_pid: pid)

        assert {:ok, {:connection_down, ^pid, ^reason}} =
                 MessageHandler.handle_message(msg, &noop/1)
      end
    end
  end

  describe "gun_error" do
    property "always routes to :connection_error regardless of reason term" do
      check all reason <- StreamData.term() do
        pid = self()
        ref = make_ref()
        msg = GunStub.gun_error(reason: reason, conn_pid: pid, stream_ref: ref)

        assert {:ok, {:connection_error, ^pid, ^ref, ^reason}} =
                 MessageHandler.handle_message(msg, &noop/1)
      end
    end
  end

  describe "data frame dispatch" do
    property "text frames reach the handler callback" do
      check all payload <- StreamData.string(:utf8) do
        test_pid = self()
        handler = fn decoded -> send(test_pid, {:handled, decoded}) end

        MessageHandler.handle_message(GunStub.gun_ws(frame: {:text, payload}), handler)

        assert_received {:handled, {:message, {:text, ^payload}}}
      end
    end

    property "binary frames reach the handler callback" do
      check all payload <- StreamData.binary() do
        test_pid = self()
        handler = fn decoded -> send(test_pid, {:handled, decoded}) end

        MessageHandler.handle_message(GunStub.gun_ws(frame: {:binary, payload}), handler)

        assert_received {:handled, {:message, {:binary, ^payload}}}
      end
    end
  end

  defp matches_real_clause?({:gun_upgrade, _, _, ["websocket"], _}), do: true
  defp matches_real_clause?({:gun_ws, _, _, _}), do: true
  defp matches_real_clause?({:gun_down, _, _, _, _}), do: true
  defp matches_real_clause?({:gun_error, _, _, _}), do: true
  defp matches_real_clause?(_), do: false

  defp noop(_msg), do: :ok
end
