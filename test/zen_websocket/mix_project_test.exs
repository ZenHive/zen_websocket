defmodule ZenWebsocket.MixProjectTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.ZenWebsocket.Usage

  test "security alias honors sobelow skips" do
    aliases = Keyword.fetch!(ZenWebsocket.MixProject.project(), :aliases)

    assert Keyword.fetch!(aliases, :security) == ["sobelow --exit --skip --config"]
  end

  test "package retains example modules and consumer mix tasks" do
    package = Keyword.fetch!(ZenWebsocket.MixProject.project(), :package)

    assert "lib" in Keyword.fetch!(package, :files)
    refute Keyword.has_key?(package, :exclude_patterns)
  end

  test "usage task exports only requested sections" do
    output =
      capture_io(fn ->
        Usage.run(["--sections", "core-principles"])
      end)

    assert output =~ "# ZenWebsocket Usage Rules"
    assert output =~ "## Core Principles"
    refute output =~ "## Quick Start Pattern"
  end

  test "usage task rejects a section name that matches no document heading" do
    # Previously an unrecognized name was silently filtered out, so a typo (or a
    # heading that had been renamed) produced a quietly empty export.
    assert_raise Mix.Error, ~r/Unknown section\(s\): quick_start\n/, fn ->
      Usage.run(["--sections", "quick_start"])
    end
  end

  test "selectable sections are derived from USAGE_RULES.md, not a hand-maintained list" do
    headings =
      "USAGE_RULES.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "## "))
      |> Enum.map(&(&1 |> String.replace("## ", "") |> String.downcase() |> String.replace(" ", "_")))

    # Sections added after the old hardcoded list was written must be selectable.
    assert "session_recording" in headings

    output = capture_io(fn -> Usage.run(["--sections", "session_recording"]) end)
    assert output =~ "## Session Recording"
    refute output =~ "## Core Principles"
  end

  test "coverage ignore_modules lists an atom for every lib module matching a Mix ignore regex" do
    ignore = coverage_ignore_modules()
    regexes = ignore_regexes(ignore)
    atoms = MapSet.new(Enum.filter(ignore, &is_atom/1))

    missing =
      lib_app_modules()
      |> Enum.filter(&ignored_by_regex?(&1, regexes))
      |> Enum.reject(&MapSet.member?(atoms, &1))

    assert missing == [],
           "add these atoms to test_coverage ignore_modules so mix test.json --cover excludes them: #{inspect(missing)}"
  end

  test "coverage ignore_modules atoms all match a Mix ignore regex" do
    ignore = coverage_ignore_modules()
    regexes = ignore_regexes(ignore)

    extras =
      ignore
      |> Enum.filter(&is_atom/1)
      |> Enum.reject(&ignored_by_regex?(&1, regexes))

    assert extras == [],
           "ignore_modules atoms must match a Mix regex so core modules stay measured: #{inspect(extras)}"
  end

  test "coverage ignore_modules keeps Mix regexes and matching atoms" do
    ignore = coverage_ignore_modules()
    sources = for %Regex{} = re <- ignore, do: Regex.source(re)

    assert "^ZenWebsocket\\.Test\\.Support\\." in sources
    assert "^ZenWebsocket\\.Examples\\." in sources
    assert "^Mix\\.Tasks\\." in sources
    assert Usage in ignore
    assert ZenWebsocket.Examples.DeribitAdapter in ignore
  end

  test "precommit aliases share the measured core-only cover threshold" do
    aliases = Keyword.fetch!(ZenWebsocket.MixProject.project(), :aliases)
    precommit = cover_threshold(aliases, :precommit)
    full = cover_threshold(aliases, :"precommit.full")

    assert precommit == 90
    assert full == precommit
  end

  # Before (origin/main at task start): check.dispatch -> precommit.full;
  # ci -> precommit.full; agents.check / deps.audit.gated skipped via host_script
  # when ~/_DATA/code/{claude-marketplace,onchain-stack} were absent.
  # After: check.dispatch is format+compile; ci still -> precommit.full with
  # every previous analyzer plus in-repo freshness scripts (no skip).
  describe "alias graph (dispatch vs full QA)" do
    test "check.dispatch is format and compile only" do
      aliases = mix_aliases()

      assert Keyword.fetch!(aliases, :"check.dispatch") == [
               "format --check-formatted",
               "compile --warnings-as-errors"
             ]
    end

    test "check.dispatch does not run full-QA analyzers or the suite" do
      joined = mix_aliases() |> Keyword.fetch!(:"check.dispatch") |> Enum.join(" ")

      for needle <- ~w(credo doctor ex_dna reach sobelow cover dialyzer test.json deps.audit agents.check precommit.full) do
        refute joined =~ needle
      end
    end

    test "ci keeps the full QA entry point and does not go through check.dispatch" do
      aliases = mix_aliases()

      assert Keyword.fetch!(aliases, :ci) == ["precommit.full"]
      refute "check.dispatch" in Keyword.fetch!(aliases, :"precommit.full")
    end

    test "precommit.full retains every analyzer removed from dispatch" do
      full = mix_aliases() |> Keyword.fetch!(:"precommit.full") |> Enum.join(" ")

      assert full =~ "compile --warnings-as-errors"
      assert full =~ "format --check-formatted"
      assert full =~ "credo --strict"
      assert full =~ "doctor --raise"
      assert full =~ "ex_dna --max-clones 0"
      assert full =~ "reach.check --arch --smells"
      assert full =~ "sobelow --skip"
      assert full =~ "deps.audit.gated"
      assert full =~ "test.json"
      assert full =~ "--cover-threshold 90"
      assert full =~ "dialyzer"
      assert full =~ "agents.check"
    end

    test "deps.audit.gated proves freshness before the advisory scan" do
      gated = Keyword.fetch!(mix_aliases(), :"deps.audit.gated")

      assert match?([fun, "deps.audit --ignore-file .mix_audit_ignore"] when is_function(fun, 1), gated)
    end

    test "freshness gates use in-repo scripts and have no host-path skip" do
      source = File.read!("mix.exs")

      refute source =~ "[skip]"
      refute source =~ "_DATA/code"
      refute source =~ "host_script"
      refute source =~ "developer-host script unavailable"
      assert source =~ "bin/sync-agents-md.sh"
      assert source =~ "bin/advisory-freshness.sh"

      for name <- ["bin/sync-agents-md.sh", "bin/advisory-freshness.sh"] do
        path = Path.expand(name)
        assert File.regular?(path), "#{name} must be a tracked in-repo script"
        assert executable?(path), "#{name} must be executable"
      end
    end

    test "in-repo AGENTS.md check proves freshness without a marketplace host path" do
      {output, status} =
        System.cmd(Path.expand("bin/sync-agents-md.sh"), ["--check"], stderr_to_stdout: true)

      assert status == 0, output
      assert output =~ "OK:"
      refute output =~ "[skip]"
    end
  end

  defp mix_aliases, do: Keyword.fetch!(ZenWebsocket.MixProject.project(), :aliases)

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _error -> false
    end
  end

  defp coverage_ignore_modules do
    project = ZenWebsocket.MixProject.project()
    Keyword.fetch!(Keyword.fetch!(project, :test_coverage), :ignore_modules)
  end

  defp ignore_regexes(ignore), do: for(%Regex{} = re <- ignore, do: re)

  defp ignored_by_regex?(mod, regexes) do
    name = inspect(mod)
    Enum.any?(regexes, &Regex.match?(&1, name))
  end

  defp lib_app_modules do
    {:ok, modules} = :application.get_key(:zen_websocket, :modules)
    cwd = File.cwd!()

    Enum.filter(modules, fn mod ->
      source = compile_source(mod)
      relative = source && Path.relative_to(source, cwd)
      is_binary(relative) and String.starts_with?(relative, "lib/")
    end)
  end

  defp compile_source(mod) do
    case mod.module_info(:compile)[:source] do
      source when is_list(source) -> List.to_string(source)
      source when is_binary(source) -> source
      _ -> nil
    end
  end

  defp cover_threshold(aliases, key) do
    aliases
    |> Keyword.fetch!(key)
    |> Enum.find_value(fn
      "cmd env MIX_ENV=test mix test.json" <> rest ->
        case Regex.run(~r/--cover-threshold (\d+)/, rest) do
          [_, digits] -> String.to_integer(digits)
          _ -> nil
        end

      _ ->
        nil
    end)
  end
end
