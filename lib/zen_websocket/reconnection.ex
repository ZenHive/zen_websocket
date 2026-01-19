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
  alias ZenWebsocket.Config
  alias ZenWebsocket.Debug

  @default_max_backoff_ms 30_000

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
    Debug.log(config, "   📍 Path: #{uri.path || "/"}")
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
            Debug.log(config, "   📋 Headers: #{inspect(config.headers)}")

            stream_ref = :gun.ws_upgrade(gun_pid, uri.path || "/", config.headers)
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

  @doc """
  Check if maximum retry attempts have been exceeded.
  """
  @spec max_retries_exceeded?(attempt :: non_neg_integer(), max_retries :: non_neg_integer()) ::
          boolean()
  def max_retries_exceeded?(attempt, max_retries) do
    attempt >= max_retries
  end

  @doc """
  Restore subscriptions after successful reconnection.

  This should be called after the WebSocket upgrade is complete and the
  connection is ready to receive subscription messages.

  Accepts a Config struct or state map for conditional debug logging.
  """
  @spec restore_subscriptions(
          gun_pid :: pid(),
          stream_ref :: reference(),
          subscriptions :: [String.t()],
          config_or_state :: Config.t() | map()
        ) :: :ok
  def restore_subscriptions(gun_pid, stream_ref, subscriptions, config_or_state \\ %{})

  def restore_subscriptions(_gun_pid, _stream_ref, [], _config_or_state), do: :ok

  def restore_subscriptions(gun_pid, stream_ref, subscriptions, config_or_state) when is_list(subscriptions) do
    Debug.log(config_or_state, "📡 [RESTORE SUBSCRIPTIONS] #{DateTime.to_string(DateTime.utc_now())}")
    Debug.log(config_or_state, "   🔧 Gun PID: #{inspect(gun_pid)}")
    Debug.log(config_or_state, "   📡 Stream Ref: #{inspect(stream_ref)}")
    Debug.log(config_or_state, "   📋 Subscriptions: #{inspect(subscriptions)}")

    message =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "public/subscribe",
        "params" => %{"channels" => subscriptions},
        "id" => System.unique_integer([:positive])
      })

    Debug.log(config_or_state, "   📤 Sending subscription restore message...")
    :gun.ws_send(gun_pid, stream_ref, {:text, message})
    Debug.log(config_or_state, "   ✅ Subscription restoration complete")

    :ok
  end
end
