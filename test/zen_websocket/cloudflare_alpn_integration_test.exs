defmodule ZenWebsocket.CloudflareAlpnIntegrationTest do
  @moduledoc """
  Integration tests for WebSocket connections to Cloudflare-fronted servers.

  These tests verify the ALPN HTTP/1.1 fix that prevents Cloudflare from
  negotiating HTTP/2 during TLS handshake, which would break WebSocket upgrades.

  Background:
  - Cloudflare-fronted servers negotiate HTTP/2 via TLS ALPN by default
  - HTTP/2 strips Connection: Upgrade headers, breaking WebSocket upgrades
  - The fix forces HTTP/1.1 via alpn_advertised_protocols in TLS options
  """
  use ExUnit.Case, async: false

  alias ZenWebsocket.Client

  @moduletag :integration
  @moduletag :external_network

  # OKX is behind Cloudflare and will negotiate HTTP/2 without ALPN fix
  @okx_ws_url "wss://ws.okx.com:8443/ws/v5/public"

  describe "Cloudflare-fronted WebSocket connections" do
    @tag timeout: 15_000
    test "connects to OKX through Cloudflare with ALPN HTTP/1.1" do
      # This test verifies the ALPN fix works against a real Cloudflare server.
      # Without the fix, this would fail with:
      #   {:gun_down, pid, :http, :normal, []}
      # because Cloudflare negotiates HTTP/2 and rejects the WebSocket upgrade.

      result = Client.connect(@okx_ws_url, timeout: 10_000, reconnect_on_error: false)

      case result do
        {:ok, client} ->
          # Connection succeeded - ALPN fix is working
          assert is_struct(client, Client)
          assert client.state == :connected

          Client.close(client)

        {:error, reason} ->
          # If connection fails, check if it's the ALPN issue
          error_str = inspect(reason)

          if String.contains?(error_str, "gun_down") and String.contains?(error_str, ":normal") do
            flunk("""
            ALPN fix not working - Cloudflare negotiated HTTP/2.

            Error: #{error_str}

            The fix should include in build_gun_opts/1:
              transport: :tls,
              tls_opts: [alpn_advertised_protocols: ["http/1.1"], ...]
            """)
          else
            # Other network errors (DNS, firewall, etc.) - fail with explanation
            flunk("Connection failed (may be network issue): #{error_str}")
          end
      end
    end
  end
end
