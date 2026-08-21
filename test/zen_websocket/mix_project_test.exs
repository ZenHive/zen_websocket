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
end
