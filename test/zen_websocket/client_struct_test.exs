defmodule ZenWebsocket.ClientStructTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.Config

  defp client_state(overrides) do
    Map.merge(
      %{
        gun_pid: self(),
        stream_ref: make_ref(),
        state: :connected,
        url: "wss://example.com/ws",
        monitor_ref: make_ref(),
        config: %Config{url: "wss://example.com/ws"},
        handler: fn _msg -> :ok end,
        heartbeat_config: :disabled,
        on_connect: nil,
        on_disconnect: nil,
        reconnector: nil
      },
      overrides
    )
  end

  describe "build_client_struct/2" do
    test "copies connection fields onto the returned Client struct" do
      server_pid = self()
      stream_ref = make_ref()
      monitor_ref = make_ref()
      config = %Config{url: "wss://example.com/ws"}

      client =
        Client.build_client_struct(
          client_state(%{
            gun_pid: server_pid,
            stream_ref: stream_ref,
            monitor_ref: monitor_ref,
            config: config
          }),
          server_pid
        )

      assert %Client{
               gun_pid: ^server_pid,
               stream_ref: ^stream_ref,
               state: :connected,
               url: "wss://example.com/ws",
               monitor_ref: ^monitor_ref,
               server_pid: ^server_pid,
               config: ^config
             } = client
    end

    test "captures reconnect opts from live handler and heartbeat config" do
      handler = fn _msg -> :ok end
      on_connect = fn _pid -> :ok end
      heartbeat = %{type: :ping_pong, interval: 15_000}

      client =
        Client.build_client_struct(
          client_state(%{
            handler: handler,
            heartbeat_config: heartbeat,
            on_connect: on_connect
          }),
          self()
        )

      assert client.reconnect_opts[:handler] == handler
      assert client.reconnect_opts[:heartbeat_config] == heartbeat
      assert client.reconnect_opts[:on_connect] == on_connect
      refute Keyword.has_key?(client.reconnect_opts, :on_disconnect)
      refute Keyword.has_key?(client.reconnect_opts, :reconnector)
    end

    test "omits disabled heartbeat config from reconnect opts" do
      client = Client.build_client_struct(client_state(%{heartbeat_config: :disabled}), self())

      refute Keyword.has_key?(client.reconnect_opts, :heartbeat_config)
    end
  end

  test "reconnect_opts_from_state/1 is not part of the public Client API" do
    refute {:reconnect_opts_from_state, 1} in Client.__info__(:functions)
    assert {:build_client_struct, 2} in Client.__info__(:functions)
  end
end
