defmodule ZenWebsocket.Examples.DeribitGenServerAdapterTest do
  @moduledoc """
  Restore-path regressions for the supervised Deribit adapter.
  """
  use ExUnit.Case, async: false

  alias ZenWebsocket.Examples.DeribitGenServerAdapter
  alias ZenWebsocket.Test.Support.MockWebSockServer

  @moduletag :integration
  @moduletag :local_network

  @channel "book.BTC-PERPETUAL.raw"

  setup do
    test_pid = self()
    {:ok, server, port} = MockWebSockServer.start_link()

    MockWebSockServer.set_handler(server, fn frame ->
      send(test_pid, {:server_frame, frame})
      handle_rpc(frame, :ok)
    end)

    name = :"deribit_gs_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      DeribitGenServerAdapter.start_link(
        name: name,
        url: "ws://localhost:#{port}/ws",
        client_id: "id",
        client_secret: "secret"
      )

    wait_connected(pid)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      MockWebSockServer.stop(server)
    end)

    {:ok, pid: pid, server: server}
  end

  test "empty subscriptions do not enter restore_subs", %{pid: pid} do
    flush_server_frames()
    send(pid, :restore_subs)
    {:ok, state} = DeribitGenServerAdapter.get_state(pid)

    assert MapSet.size(state.subscriptions) == 0
    refute_receive {:server_frame, {:text, _msg}}, 100
  end

  test "failed restore keeps tracked subscriptions", %{pid: pid, server: server} do
    assert :ok = DeribitGenServerAdapter.subscribe(pid, [@channel])
    {:ok, subscribed} = DeribitGenServerAdapter.get_state(pid)
    assert MapSet.member?(subscribed.subscriptions, @channel)

    MockWebSockServer.set_handler(server, fn {:text, msg} ->
      decoded = Jason.decode!(msg)

      {:reply,
       {:text,
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => decoded["id"],
          "error" => %{"code" => 13_009, "message" => "unauthorized"}
        })}}
    end)

    send(pid, :restore_subs)
    {:ok, state} = DeribitGenServerAdapter.get_state(pid)

    assert MapSet.member?(state.subscriptions, @channel)
    assert MapSet.size(state.subscriptions) == 1
  end

  defp wait_connected(pid, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_connected_until(pid, deadline)
  end

  defp wait_connected_until(pid, deadline) do
    {:ok, state} = DeribitGenServerAdapter.get_state(pid)

    cond do
      state.client != nil ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("adapter did not connect")

      true ->
        Process.sleep(20)
        wait_connected_until(pid, deadline)
    end
  end

  defp handle_rpc({:text, msg}, :ok) do
    decoded = Jason.decode!(msg)
    result = rpc_result(decoded)

    {:reply,
     {:text,
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => decoded["id"],
        "result" => result
      })}}
  end

  defp handle_rpc(_frame, :ok), do: :ok

  defp rpc_result(%{"method" => "public/subscribe", "params" => %{"channels" => channels}}), do: channels
  defp rpc_result(_decoded), do: %{}

  defp flush_server_frames do
    receive do
      {:server_frame, _} -> flush_server_frames()
    after
      0 -> :ok
    end
  end
end
