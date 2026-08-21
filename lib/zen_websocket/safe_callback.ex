defmodule ZenWebsocket.SafeCallback do
  @moduledoc """
  Invokes user-provided lifecycle callbacks without letting them crash the caller.
  """

  require Logger

  @doc """
  Calls `fun.(pid)` when `fun` is a 1-arity function.

  Returns `:ok` when `fun` is nil, and also when the callback raises, throws, or exits.
  """
  @spec invoke((pid() -> any()) | nil, pid()) :: :ok
  def invoke(nil, _pid), do: :ok

  def invoke(fun, pid) when is_function(fun, 1) do
    fun.(pid)
    :ok
  catch
    _kind, error ->
      Logger.warning("Lifecycle callback error: #{inspect(error)}")
      :ok
  end
end
