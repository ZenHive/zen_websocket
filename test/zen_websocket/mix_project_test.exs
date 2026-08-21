defmodule ZenWebsocket.MixProjectTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.ZenWebsocket.Usage

  test "security alias honors sobelow skips" do
    aliases = Keyword.fetch!(ZenWebsocket.MixProject.project(), :aliases)

    assert Keyword.fetch!(aliases, :security) == ["sobelow --exit --skip --config"]
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
