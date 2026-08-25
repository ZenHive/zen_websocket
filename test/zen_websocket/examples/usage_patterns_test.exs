defmodule ZenWebsocket.Examples.UsagePatternsTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client
  alias ZenWebsocket.Examples.UsagePatterns

  test "supervised client spec installs a callable frame handler" do
    assert {Client, opts} = UsagePatterns.supervised_client_spec()
    assert handler = Keyword.fetch!(opts, :handler)
    assert handler.(%{"channel" => "ticker"}) == :ok
  end
end
