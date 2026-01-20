defmodule ZenWebsocket.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias ZenWebsocket.ErrorHandler

  describe "categorize_error/1" do
    test "categorizes connection errors correctly" do
      assert {:recoverable, {:error, :econnrefused}} = ErrorHandler.categorize_error({:error, :econnrefused})
      assert {:recoverable, {:error, :nxdomain}} = ErrorHandler.categorize_error({:error, :nxdomain})

      assert {:recoverable, {:error, {:tls_alert, :bad_certificate}}} =
               ErrorHandler.categorize_error({:error, {:tls_alert, :bad_certificate}})

      assert {:recoverable, {:gun_down, :closed}} =
               ErrorHandler.categorize_error({:gun_down, :pid, :ws, :closed, []})

      assert {:recoverable, {:gun_error, :timeout}} =
               ErrorHandler.categorize_error({:gun_error, :pid, :ref, :timeout})
    end

    test "categorizes timeout errors correctly" do
      assert {:recoverable, {:error, :timeout}} = ErrorHandler.categorize_error({:error, :timeout})
    end

    test "categorizes protocol errors correctly" do
      assert {:fatal, {:error, :invalid_frame}} = ErrorHandler.categorize_error({:error, :invalid_frame})
      assert {:fatal, {:error, :frame_too_large}} = ErrorHandler.categorize_error({:error, :frame_too_large})

      assert {:fatal, {:error, {:bad_frame, :invalid_opcode}}} =
               ErrorHandler.categorize_error({:error, {:bad_frame, :invalid_opcode}})
    end

    test "categorizes authentication errors correctly" do
      assert {:fatal, {:error, :unauthorized}} = ErrorHandler.categorize_error({:error, :unauthorized})
      assert {:fatal, {:error, :invalid_credentials}} = ErrorHandler.categorize_error({:error, :invalid_credentials})
      assert {:fatal, {:error, :token_expired}} = ErrorHandler.categorize_error({:error, :token_expired})
    end

    test "categorizes unknown errors correctly" do
      assert {:fatal, {:error, :some_random_error}} = ErrorHandler.categorize_error({:error, :some_random_error})
      assert {:fatal, :unexpected_data} = ErrorHandler.categorize_error(:unexpected_data)
    end
  end

  describe "recoverable?/1" do
    test "returns true for recoverable errors" do
      assert ErrorHandler.recoverable?({:error, :econnrefused})
      assert ErrorHandler.recoverable?({:error, :timeout})
      assert ErrorHandler.recoverable?({:gun_down, :pid, :ws, :closed, []})
    end

    test "returns false for non-recoverable errors" do
      refute ErrorHandler.recoverable?({:error, :invalid_frame})
      refute ErrorHandler.recoverable?({:error, :unauthorized})
      refute ErrorHandler.recoverable?({:error, :invalid_credentials})
      refute ErrorHandler.recoverable?({:error, :some_unknown_error})
    end
  end

  describe "handle_error/1" do
    test "returns :reconnect for connection errors" do
      assert :reconnect = ErrorHandler.handle_error({:error, :econnrefused})
      assert :reconnect = ErrorHandler.handle_error({:error, :timeout})
      assert :reconnect = ErrorHandler.handle_error({:gun_down, :pid, :ws, :closed, []})
    end

    test "returns :stop for protocol and auth errors" do
      assert :stop = ErrorHandler.handle_error({:error, :invalid_frame})
      assert :stop = ErrorHandler.handle_error({:error, :unauthorized})
      assert :stop = ErrorHandler.handle_error({:error, :invalid_credentials})
    end

    test "returns :stop for unknown errors" do
      assert :stop = ErrorHandler.handle_error({:error, :some_unknown_error})
      assert :stop = ErrorHandler.handle_error(:unexpected_data)
    end
  end

  describe "explain/1" do
    test "returns explanation struct with required keys" do
      result = ErrorHandler.explain({:error, :econnrefused})

      assert is_map(result)
      assert Map.has_key?(result, :message)
      assert Map.has_key?(result, :suggestion)
      assert Map.has_key?(result, :docs_url)
      assert is_binary(result.message)
      assert is_binary(result.suggestion)
    end

    test "explains connection errors" do
      assert %{message: "Connection refused" <> _} = ErrorHandler.explain({:error, :econnrefused})
      assert %{message: "Connection timed out" <> _} = ErrorHandler.explain({:error, :timeout})
      assert %{message: "DNS lookup failed" <> _} = ErrorHandler.explain({:error, :nxdomain})
      assert %{message: "Host not found" <> _} = ErrorHandler.explain({:error, :enotfound})
      assert %{message: "Host unreachable" <> _} = ErrorHandler.explain({:error, :ehostunreach})
      assert %{message: "Network unreachable" <> _} = ErrorHandler.explain({:error, :enetunreach})
      assert %{message: "Connection failed" <> _} = ErrorHandler.explain(:connection_failed)
    end

    test "explains TLS errors with details" do
      result = ErrorHandler.explain({:error, {:tls_alert, :bad_certificate}})

      assert result.message =~ "TLS/SSL handshake failed"
      assert result.message =~ "bad_certificate"
      assert result.suggestion =~ "certificate"
    end

    test "explains gun_down errors" do
      result = ErrorHandler.explain({:gun_down, :closed})

      assert result.message =~ "Connection closed unexpectedly"
      assert result.message =~ "closed"
      assert result.suggestion =~ "reconnect"
    end

    test "explains gun_error errors" do
      result = ErrorHandler.explain({:gun_error, :timeout})

      assert result.message =~ "Connection error"
      assert result.message =~ "timeout"
    end

    test "explains protocol errors" do
      assert %{message: "Invalid WebSocket frame" <> _} = ErrorHandler.explain({:error, :invalid_frame})
      assert %{message: "Frame exceeds" <> _} = ErrorHandler.explain({:error, :frame_too_large})

      bad_frame_result = ErrorHandler.explain({:error, {:bad_frame, :invalid_opcode}})
      assert bad_frame_result.message =~ "Malformed frame"
      assert bad_frame_result.message =~ "invalid_opcode"
    end

    test "explains authentication errors" do
      assert %{message: "Authentication failed" <> _} = ErrorHandler.explain({:error, :unauthorized})

      assert %{message: "Invalid credentials" <> _} =
               ErrorHandler.explain({:error, :invalid_credentials})

      assert %{message: msg} = ErrorHandler.explain({:error, :token_expired})
      assert msg =~ "expired"
    end

    test "handles unknown errors with raw error in message" do
      result = ErrorHandler.explain({:error, :some_weird_error})

      assert result.message =~ "Unknown error"
      assert result.message =~ "some_weird_error"
      assert result.suggestion =~ "logs"
    end

    test "handles raw atoms without {:error, _} wrapper" do
      result = ErrorHandler.explain(:econnrefused)

      assert result.message =~ "Connection refused"
    end

    test "handles nested tuples correctly" do
      # {:error, {:tls_alert, details}} should unwrap properly
      result = ErrorHandler.explain({:error, {:tls_alert, :certificate_expired}})

      assert result.message =~ "TLS"
      assert result.message =~ "certificate_expired"
    end

    test "handles completely unknown data structures" do
      result = ErrorHandler.explain(%{weird: "structure"})

      assert result.message =~ "Unknown error"
      assert result.message =~ "weird"
    end
  end
end
