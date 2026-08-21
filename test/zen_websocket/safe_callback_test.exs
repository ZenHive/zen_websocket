defmodule ZenWebsocket.SafeCallbackTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenWebsocket.SafeCallback

  test "returns :ok without calling when the callback is nil" do
    assert SafeCallback.invoke(nil, self()) == :ok
  end

  test "invokes a 1-arity callback with the given pid" do
    parent = self()

    assert SafeCallback.invoke(fn pid -> send(parent, {:called, pid}) end, parent) == :ok
    assert_received {:called, ^parent}
  end

  test "swallows a raised callback and logs the error" do
    log =
      capture_log(fn ->
        assert SafeCallback.invoke(fn _pid -> raise "intentional error" end, self()) == :ok
      end)

    assert log =~ "Lifecycle callback error"
    assert log =~ "intentional error"
  end

  test "swallows a thrown callback and logs the error" do
    log =
      capture_log(fn ->
        assert SafeCallback.invoke(fn _pid -> throw(:intentional) end, self()) == :ok
      end)

    assert log =~ "Lifecycle callback error"
    assert log =~ ":intentional"
  end

  test "swallows an exited callback and logs the error" do
    log =
      capture_log(fn ->
        assert SafeCallback.invoke(fn _pid -> exit(:intentional) end, self()) == :ok
      end)

    assert log =~ "Lifecycle callback error"
    assert log =~ ":intentional"
  end
end
