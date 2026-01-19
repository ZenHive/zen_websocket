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

  Always pass the Config struct directly - this is the canonical holder of the debug flag.

  ## Examples

      ZenWebsocket.Debug.log(config, "Connection established")
      ZenWebsocket.Debug.log(state.config, "Message received")
  """
  @spec log(Config.t(), String.t()) :: :ok
  def log(%Config{debug: true}, message), do: Logger.debug(message)
  def log(%Config{debug: false}, _message), do: :ok
end
