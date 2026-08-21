defmodule ZenWebsocket.Examples.DeribitAdapterAuthTest do
  @moduledoc """
  Failed-auth regression: a JSON-RPC error body must not match `{:ok, adapter}`.
  """
  use ExUnit.Case, async: false

  alias ZenWebsocket.Examples.DeribitAdapter
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @moduletag :integration
  @moduletag :local_network

  @auth_error %{"code" => 13_009, "message" => "unauthorized"}

  setup do
    {:ok, server, port} = MockWebSockServer.start_link()

    MockWebSockServer.set_handler(server, fn
      {:text, msg} ->
        decoded = Jason.decode!(msg)

        {:reply,
         {:text,
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "id" => decoded["id"],
            "error" => @auth_error
          })}}
    end)

    on_exit(fn -> MockWebSockServer.stop(server) end)

    {:ok, mock_url: "ws://localhost:#{port}/ws"}
  end

  test "authenticate/1 returns {:error, reason} on a JSON-RPC error body", %{mock_url: mock_url} do
    {:ok, adapter} =
      DeribitAdapter.connect(
        url: mock_url,
        client_id: "bad_id",
        client_secret: "bad_secret"
      )

    result = DeribitAdapter.authenticate(adapter)

    refute match?({:ok, _adapter}, result)
    assert {:error, %{"code" => 13_009, "message" => "unauthorized"}} = result
  end
end
