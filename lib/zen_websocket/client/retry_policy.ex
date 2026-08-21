defmodule ZenWebsocket.Client.RetryPolicy do
  @moduledoc """
  Pure retry eligibility and error normalization for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.Reconnection

  @doc """
  True when the current error should open a new Gun attempt immediately or later.
  """
  @spec retry_now?(map(), term()) :: boolean()
  def retry_now?(state, reason) do
    state.config.reconnect_on_error and
      Reconnection.should_reconnect?(reason) and
      not Reconnection.max_retries_exceeded?(state.retry_count, state.config.retry_count)
  end

  @doc """
  Unwraps nested Gun/shutdown error tuples to the inner reason.
  """
  @spec normalize_error(term()) :: term()
  def normalize_error({:error, reason}), do: normalize_error(reason)
  def normalize_error({:shutdown, reason}), do: normalize_error(reason)
  def normalize_error({:gun_error, _pid, _stream, reason}), do: reason
  def normalize_error({:gun_error, _pid, reason}), do: reason
  def normalize_error(reason), do: reason
end
