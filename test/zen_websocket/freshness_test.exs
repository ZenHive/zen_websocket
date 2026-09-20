defmodule ZenWebsocket.FreshnessTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  setup do
    home = Path.join(@root, ".harness/freshness-#{System.unique_integer([:positive])}")
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(home) end)
    {:ok, home: home}
  end

  test "AGENTS freshness works with no host includes and detects project drift", %{home: home} do
    for file <- ~w(CLAUDE.md AGENTS.md mix.exs) do
      File.cp!(Path.join(@root, file), Path.join(home, file))
    end

    assert {output, 0} = agents_check(home)
    assert output =~ "is up to date"

    File.write!(Path.join(home, "CLAUDE.md"), "\nChanged project instructions\n", [:append])
    assert {output, 1} = agents_check(home)
    assert output =~ "STALE:"
  end

  test "AGENTS freshness detects canonical import drift and missing imports", %{home: home} do
    for file <- ~w(CLAUDE.md AGENTS.md mix.exs) do
      File.cp!(Path.join(@root, file), Path.join(home, file))
    end

    includes = Path.join(home, ".claude/includes")
    File.mkdir_p!(includes)

    File.cp!(
      Path.join(@root, "priv/agent-includes/verification-policy.md"),
      Path.join(includes, "verification-policy.md")
    )

    File.write!(Path.join(includes, "verification-policy.md"), "\nChanged canonical policy\n", [:append])
    assert {output, 1} = agents_check(home)
    assert output =~ "STALE:"

    File.write!(Path.join(home, "CLAUDE.md"), "\n@~/.claude/includes/missing.md\n", [:append])
    assert {output, 1} = agents_check(home)
    assert output =~ "cannot read @-import"
  end

  @tag :integration
  @tag :external_network
  @tag timeout: 120_000
  test "gated audit proves a cold live mirror and rejects dirty or offline mirrors", %{home: home} do
    assert {output, 0} = audit(home)
    assert output =~ "advisory-freshness: OK - at upstream tip"
    assert output =~ "No vulnerabilities found."

    mirror = Path.join(home, ".local/share/elixir-security-advisories-mirego")
    {files, 0} = System.cmd("git", ["-C", mirror, "ls-files"])
    tracked = files |> String.split("\n", trim: true) |> hd()
    path = Path.join(mirror, tracked)
    original = File.read!(path)
    File.write!(path, "\nchanged\n", [:append])
    assert {output, status} = audit(home)
    assert status != 0
    assert output =~ "modified tracked files"
    refute output =~ "No vulnerabilities found."
    File.write!(path, original)

    File.write!(
      Path.join(mirror, ".git/advisory-freshness-last-sync"),
      Integer.to_string(System.system_time(:second))
    )

    assert {output, status} =
             audit(home, [
               {"GIT_CONFIG_COUNT", "1"},
               {"GIT_CONFIG_KEY_0", "protocol.https.allow"},
               {"GIT_CONFIG_VALUE_0", "never"}
             ])

    assert status != 0
    assert output =~ "freshness was not proven in this invocation"
    refute output =~ "No vulnerabilities found."
  end

  defp agents_check(home) do
    System.cmd(Path.join(@root, "bin/sync-agents-md.sh"), ["--check"],
      cd: home,
      env: [{"HOME", home}],
      stderr_to_stdout: true
    )
  end

  defp audit(home, extra_env \\ []) do
    elixir_bin = :elixir |> :code.lib_dir() |> to_string() |> Path.join("../../bin") |> Path.expand()
    erl_bin = Path.join(to_string(:code.root_dir()), "bin")
    path = Enum.join([elixir_bin, erl_bin, System.fetch_env!("PATH")], ":")

    System.cmd(Path.join(elixir_bin, "mix"), ["deps.audit.gated"],
      cd: @root,
      env: [{"HOME", home}, {"PATH", path}, {"MIX_ENV", "dev"}, {"ERL_FLAGS", "+S 2:2"}] ++ extra_env,
      stderr_to_stdout: true
    )
  end
end
