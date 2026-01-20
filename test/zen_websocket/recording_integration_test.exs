defmodule ZenWebsocket.RecordingIntegrationTest do
  use ExUnit.Case, async: false

  alias ZenWebsocket.Recorder
  alias ZenWebsocket.Testing

  @moduletag :integration

  setup do
    path = Path.join(System.tmp_dir!(), "test_session_#{System.unique_integer()}.jsonl")

    on_exit(fn ->
      File.rm(path)
    end)

    {:ok, path: path}
  end

  describe "Client with recording enabled" do
    test "records outbound and inbound messages", %{path: path} do
      {:ok, server} = Testing.start_mock_server()

      # Connect with recording enabled
      {:ok, client} = ZenWebsocket.Client.connect(server.url, record_to: path)

      # Send some messages
      ZenWebsocket.Client.send_message(client, ~s({"type": "ping"}))
      ZenWebsocket.Client.send_message(client, ~s({"type": "hello"}))

      # Wait for responses
      Process.sleep(100)

      # Close client to flush recording
      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)

      # Verify recording
      assert {:ok, meta} = Recorder.metadata(path)
      assert meta.count >= 2
      assert meta.outbound >= 2

      # Replay and verify content
      entries = collect_entries(path)
      outbound = Enum.filter(entries, &(&1.dir == :out))

      assert length(outbound) >= 2
      assert Enum.any?(outbound, fn e -> String.contains?(e.data, "ping") end)
      assert Enum.any?(outbound, fn e -> String.contains?(e.data, "hello") end)
    end

    test "records inbound frames from server", %{path: path} do
      {:ok, server} = Testing.start_mock_server()

      {:ok, client} = ZenWebsocket.Client.connect(server.url, record_to: path)

      # Inject message from server
      Testing.inject_message(server, ~s({"type": "notification", "data": "test"}))

      # Wait for message to be received and recorded
      Process.sleep(100)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)

      # Verify inbound was recorded
      entries = collect_entries(path)
      inbound = Enum.filter(entries, &(&1.dir == :in))

      assert inbound != []
      assert Enum.any?(inbound, fn e -> String.contains?(e.data, "notification") end)
    end

    test "recording disabled by default" do
      {:ok, server} = Testing.start_mock_server()

      # Connect without record_to option
      {:ok, client} = ZenWebsocket.Client.connect(server.url)

      ZenWebsocket.Client.send_message(client, "test")
      Process.sleep(50)

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)

      # No recording file should be created
      # (This test verifies no errors occur when recording is disabled)
    end

    test "handles recording errors gracefully" do
      {:ok, server} = Testing.start_mock_server()

      # Try to record to invalid path - should still connect
      {:ok, client} = ZenWebsocket.Client.connect(server.url, record_to: "/nonexistent/dir/file.jsonl")

      # Client should still work even if recording failed
      assert ZenWebsocket.Client.get_state(client) == :connected
      :ok = ZenWebsocket.Client.send_message(client, "test")

      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)
    end
  end

  describe "replay recorded session" do
    test "replays session with correct timing info", %{path: path} do
      {:ok, server} = Testing.start_mock_server()

      {:ok, client} = ZenWebsocket.Client.connect(server.url, record_to: path)

      # Send messages with small delays
      ZenWebsocket.Client.send_message(client, "message 1")
      Process.sleep(50)
      ZenWebsocket.Client.send_message(client, "message 2")
      Process.sleep(50)
      ZenWebsocket.Client.send_message(client, "message 3")

      Process.sleep(100)
      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)

      # Verify replay works
      entries = collect_entries(path)

      # Should have recorded entries
      assert length(entries) >= 3

      # Entries should have timestamps
      assert Enum.all?(entries, fn e -> e.ts != nil end)

      # Outbound entries should be in order
      outbound = Enum.filter(entries, &(&1.dir == :out))
      timestamps = Enum.map(outbound, & &1.ts)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end
  end

  describe "metadata of recorded session" do
    test "returns accurate statistics", %{path: path} do
      {:ok, server} = Testing.start_mock_server()

      {:ok, client} = ZenWebsocket.Client.connect(server.url, record_to: path)

      # Generate some traffic
      for i <- 1..5 do
        ZenWebsocket.Client.send_message(client, "outbound #{i}")
        Testing.inject_message(server, "inbound #{i}")
      end

      Process.sleep(200)
      ZenWebsocket.Client.close(client)
      Testing.stop_server(server)

      # Check metadata
      {:ok, meta} = Recorder.metadata(path)

      assert meta.count >= 10
      assert meta.outbound >= 5
      assert meta.inbound >= 5
      assert meta.duration_ms >= 0
      assert meta.first_ts
      assert meta.last_ts
    end
  end

  # Helper to collect all entries from a recording
  defp collect_entries(path) do
    Recorder.replay(path, fn entry ->
      send(self(), {:entry, entry})
    end)

    collect_messages([])
  end

  defp collect_messages(acc) do
    receive do
      {:entry, entry} -> collect_messages([entry | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
