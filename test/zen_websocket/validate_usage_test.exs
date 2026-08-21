defmodule ZenWebsocket.ValidateUsageTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.ZenWebsocket.ValidateUsage

  @public_client_calls """
  ZenWebsocket.Client.connect(url)
  ZenWebsocket.Client.send_message(client, msg)
  ZenWebsocket.Client.subscribe(client, channels)
  ZenWebsocket.Client.get_state(client)
  ZenWebsocket.Client.close(client)
  ZenWebsocket.Client.get_heartbeat_health(client)
  ZenWebsocket.Client.get_state_metrics(client)
  ZenWebsocket.Client.get_latency_stats(client)
  ZenWebsocket.Client.reconnect(client)
  ZenWebsocket.Client.reconnect_opts_from_state(state)
  """

  test "allows every public Client function" do
    path = write_tmp(@public_client_calls)
    issues = json_issues(run_task(["--format", "json", path]))

    assert issues == []
  end

  test "flags unknown Client functions as invalid_api" do
    # Concatenate so this test file itself is not a false :invalid_api hit
    # when validate_usage scans test/**/*.exs.
    path = write_tmp("ZenWebsocket.Client." <> "not_a_function(client)\n")
    issues = json_issues(run_task(["--format", "json", path]))

    assert Enum.any?(issues, fn issue -> issue["type"] == "invalid_api" end)
  end

  test "library Client calls are not invalid_api" do
    issues = json_issues(run_task(["--format", "json", "lib", "test"]))
    invalid = Enum.filter(issues, &(&1["type"] == "invalid_api"))

    assert invalid == [], inspect(invalid)
  end

  test "allows Client.t typespec references" do
    path = write_tmp("@spec start_client(term()) :: {:ok, ZenWebsocket.Client.t()}\n")
    issues = json_issues(run_task(["--format", "json", path]))

    assert issues == []
  end

  test "UTF-8 before a legitimate call is not invalid_api" do
    path = write_tmp("# em-dash — then a call\nZenWebsocket.Client.send_message(client, msg)\n")
    issues = json_issues(run_task(["--format", "json", path]))

    assert issues == []
  end

  test "--fix does not rewrite files" do
    content = """
    ZenWebsocket.Client.reconnect(client)
    WebsockexAdapter.foo()
    """

    path = write_tmp(content)
    run_task(["--fix", "--format", "json", path])

    assert File.read!(path) == content
  end

  defp run_task(args) do
    Mix.Task.reenable(ValidateUsage)
    capture_io(fn -> ValidateUsage.run(args) end)
  end

  defp write_tmp(content) do
    path = Path.join(System.tmp_dir!(), "zen_ws_validate_#{System.unique_integer([:positive])}.ex")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp json_issues(output) do
    case :binary.match(output, "[") do
      {start, _len} ->
        output
        |> binary_part(start, byte_size(output) - start)
        |> Jason.decode!()

      :nomatch ->
        []
    end
  end
end
