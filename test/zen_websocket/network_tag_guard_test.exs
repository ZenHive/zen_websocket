defmodule ZenWebsocket.NetworkTagGuardTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Test.Support.NetworkTagGuard

  @fixture Path.expand("../fixtures/mistagged_network_suite.exs", __DIR__)

  test "every suite under test/ carries tags that match the sockets it opens" do
    assert NetworkTagGuard.scan(Path.expand("..", __DIR__)) == []
  end

  test "a deliberately mistagged fixture reds on internet, mock-server, and unpaired tags" do
    messages = NetworkTagGuard.check_source(@fixture, File.read!(@fixture))

    assert Enum.any?(messages, &(&1 =~ "internet URL without :external_network"))
    assert Enum.any?(messages, &(&1 =~ "MockWebSockServer without :local_network"))
    assert Enum.any?(messages, &(&1 =~ "network tag without :integration"))
    assert Enum.any?(messages, &(&1 =~ "module setup starts MockWebSockServer"))
  end
end
