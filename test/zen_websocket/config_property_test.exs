defmodule ZenWebsocket.ConfigPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ZenWebsocket.Config

  @positive_field_errors %{
    timeout: "Timeout must be positive",
    retry_delay: "Retry delay must be positive",
    heartbeat_interval: "Heartbeat interval must be positive",
    max_backoff: "Max backoff must be positive",
    request_timeout: "Request timeout must be positive",
    latency_buffer_size: "Latency buffer size must be positive"
  }

  defp host_gen do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp valid_url_gen do
    StreamData.bind(
      StreamData.tuple({StreamData.member_of(["ws", "wss"]), host_gen()}),
      fn {scheme, host} -> StreamData.constant("#{scheme}://#{host}") end
    )
  end

  defp pos_int(max \\ 1_000_000), do: StreamData.integer(1..max)

  describe "valid-input totality" do
    property "any ws/wss URL with valid positive-int fields produces {:ok, _}" do
      check all url <- valid_url_gen(),
                timeout <- pos_int(),
                retry_count <- StreamData.integer(0..100),
                retry_delay <- pos_int(10_000),
                heartbeat_interval <- pos_int(),
                backoff_offset <- StreamData.integer(0..100_000),
                request_timeout <- pos_int(),
                latency_buffer_size <- pos_int(10_000) do
        max_backoff = retry_delay + backoff_offset

        opts = [
          timeout: timeout,
          retry_count: retry_count,
          retry_delay: retry_delay,
          heartbeat_interval: heartbeat_interval,
          max_backoff: max_backoff,
          request_timeout: request_timeout,
          latency_buffer_size: latency_buffer_size
        ]

        assert {:ok, %Config{}} = Config.new(url, opts)
      end
    end
  end

  describe "URL validation" do
    property "non ws/wss URLs always return invalid-URL error" do
      check all scheme <- StreamData.member_of(["http", "https", "ftp", "file", ""]),
                host <- host_gen() do
        url = if scheme == "", do: host, else: "#{scheme}://#{host}"
        assert {:error, "Invalid URL format"} = Config.new(url)
      end
    end

    property "ws/wss with empty host fails" do
      check all scheme <- StreamData.member_of(["ws", "wss"]) do
        assert {:error, "Invalid URL format"} = Config.new("#{scheme}://")
      end
    end
  end

  describe "non-positive field rejection" do
    for {field, expected_msg} <- @positive_field_errors do
      property "#{field} <= 0 returns exact validation error" do
        check all url <- valid_url_gen(),
                  bad <- StreamData.integer(-1000..0) do
          assert Config.new(url, [{unquote(field), bad}]) == {:error, unquote(expected_msg)}
        end
      end
    end
  end

  describe "retry_count validation" do
    property "negative retry_count returns exact validation error" do
      check all url <- valid_url_gen(),
                bad <- StreamData.integer(-1000..-1) do
        assert Config.new(url, retry_count: bad) == {:error, "Retry count must be non-negative"}
      end
    end
  end

  describe "ordering constraint" do
    property "max_backoff < retry_delay (both positive) returns exact validation error" do
      check all url <- valid_url_gen(),
                retry_delay <- StreamData.integer(2..10_000),
                max_backoff <- StreamData.integer(1..(retry_delay - 1)) do
        assert Config.new(url, retry_delay: retry_delay, max_backoff: max_backoff) ==
                 {:error, "Max backoff must be >= retry delay"}
      end
    end
  end

  describe "new!/2 consistency" do
    property "new!/2 raises iff new/2 returns {:error, _}" do
      check all url <- StreamData.one_of([valid_url_gen(), host_gen()]),
                timeout <- StreamData.integer(-100..100) do
        case Config.new(url, timeout: timeout) do
          {:ok, config} ->
            assert %Config{} = Config.new!(url, timeout: timeout)
            assert config == Config.new!(url, timeout: timeout)

          {:error, _} ->
            assert_raise ArgumentError, fn -> Config.new!(url, timeout: timeout) end
        end
      end
    end
  end
end
