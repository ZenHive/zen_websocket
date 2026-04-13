defmodule ZenWebsocket.JsonRpcPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ZenWebsocket.JsonRpc

  defp method_gen do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 30)
  end

  describe "build_request/2 shape" do
    property "returns {:ok, request} with jsonrpc/id/method keys and no params when nil" do
      check all method <- method_gen() do
        assert {:ok, req} = JsonRpc.build_request(method)
        assert req["jsonrpc"] == "2.0"
        assert is_integer(req["id"])
        assert req["id"] > 0
        assert req["method"] == method
        refute Map.has_key?(req, "params")
      end
    end

    property "includes params key when params map provided" do
      check all method <- method_gen(),
                params <- StreamData.map_of(method_gen(), StreamData.integer()) do
        assert {:ok, req} = JsonRpc.build_request(method, params)
        assert req["params"] == params
      end
    end
  end

  describe "unique IDs" do
    property "N sequential calls produce N distinct ids" do
      check all n <- StreamData.integer(2..20),
                method <- method_gen() do
        ids =
          for _ <- 1..n do
            {:ok, req} = JsonRpc.build_request(method)
            req["id"]
          end

        assert length(Enum.uniq(ids)) == n
      end
    end
  end

  describe "match_response" do
    property "result case returns {:ok, term}" do
      check all id <- StreamData.integer(1..1_000_000),
                result <-
                  StreamData.one_of([
                    StreamData.integer(),
                    StreamData.binary(),
                    StreamData.boolean(),
                    StreamData.constant(nil),
                    StreamData.list_of(StreamData.integer(), max_length: 5),
                    StreamData.map_of(method_gen(), StreamData.integer(), max_length: 3)
                  ]) do
        assert JsonRpc.match_response(%{"id" => id, "result" => result}) == {:ok, result}
      end
    end

    property "error case returns {:error, {code, message}}" do
      check all id <- StreamData.integer(1..1_000_000),
                code <- StreamData.integer(-32_768..32_767),
                message <- StreamData.string(:printable, max_length: 100) do
        response = %{
          "id" => id,
          "error" => %{"code" => code, "message" => message}
        }

        assert JsonRpc.match_response(response) == {:error, {code, message}}
      end
    end

    property "notification case returns {:notification, method, params}" do
      check all method <- method_gen(),
                params <- StreamData.map_of(method_gen(), StreamData.integer(), max_length: 3) do
        response = %{"method" => method, "params" => params}
        assert JsonRpc.match_response(response) == {:notification, method, params}
      end
    end
  end
end
