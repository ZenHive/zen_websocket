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
