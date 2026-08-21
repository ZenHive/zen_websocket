defmodule ZenWebsocket.Client.CallFacadeTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.Client.CallFacade
  alias ZenWebsocket.Config

  test "process_down_exit?/1 recognizes noproc, normal, and shutdown exits" do
    assert CallFacade.process_down_exit?({:noproc, {:gen_server, :call, [self(), :x]}})
    assert CallFacade.process_down_exit?({:normal, {:gen_server, :call, [self(), :x]}})
    assert CallFacade.process_down_exit?({:shutdown, {:gen_server, :call, [self(), :x]}})
    assert CallFacade.process_down_exit?({{:shutdown, :closed}, {:gen_server, :call, [self(), :x]}})
    refute CallFacade.process_down_exit?({:timeout, {:gen_server, :call, [self(), :x]}})
    refute CallFacade.process_down_exit?(:killed)
  end

  test "unwrap_call_exit/1 maps call exits to the caller-facing reason" do
    assert CallFacade.unwrap_call_exit({:timeout, {:gen_server, :call, []}}) == :timeout
    assert CallFacade.unwrap_call_exit({:noproc, {GenServer, :call, []}}) == :noproc
    assert CallFacade.unwrap_call_exit({:shutdown, {:gen_server, :call, []}}) == :shutdown
    assert CallFacade.unwrap_call_exit(:killed) == :killed
  end

  test "with_default_handler/2 keeps an explicit handler" do
    handler = fn _msg -> :kept end
    opts = CallFacade.with_default_handler([handler: handler, timeout: 1_000], self())
    assert opts[:handler] == handler
  end

  test "with_default_handler/2 sends parent messages when no handler is given" do
    parent = self()
    opts = CallFacade.with_default_handler([], parent)
    handler = Keyword.fetch!(opts, :handler)

    handler.({:message, %{"ok" => true}})
    handler.({:binary, <<1>>})
    handler.({:unmatched_response, %{"id" => 1}})
    handler.({:protocol_error, :bad_frame})
    handler.(:ignored)

    assert_received {:websocket_message, %{"ok" => true}}
    assert_received {:websocket_message, <<1>>}
    assert_received {:websocket_unmatched_response, %{"id" => 1}}
    assert_received {:websocket_protocol_error, :bad_frame}
  end

  test "reconnect_opts_from_state/1 omits nil and disabled heartbeat config" do
    handler = fn _msg -> :ok end

    opts =
      CallFacade.reconnect_opts_from_state(%{
        handler: handler,
        heartbeat_config: :disabled,
        on_connect: nil,
        on_disconnect: fn _pid -> :ok end,
        reconnector: nil
      })

    assert opts[:handler] == handler
    assert is_function(opts[:on_disconnect], 1)
    refute Keyword.has_key?(opts, :heartbeat_config)
    refute Keyword.has_key?(opts, :on_connect)
    refute Keyword.has_key?(opts, :reconnector)
  end

  test "reconnect_with/3 uses the supplied connect function when no reconnector is set" do
    assert {:ok, {"ws://localhost", []}} =
             CallFacade.reconnect_with("ws://localhost", [], fn target, opts -> {:ok, {target, opts}} end)
  end

  test "reconnect_with/3 prefers a 2-arity reconnector over connect_fun" do
    reconnector = fn target, opts -> {:ok, {:via_reconnector, target, opts}} end

    assert {:ok, {:via_reconnector, :target, [foo: 1]}} =
             CallFacade.reconnect_with(:target, [reconnector: reconnector, foo: 1], fn _, _ -> flunk("connect_fun") end)
  end

  test "reconnect_with/3 returns missing_config when the target is nil" do
    assert CallFacade.reconnect_with(nil, [], fn _, _ -> flunk("connect_fun") end) ==
             {:error, {:not_connected, :missing_config}}
  end

  test "reconnect_target/1 falls back to struct fields when the server is down" do
    {:ok, pid} = Agent.start_link(fn -> :ok end)
    :ok = Agent.stop(pid)
    config = %Config{url: "ws://localhost/ws"}

    assert {^config, [debug: true]} =
             CallFacade.reconnect_target(%{
               server_pid: pid,
               config: config,
               url: "ws://localhost/other",
               reconnect_opts: [debug: true]
             })
  end

  test "reconnect_target/1 uses config or url when no server pid is present" do
    config = %Config{url: "ws://localhost/ws"}
    assert {^config, []} = CallFacade.reconnect_target(%{config: config, url: "ws://localhost/other", reconnect_opts: []})

    assert {"ws://localhost/fallback", [a: 1]} =
             CallFacade.reconnect_target(%{config: nil, url: "ws://localhost/fallback", reconnect_opts: [a: 1]})
  end

  test "safe_call/3 returns the fallback when the server process is gone" do
    {:ok, pid} = Agent.start_link(fn -> :ok end)
    :ok = Agent.stop(pid)
    assert CallFacade.safe_call(pid, :get_state, :disconnected) == :disconnected
  end

  test "Client.build_client_struct/2 still copies reconnect opts via CallFacade" do
    handler = fn _msg -> :ok end
    config = %Config{url: "ws://localhost/ws"}

    client =
      Client.build_client_struct(
        %{
          gun_pid: self(),
          stream_ref: make_ref(),
          state: :connected,
          url: config.url,
          monitor_ref: make_ref(),
          config: config,
          handler: handler,
          heartbeat_config: %{type: :ping_pong, interval: 15_000},
          on_connect: nil,
          on_disconnect: nil,
          reconnector: nil
        },
        self()
      )

    assert client.reconnect_opts[:handler] == handler
    assert client.reconnect_opts[:heartbeat_config] == %{type: :ping_pong, interval: 15_000}
  end
end
