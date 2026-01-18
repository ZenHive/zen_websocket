defmodule ZenWebsocket.Config do
  @moduledoc """
  Configuration struct for WebSocket connections.

  ## Options

  - `:url` - WebSocket URL (required, must be ws:// or wss://)
  - `:headers` - HTTP headers for the upgrade request (default: [])
  - `:timeout` - Connection timeout in milliseconds (default: 5000)
  - `:retry_count` - Maximum reconnection attempts (default: 3)
  - `:retry_delay` - Base delay for exponential backoff in ms (default: 1000)
  - `:heartbeat_interval` - Interval for heartbeat messages in ms (default: 30000)
  - `:max_backoff` - Maximum delay between reconnection attempts in ms (default: 30000)
  - `:reconnect_on_error` - Whether to auto-reconnect on connection errors (default: true)
  - `:restore_subscriptions` - Whether to restore subscriptions after reconnect (default: true)
  - `:request_timeout` - Timeout for correlated requests in ms (default: 30000)
  - `:debug` - Enable verbose debug logging (default: false)

  ## Examples

      # Basic configuration
      {:ok, config} = Config.new("wss://example.com")

      # Custom reconnection settings
      {:ok, config} = Config.new("wss://example.com",
        retry_count: 5,
        retry_delay: 2000,
        max_backoff: 60_000,
        reconnect_on_error: true
      )

      # Disable auto-reconnection
      {:ok, config} = Config.new("wss://example.com",
        reconnect_on_error: false
      )
  """

  defstruct [
    :url,
    headers: [],
    timeout: 5_000,
    retry_count: 3,
    retry_delay: 1_000,
    heartbeat_interval: 30_000,
    max_backoff: 30_000,
    reconnect_on_error: true,
    restore_subscriptions: true,
    request_timeout: 30_000,
    debug: false
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          headers: [{String.t(), String.t()}],
          timeout: pos_integer(),
          retry_count: non_neg_integer(),
          retry_delay: pos_integer(),
          heartbeat_interval: pos_integer(),
          max_backoff: pos_integer(),
          reconnect_on_error: boolean(),
          restore_subscriptions: boolean(),
          request_timeout: pos_integer(),
          debug: boolean()
        }

  @doc """
  Creates and validates a new configuration.
  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(url, opts \\ []) when is_binary(url) do
    config = struct(__MODULE__, [{:url, url} | opts])
    validate(config)
  end

  @doc """
  Creates and validates a new configuration, raising on error.
  """
  @spec new!(String.t(), keyword()) :: t()
  def new!(url, opts \\ []) when is_binary(url) do
    case new(url, opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates a configuration struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{url: url} = config) when is_binary(url) do
    cond do
      not valid_url?(url) ->
        {:error, "Invalid URL format"}

      config.timeout <= 0 ->
        {:error, "Timeout must be positive"}

      config.retry_count < 0 ->
        {:error, "Retry count must be non-negative"}

      config.retry_delay <= 0 ->
        {:error, "Retry delay must be positive"}

      config.heartbeat_interval <= 0 ->
        {:error, "Heartbeat interval must be positive"}

      config.max_backoff <= 0 ->
        {:error, "Max backoff must be positive"}

      config.max_backoff < config.retry_delay ->
        {:error, "Max backoff must be >= retry delay"}

      config.request_timeout <= 0 ->
        {:error, "Request timeout must be positive"}

      true ->
        {:ok, config}
    end
  end

  def validate(_), do: {:error, "URL is required"}

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end
end
