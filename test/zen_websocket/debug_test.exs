defmodule ZenWebsocket.DebugTest do
  # Deliberately synchronous. `capture_log/1` intercepts the GLOBAL :logger for
  # the duration of the call, not just the calling process, so any other async
  # test logging in that window lands in this capture. The `log == ""` assertion
  # below then fails on output `Debug.log/2` never produced — observed under
  # `--max-cases 32` with a `Batch subscribe failed for req_3: :not_connected`
  # warning from BatchSubscriptionManagerTest. ExUnit guarantees sync tests run
  # after all async ones, which closes the window. Two trivial tests, so the
  # serialisation costs nothing.
  #
  # The weaker alternative — asserting `refute log =~ "should not appear"` —
  # would also stop the flake but stops testing the actual property: that a
  # disabled `Debug.log/2` emits NOTHING, not merely nothing recognisable.
  use ExUnit.Case, async: false

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
