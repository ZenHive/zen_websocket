defmodule ZenWebsocket.Reconnection do
  # Default maximum delay between reconnection attempts (30 seconds).
  # Prevents exponential backoff from growing unbounded.
  @moduledoc """
  Internal reconnection helper for Client GenServer.

  This module provides reconnection logic that runs within the Client GenServer
  process to maintain Gun message ownership. It handles:

  - Connection establishment with retry logic
  - Exponential backoff calculations
  - Subscription restoration after reconnection

  ## Architecture

  This module is called by the Client GenServer during its handle_continue
  and handle_info callbacks. All functions run in the Client GenServer process
  to ensure the new Gun connection sends messages to the correct process.

  ## Not for External Use

  This module is internal to ZenWebsocket. External code should use
  `ZenWebsocket.Client.connect/2` which handles initial connection attempts
  and automatic reconnection.
  """
  use Descripex, namespace: "/reconnection"

  alias ZenWebsocket.Config
  alias ZenWebsocket.Debug

  @default_max_backoff_ms 30_000

  api(:establish_connection, "Establish a Gun WebSocket connection from the given config.",
    params: [config: [kind: :value, description: "Client configuration struct"]],
    returns: %{
      type: "{:ok, pid(), reference(), reference()} | {:error, term()}",
      description: "Gun PID, stream ref, and monitor ref on success"
    }
  )

  @doc """
  Attempt to establish a Gun connection with the given configuration.

  This function must be called from within the Client GenServer process
  to ensure Gun sends messages to the correct process.
  """
  @spec establish_connection(Config.t()) ::
          {:ok, gun_pid :: pid(), stream_ref :: reference(), monitor_ref :: reference()}
          | {:error, term()}
  def establish_connection(%Config{} = config) do
    uri = URI.parse(config.url)
    port = uri.port || if uri.scheme == "wss", do: 443, else: 80

    Debug.log(config, "🔫 [GUN OPEN] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(config, "   🌐 Host: #{uri.host}")
    Debug.log(config, "   🔌 Port: #{port}")
    Debug.log(config, "   📋 Scheme: #{uri.scheme}")
    upgrade_path = build_upgrade_path(uri)
    Debug.log(config, "   📍 Path: #{upgrade_path}")
    Debug.log(config, "   🔄 Opening Gun connection...")

    # Gun sends messages to the calling process (Client GenServer)
    gun_opts = build_gun_opts(uri)

    case :gun.open(to_charlist(uri.host), port, gun_opts) do
      {:ok, gun_pid} ->
        Debug.log(config, "   ✅ Gun connection opened successfully")
        Debug.log(config, "   🔧 Gun PID: #{inspect(gun_pid)}")
        Debug.log(config, "   👁️  Setting up process monitor...")

        monitor_ref = Process.monitor(gun_pid)
        Debug.log(config, "   📍 Monitor Ref: #{inspect(monitor_ref)}")
        Debug.log(config, "   ⏳ Awaiting Gun up (timeout: #{config.timeout}ms)...")

        case :gun.await_up(gun_pid, config.timeout) do
          {:ok, protocol} ->
            Debug.log(config, "   ✅ Gun connection up")
            Debug.log(config, "   🌐 Protocol: #{inspect(protocol)}")
            Debug.log(config, "   🔄 Upgrading to WebSocket...")

            stream_ref = :gun.ws_upgrade(gun_pid, upgrade_path, config.headers)
            Debug.log(config, "   📡 WebSocket upgrade initiated")
            Debug.log(config, "   📡 Stream Ref: #{inspect(stream_ref)}")
            Debug.log(config, "   ✅ Connection establishment complete")

            {:ok, gun_pid, stream_ref, monitor_ref}

          {:error, reason} ->
            Debug.log(config, "   ❌ Gun await_up failed: #{inspect(reason)}")
            Debug.log(config, "   🧹 Cleaning up monitor and closing Gun...")

            Process.demonitor(monitor_ref, [:flush])
            :gun.close(gun_pid)
            {:error, reason}
        end

      {:error, reason} ->
        Debug.log(config, "   ❌ Gun open failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  api(:build_gun_opts, "Build Gun connection options for a URI scheme.",
    params: [uri: [kind: :value, description: "Parsed URI with scheme (ws or wss)"]],
    returns: %{type: "map()", description: "Gun transport and protocol options"}
  )

  @doc """
  Build Gun connection options for the given URI.

  For WSS connections, configures TLS ALPN to force HTTP/1.1 negotiation.
  Without this, Cloudflare-fronted servers negotiate HTTP/2 via ALPN,
  which strips Connection: Upgrade headers and breaks WebSocket upgrades.
  """
  @spec build_gun_opts(URI.t()) :: map()
  def build_gun_opts(%URI{scheme: "wss"}) do
    %{
      protocols: [:http],
      transport: :tls,
      tls_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        alpn_advertised_protocols: ["http/1.1"]
      ]
    }
  end

  def build_gun_opts(%URI{}) do
    %{protocols: [:http]}
  end

  api(:calculate_backoff, "Calculate exponential backoff delay for a reconnection attempt.",
    params: [
      attempt: [kind: :value, description: "Zero-based attempt number"],
      base_delay: [kind: :value, description: "Base delay in milliseconds"],
      max_backoff: [kind: :value, description: "Maximum delay cap in milliseconds (nil uses default 30s)"]
    ],
    returns: %{type: "pos_integer()", description: "Delay in milliseconds, capped at max_backoff"}
  )

  @doc """
  Calculate exponential backoff delay for reconnection attempts.

  ## Examples

      iex> calculate_backoff(0, 1000)
      1000

      iex> calculate_backoff(1, 1000)
      2000

      iex> calculate_backoff(5, 1000, 30000)
      30000  # Capped at max_backoff
  """
  @spec calculate_backoff(
          attempt :: non_neg_integer(),
          base_delay :: pos_integer(),
          max_backoff :: pos_integer() | nil
        ) ::
          pos_integer()
  def calculate_backoff(attempt, base_delay, max_backoff \\ @default_max_backoff_ms) do
    delay = base_delay * :math.pow(2, attempt)
    max_delay = max_backoff || @default_max_backoff_ms
    min(round(delay), max_delay)
  end

  api(:should_reconnect?, "Check whether an error should trigger reconnection.",
    params: [error: [kind: :value, description: "Error term to evaluate"]],
    returns: %{type: "boolean()", description: "True if the error is recoverable"}
  )

  @doc """
  Determine if a connection error should trigger reconnection.

  Returns true for recoverable errors like network issues, false for
  unrecoverable errors like invalid credentials.
  """
  @spec should_reconnect?(error :: term()) :: boolean()
  def should_reconnect?(error) do
    case ZenWebsocket.ErrorHandler.handle_error(error) do
      :reconnect -> true
      _ -> false
    end
  end

  api(:max_retries_exceeded?, "Check if the retry attempt count has exceeded the maximum.",
    params: [
      attempt: [kind: :value, description: "Current attempt number"],
      max_retries: [kind: :value, description: "Maximum allowed retries"]
    ],
    returns: %{type: "boolean()", description: "True if attempt >= max_retries"}
  )

  @doc """
  Check if maximum retry attempts have been exceeded.
  """
  @spec max_retries_exceeded?(attempt :: non_neg_integer(), max_retries :: non_neg_integer()) ::
          boolean()
  def max_retries_exceeded?(attempt, max_retries) do
    attempt >= max_retries
  end

  # Builds the upgrade path for :gun.ws_upgrade/3, preserving query params
  # when present in the original URL (e.g., wss://host/path?token=abc → /path?token=abc)
  defp build_upgrade_path(%URI{path: path, query: query}) do
    base = path || "/"
    if query, do: base <> "?" <> query, else: base
  end
end
