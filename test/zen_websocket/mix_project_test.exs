defmodule ZenWebsocket.MixProjectTest do
  use ExUnit.Case, async: true

  test "security alias honors sobelow skips" do
    aliases = Keyword.fetch!(ZenWebsocket.MixProject.project(), :aliases)

    assert Keyword.fetch!(aliases, :security) == ["sobelow --exit --skip --config"]
  end
end
