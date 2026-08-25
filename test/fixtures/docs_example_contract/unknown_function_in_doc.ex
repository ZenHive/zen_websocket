# Fixture: a public @doc example that names a function the library does not export.
# The contract must fail this checkable fence and name the file, fence line, and symbol.

defmodule ZenWebsocket.Fixtures.UnknownFunctionInDoc do
  @moduledoc false

  @doc """
  Copy-pasteable example that names a function the library does not export.

  ```elixir
  ZenWebsocket.Config.not_a_real_function()
  ```
  """
  def example, do: :ok
end
