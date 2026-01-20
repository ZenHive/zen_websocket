defmodule ZenWebsocket.ConfigTest do
  use ExUnit.Case

  alias ZenWebsocket.Config

  describe "new/2" do
    test "creates valid config with defaults" do
      {:ok, config} = Config.new("wss://test.example.com/ws")

      assert config.url == "wss://test.example.com/ws"
      assert config.headers == []
      assert config.timeout == 5_000
      assert config.retry_count == 3
      assert config.retry_delay == 1_000
      assert config.heartbeat_interval == 30_000
      assert config.max_backoff == 30_000
      assert config.reconnect_on_error == true
      assert config.restore_subscriptions == true
    end

    test "creates config with custom options" do
      opts = [timeout: 10_000, retry_count: 5, headers: [{"Authorization", "Bearer token"}]]
      {:ok, config} = Config.new("ws://localhost:8080", opts)

      assert config.timeout == 10_000
      assert config.retry_count == 5
      assert config.headers == [{"Authorization", "Bearer token"}]
    end

    test "validates URL format" do
      {:error, "Invalid URL format"} = Config.new("http://example.com")
      {:error, "Invalid URL format"} = Config.new("invalid-url")
      {:error, "Invalid URL format"} = Config.new("wss://")
    end

    test "validates positive timeout" do
      {:error, "Timeout must be positive"} = Config.new("wss://test.com", timeout: 0)
      {:error, "Timeout must be positive"} = Config.new("wss://test.com", timeout: -1000)
    end

    test "validates non-negative retry count" do
      {:error, "Retry count must be non-negative"} = Config.new("wss://test.com", retry_count: -1)
    end

    test "validates positive retry delay" do
      {:error, "Retry delay must be positive"} = Config.new("wss://test.com", retry_delay: 0)
    end

    test "validates positive heartbeat interval" do
      {:error, "Heartbeat interval must be positive"} = Config.new("wss://test.com", heartbeat_interval: 0)
    end

    test "validates positive max backoff" do
      {:error, "Max backoff must be positive"} = Config.new("wss://test.com", max_backoff: 0)
    end

    test "validates max backoff >= retry delay" do
      {:error, "Max backoff must be >= retry delay"} =
        Config.new("wss://test.com",
          retry_delay: 5000,
          max_backoff: 1000
        )
    end

    test "accepts custom reconnection options" do
      {:ok, config} =
        Config.new("wss://test.com",
          max_backoff: 60_000,
          reconnect_on_error: false,
          restore_subscriptions: false
        )

      assert config.max_backoff == 60_000
      assert config.reconnect_on_error == false
      assert config.restore_subscriptions == false
    end

    test "validates positive request_timeout" do
      {:error, "Request timeout must be positive"} =
        Config.new("wss://test.com", request_timeout: 0)
    end

    test "validates negative request_timeout" do
      {:error, "Request timeout must be positive"} =
        Config.new("wss://test.com", request_timeout: -1000)
    end
  end

  describe "new!/2" do
    test "returns config on success" do
      config = Config.new!("wss://test.example.com/ws")
      assert config.url == "wss://test.example.com/ws"
    end

    test "raises ArgumentError on invalid URL" do
      assert_raise ArgumentError, "Invalid URL format", fn ->
        Config.new!("invalid-url")
      end
    end

    test "raises ArgumentError on invalid options" do
      assert_raise ArgumentError, "Timeout must be positive", fn ->
        Config.new!("wss://test.com", timeout: -1)
      end
    end
  end

  describe "validate/1" do
    test "accepts valid config" do
      config = %Config{url: "wss://test.com"}
      {:ok, ^config} = Config.validate(config)
    end

    test "rejects missing URL" do
      {:error, "URL is required"} = Config.validate(%Config{})
    end

    test "rejects non-Config struct" do
      {:error, "URL is required"} = Config.validate(%{url: "wss://test.com"})
    end

    test "rejects nil URL" do
      {:error, "URL is required"} = Config.validate(%Config{url: nil})
    end
  end
end
