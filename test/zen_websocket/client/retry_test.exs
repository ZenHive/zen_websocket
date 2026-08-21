defmodule ZenWebsocket.Client.RetryTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.Client.Connection, as: Connection
  alias ZenWebsocket.Client.Retry, as: Retry
  alias ZenWebsocket.Client.RetryPolicy, as: RetryPolicy
  alias ZenWebsocket.Client.TransportErrors, as: TransportErrors
  alias ZenWebsocket.Config

  test "normalize_error/1 unwraps nested error and gun tuples" do
    assert RetryPolicy.normalize_error({:error, :timeout}) == :timeout
    assert RetryPolicy.normalize_error({:shutdown, :closed}) == :closed
    assert RetryPolicy.normalize_error({:gun_error, self(), make_ref(), :gone}) == :gone
    assert RetryPolicy.normalize_error({:gun_error, self(), :nxdomain}) == :nxdomain
    assert RetryPolicy.normalize_error(:timeout) == :timeout
  end

  test "retry_now?/2 is false when reconnect is disabled or retries are exhausted" do
    state = retry_state(reconnect_on_error: false, retry_count: 0, max_retries: 3)
    refute RetryPolicy.retry_now?(state, :timeout)

    exhausted = retry_state(reconnect_on_error: true, retry_count: 3, max_retries: 3)
    refute RetryPolicy.retry_now?(exhausted, :timeout)
  end

  test "retry_now?/2 is true for recoverable errors under the retry budget" do
    state = retry_state(reconnect_on_error: true, retry_count: 0, max_retries: 3)
    assert RetryPolicy.retry_now?(state, :timeout)
    refute RetryPolicy.retry_now?(state, :unauthorized)
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

  test "transport process-down errors preserve their error tuple" do
    config = %Config{url: "ws://localhost/ws", reconnect_on_error: false}
    state = Connection.initial_state(config, [])

    assert {:stop, {:connection_down, :closed}, new_state} =
             TransportErrors.handle_process_down(state, self(), make_ref(), :closed)

    assert new_state.state == :disconnected
  end

  test "transport Gun errors preserve their normalized reason" do
    config = %Config{url: "ws://localhost/ws", reconnect_on_error: false}
    state = Connection.initial_state(config, [])

    assert {:stop, :closed, new_state} =
             TransportErrors.handle_gun_error(state, self(), make_ref(), :closed)

    assert new_state.state == :disconnected
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
