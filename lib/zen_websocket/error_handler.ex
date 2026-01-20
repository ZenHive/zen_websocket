defmodule ZenWebsocket.ErrorHandler do
  @moduledoc """
  Simple error handling for WebSocket connections.

  Handles common error scenarios:
  - Connection errors (network failures)
  - Protocol errors (malformed frames)
  - Authentication errors
  - Timeout errors

  Passes raw errors without wrapping to preserve original error information.
  Provides human-readable explanations via `explain/1`.
  """

  @typedoc """
  Human-readable error explanation with fix suggestions.

  - `message` - What went wrong
  - `suggestion` - How to fix it
  - `docs_url` - Link to relevant docs (currently always nil, reserved for future use)
  """
  @type explanation :: %{
          message: String.t(),
          suggestion: String.t(),
          docs_url: String.t() | nil
        }

  @doc """
  Categorizes errors into recoverable vs non-recoverable types.

  Returns the raw error unchanged to preserve all original information.
  """
  @spec categorize_error(term()) :: {:recoverable | :fatal, term()}
  def categorize_error(error) do
    case check_recoverable(error) do
      {:recoverable, _} = result -> result
      :not_recoverable -> check_fatal(error)
    end
  end

  @doc false
  # Checks if error is recoverable (network/connection issues that may resolve).
  # Returns {:recoverable, normalized_error} or :not_recoverable.
  defp check_recoverable({:error, reason})
       when reason in [:econnrefused, :timeout, :nxdomain, :enotfound, :ehostunreach, :enetunreach] do
    {:recoverable, {:error, reason}}
  end

  defp check_recoverable({:error, {:tls_alert, _}} = error), do: {:recoverable, error}
  defp check_recoverable(:timeout), do: {:recoverable, {:error, :timeout}}
  defp check_recoverable(:connection_failed = error), do: {:recoverable, error}
  defp check_recoverable({:gun_down, _, _, reason, _}), do: {:recoverable, {:gun_down, reason}}
  defp check_recoverable({:gun_error, _, _, reason}), do: {:recoverable, {:gun_error, reason}}
  defp check_recoverable(_), do: :not_recoverable

  @doc false
  # Checks if error is fatal (protocol/auth issues that won't resolve on retry).
  # All unrecognized errors are treated as fatal.
  defp check_fatal({:error, reason})
       when reason in [:invalid_frame, :frame_too_large, :unauthorized, :invalid_credentials, :token_expired] do
    {:fatal, {:error, reason}}
  end

  defp check_fatal({:error, {:bad_frame, _}} = error), do: {:fatal, error}
  defp check_fatal(error), do: {:fatal, error}

  @doc """
  Determines if an error is recoverable through reconnection.
  """
  @spec recoverable?(term()) :: boolean()
  def recoverable?(error) do
    case categorize_error(error) do
      {:recoverable, _} -> true
      {:fatal, _} -> false
    end
  end

  @doc """
  Handles errors by returning appropriate actions.

  Returns either :reconnect or :stop based on error recoverability.
  """
  @spec handle_error(term()) :: :reconnect | :stop
  def handle_error(error) do
    case categorize_error(error) do
      {:recoverable, _} -> :reconnect
      {:fatal, _} -> :stop
    end
  end

  @doc """
  Returns a human-readable explanation for an error.

  Provides a clear message describing what happened, a suggestion for how to
  fix it, and optionally a documentation URL for more information.

  ## Examples

      iex> ZenWebsocket.ErrorHandler.explain({:error, :econnrefused})
      %{
        message: "Connection refused by server",
        suggestion: "Check that the server is running and verify the URL is correct",
        docs_url: nil
      }

      iex> ZenWebsocket.ErrorHandler.explain({:error, :unauthorized})
      %{
        message: "Authentication failed",
        suggestion: "Check your API credentials are valid and not expired",
        docs_url: nil
      }

  """
  @spec explain(term()) :: explanation()
  def explain(error) do
    error
    |> unwrap_error()
    |> do_explain()
  end

  @doc false
  # Unwraps nested error tuples to get the core error reason.
  # Handles {:error, reason}, {:gun_down, reason}, {:gun_error, reason} patterns.
  defp unwrap_error({:error, reason}), do: reason
  defp unwrap_error({:gun_down, reason}), do: {:gun_down, reason}
  defp unwrap_error({:gun_error, reason}), do: {:gun_error, reason}
  defp unwrap_error(error), do: error

  @doc false
  # Builds explanation map from message and suggestion.
  defp explanation(message, suggestion, docs_url \\ nil) do
    %{message: message, suggestion: suggestion, docs_url: docs_url}
  end

  @doc false
  # Returns human-readable explanation for a specific error reason.
  # Connection/network errors (recoverable)
  defp do_explain(:econnrefused) do
    explanation(
      "Connection refused by server",
      "Check that the server is running and verify the URL is correct"
    )
  end

  defp do_explain(:timeout) do
    explanation(
      "Connection timed out",
      "Check network connectivity or increase the timeout configuration"
    )
  end

  defp do_explain(:nxdomain) do
    explanation("DNS lookup failed - domain not found", "Verify the hostname spelling is correct")
  end

  defp do_explain({:tls_alert, details}) do
    explanation(
      "TLS/SSL handshake failed: #{inspect(details)}",
      "Check certificate validity and TLS configuration"
    )
  end

  defp do_explain(:enotfound), do: explanation("Host not found", "Verify the hostname is correct")

  defp do_explain(:ehostunreach) do
    explanation("Host unreachable", "Check network connectivity to the target host")
  end

  defp do_explain(:enetunreach) do
    explanation("Network unreachable", "Check your network connection or VPN status")
  end

  defp do_explain({:gun_down, reason}) do
    explanation(
      "Connection closed unexpectedly: #{inspect(reason)}",
      "Will auto-reconnect if reconnection is configured"
    )
  end

  defp do_explain({:gun_error, reason}) do
    explanation("Connection error: #{inspect(reason)}", "Check server status and network connectivity")
  end

  defp do_explain(:connection_failed) do
    explanation("Connection failed", "Verify the URL and check network connectivity")
  end

  # Protocol errors (fatal)
  defp do_explain(:invalid_frame) do
    explanation(
      "Invalid WebSocket frame received",
      "Server sent malformed data - this may indicate a server bug"
    )
  end

  defp do_explain(:frame_too_large) do
    explanation(
      "Frame exceeds maximum size limit",
      "Increase max_frame_size in configuration if larger frames are expected"
    )
  end

  defp do_explain({:bad_frame, details}) do
    explanation("Malformed frame received: #{inspect(details)}", "Protocol error - check server implementation")
  end

  # Authentication errors (fatal)
  defp do_explain(:unauthorized) do
    explanation("Authentication failed", "Check your API credentials are valid and not expired")
  end

  defp do_explain(:invalid_credentials) do
    explanation("Invalid credentials provided", "Verify your API key and secret are correct")
  end

  defp do_explain(:token_expired) do
    explanation("Authentication token has expired", "Re-authenticate to obtain a fresh token")
  end

  # Unknown errors - include the raw error in the message
  defp do_explain(unknown) do
    explanation("Unknown error: #{inspect(unknown)}", "Check logs for more details")
  end
end
