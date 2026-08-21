defmodule ZenWebsocket.Client.RetryTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client.Connection
  alias ZenWebsocket.Client.Retry
  alias ZenWebsocket.Config

  test "normalize_error/1 unwraps nested error and gun tuples" do
    assert Retry.normalize_error({:error, :timeout}) == :timeout
    assert Retry.normalize_error({:shutdown, :closed}) == :closed
    assert Retry.normalize_error({:gun_error, self(), make_ref(), :gone}) == :gone
    assert Retry.normalize_error({:gun_error, self(), :nxdomain}) == :nxdomain
    assert Retry.normalize_error(:timeout) == :timeout
  end

  test "retry_now?/2 is false when reconnect is disabled or retries are exhausted" do
    state = retry_state(reconnect_on_error: false, retry_count: 0, max_retries: 3)
    refute Retry.retry_now?(state, :timeout)

    exhausted = retry_state(reconnect_on_error: true, retry_count: 3, max_retries: 3)
    refute Retry.retry_now?(exhausted, :timeout)
  end

  test "retry_now?/2 is true for recoverable errors under the retry budget" do
    state = retry_state(reconnect_on_error: true, retry_count: 0, max_retries: 3)
    assert Retry.retry_now?(state, :timeout)
    refute Retry.retry_now?(state, :unauthorized)
  end

  test "continue_failed/2 stops and replies when reconnect is disabled" do
    from = {self(), make_ref()}
    config = %Config{url: "ws://localhost/ws", reconnect_on_error: false, retry_count: 3}
    state = config |> Connection.initial_state([]) |> Map.put(:awaiting_connection, from)

    assert {:stop, :timeout, new_state} = Retry.continue_failed(state, :timeout)
    assert new_state.state == :disconnected
    refute Map.has_key?(new_state, :awaiting_connection)
    assert_receive {ref, {:error, :timeout}} when ref == elem(from, 1)
  end

  test "continue_failed/2 schedules a retry when reconnect is enabled" do
    config = %Config{url: "ws://localhost/ws", reconnect_on_error: true, retry_count: 3, retry_delay: 1}
    state = Connection.initial_state(config, [])

    assert {:noreply, new_state} = Retry.continue_failed(state, :timeout)
    assert new_state.retry_count == 1
    assert_receive :retry_reconnect, 200
  end

  defp retry_state(opts) do
    config = %Config{
      url: "ws://localhost/ws",
      reconnect_on_error: Keyword.fetch!(opts, :reconnect_on_error),
      retry_count: Keyword.fetch!(opts, :max_retries)
    }

    %{config: config, retry_count: Keyword.fetch!(opts, :retry_count)}
  end
end
