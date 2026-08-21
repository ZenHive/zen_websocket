defmodule ZenWebsocket.NetworkTagGuardTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Test.Support.NetworkTagGuard

  @fixture Path.expand("../fixtures/mistagged_network_suite.fixture", __DIR__)

  test "every suite under test/ carries tags that match the sockets it opens" do
    assert NetworkTagGuard.scan(Path.expand("..", __DIR__)) == []
  end

  test "a deliberately mistagged fixture reds on internet, mock-server, and unpaired tags" do
    messages = NetworkTagGuard.check_source(@fixture, File.read!(@fixture))

    assert Enum.any?(messages, &(&1 =~ "internet URL without :external_network"))
    assert Enum.any?(messages, &(&1 =~ "MockWebSockServer without :local_network"))
    assert Enum.any?(messages, &(&1 =~ "network tag without :integration"))
    assert Enum.any?(messages, &(&1 =~ "MockWebSockServer selected by :external_network"))

    assert Enum.any?(messages, fn message ->
             message =~ "mistagged internet sibling" and
               message =~ "internet URL without :external_network"
           end)

    assert Enum.any?(messages, fn message ->
             message =~ "mistagged mock sibling" and
               message =~ "MockWebSockServer without :local_network"
           end)
  end
end
