defmodule ZenWebsocket.Client.CallbacksTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client.Callbacks, as: Callbacks
  alias ZenWebsocket.Client.Connection, as: Connection
  alias ZenWebsocket.Config

  test "handle_call :get_state returns the connection state atom" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    from = {self(), make_ref()}
    assert {:reply, :disconnected, ^state} = Callbacks.handle_call(:get_state, from, state)
  end

  test "handle_call :await_connection replies immediately when already connected" do
    state = Map.put(Connection.initial_state(%Config{url: "ws://localhost/ws"}, []), :state, :connected)
    from = {self(), make_ref()}
    assert {:reply, {:ok, ^state}, ^state} = Callbacks.handle_call(:await_connection, from, state)
  end

  test "handle_call :await_connection parks the caller when not connected" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    from = {self(), make_ref()}
    assert {:noreply, new_state} = Callbacks.handle_call(:await_connection, from, state)
    assert new_state.awaiting_connection == from
  end

  test "handle_call :send_message replies not_connected when disconnected" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    from = {self(), make_ref()}

    assert {:reply, {:error, {:not_connected, :disconnected}}, ^state} =
             Callbacks.handle_call({:send_message, "hi"}, from, state)
  end

  test "handle_call :get_latency_stats is nil with an empty sample buffer" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    from = {self(), make_ref()}
    assert {:reply, nil, ^state} = Callbacks.handle_call(:get_latency_stats, from, state)
  end

  test "handle_info ignores a stale connection_timeout" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    assert {:noreply, ^state} = Callbacks.handle_info({:connection_timeout, make_ref()}, state)
  end

  test "handle_info ignores Gun messages from a different connection" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    other = spawn(fn -> :ok end)
    assert {:noreply, ^state} = Callbacks.handle_info({:gun_error, other, make_ref(), :closed}, state)
  end

  test "handle_info ignores unknown messages" do
    state = Connection.initial_state(%Config{url: "ws://localhost/ws"}, [])
    assert {:noreply, ^state} = Callbacks.handle_info(:nope, state)
  end
end
