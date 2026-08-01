defmodule ZenWebsocket.DebugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ZenWebsocket.Config
  alias ZenWebsocket.Debug

  describe "log/2" do
    test "logs the message when debug is enabled" do
      config = %Config{url: "wss://test.com", debug: true}

      log =
        capture_log(fn ->
          assert :ok = Debug.log(config, "hello from debug")
        end)

      assert log =~ "hello from debug"
    end

    test "is a silent no-op when debug is disabled" do
      config = %Config{url: "wss://test.com", debug: false}

      log =
        capture_log(fn ->
          assert :ok = Debug.log(config, "should not appear")
        end)

      assert log == ""
    end
  end
end
