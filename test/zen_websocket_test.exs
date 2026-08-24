defmodule ZenWebsocketTest do
  use ExUnit.Case

  alias ZenWebsocket.JsonRpc
  alias ZenWebsocket.Recorder

  doctest ZenWebsocket
  doctest ZenWebsocket.ErrorHandler
  doctest JsonRpc
  doctest ZenWebsocket.LatencyStats
  doctest Recorder
  doctest ZenWebsocket.Reconnection
end
