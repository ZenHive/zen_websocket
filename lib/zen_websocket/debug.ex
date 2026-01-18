defmodule ZenWebsocket.Debug do
  @moduledoc """
  Conditional debug logging for ZenWebsocket.

  Provides debug logging that only outputs when `debug: true` is set in config.
  This keeps library output quiet by default while allowing verbose logging
  when troubleshooting connection issues.
  """

  alias ZenWebsocket.Config

  require Logger

  @doc """
  Log a debug message if debug mode is enabled in the config.

  Accepts either a Config struct directly or a state map containing a config key.

  ## Examples

      # With Config struct
      ZenWebsocket.Debug.log(config, "Connection established")

      # With state map containing config
      ZenWebsocket.Debug.log(state, "Message received")
  """
  @spec log(Config.t() | map(), String.t()) :: :ok
  def log(%Config{debug: true}, message), do: Logger.debug(message)
  def log(%{config: %{debug: true}}, message), do: Logger.debug(message)
  def log(_, _), do: :ok
end
