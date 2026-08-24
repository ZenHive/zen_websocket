defmodule ZenWebsocket.DescribeSurfaceTest do
  @moduledoc """
  Pins the descripex agent surface to the real consumer API.

  One source of truth: `Client.__api__/0`. Param kinds, the `describe/0`
  module set, supervised entry points, and the Client moduledoc Public API
  section must agree with that list.
  """

  use ExUnit.Case, async: true

  @internal_modules [
    ZenWebsocket.Reconnection,
    ZenWebsocket.HeartbeatManager,
    ZenWebsocket.SubscriptionManager,
    ZenWebsocket.RequestCorrelator
  ]

  @inbound_or_state ~r/client\s+state|\bincoming\b|\binbound\b|gun\s+message|gun\s+websocket\s+frame|jsonl[- ]formatted\s+line|raw\s+frame|decoded\s+json-rpc|decoded\s+websocket\s+frame/i

  describe "param kinds" do
    test "marks wire-derived and Client-owned params as :exchange_data" do
      assert param_kind(ZenWebsocket.Frame, :decode, :frame) == :exchange_data
      assert param_kind(ZenWebsocket.JsonRpc, :match_response, :response) == :exchange_data
      assert param_kind(ZenWebsocket.MessageHandler, :handle_message, :message) == :exchange_data
      assert param_kind(ZenWebsocket.RequestCorrelator, :extract_id, :message) == :exchange_data
      assert param_kind(ZenWebsocket.SubscriptionManager, :handle_message, :msg) == :exchange_data
      assert param_kind(ZenWebsocket.HeartbeatManager, :handle_message, :msg) == :exchange_data
      assert param_kind(ZenWebsocket.Recorder, :parse_entry, :line) == :exchange_data
      assert param_kind(ZenWebsocket.HeartbeatManager, :start_timer, :state) == :exchange_data
      assert param_kind(ZenWebsocket.SubscriptionManager, :add, :state) == :exchange_data
      assert param_kind(ZenWebsocket.RequestCorrelator, :track, :state) == :exchange_data
    end

    test "marks caller-created rate-limit requests as :value" do
      assert param_kind(ZenWebsocket.RateLimiter, :deribit_cost, :request) == :value
      assert param_kind(ZenWebsocket.RateLimiter, :binance_cost, :request) == :value
      assert param_kind(ZenWebsocket.RateLimiter, :simple_cost, :request) == :value
    end

    test "no inbound message, frame, line, or Client state map is kind :value" do
      params = annotated_params()
      exchange_data = Enum.count(params, fn {_mod, _fun, _name, meta} -> meta[:kind] == :exchange_data end)

      assert exchange_data > 0

      bad =
        Enum.filter(params, fn {_mod, _fun, _name, meta} ->
          meta[:kind] == :value and inbound_or_state?(meta[:description])
        end)

      assert bad == [], inspect(bad)
    end
  end

  describe "describe/0 module set" do
    test "omits modules whose moduledocs declare them internal" do
      names = Enum.map(ZenWebsocket.describe(), & &1.module)

      for module <- @internal_modules do
        refute module in names
      end
    end

    test "each internal module records the describe/0 decision" do
      for module <- @internal_modules do
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)

        assert doc =~ "not listed in `ZenWebsocket.describe/0`",
               "#{inspect(module)} does not record the internal decision"
      end
    end
  end

  describe "Client public API source of truth" do
    test "describe(:client) includes start_link/2 and child_spec/1" do
      names = Enum.map(ZenWebsocket.describe(:client), & &1.name)

      assert :start_link in names
      assert :child_spec in names
      assert ZenWebsocket.Client.__api__(:start_link)
      assert ZenWebsocket.Client.__api__(:child_spec)
    end

    test "Client moduledoc Public API names match Client.__api__" do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(ZenWebsocket.Client)

      api_names =
        ZenWebsocket.Client.__api__()
        |> Enum.map(&Atom.to_string(&1.name))
        |> Enum.sort()

      assert public_api_names(doc) == api_names
    end
  end

  defp param_kind(module, fun, param) do
    %{hints: %{params: params}} = module.__api__(fun)
    params[param].kind
  end

  defp annotated_params do
    {:ok, modules} = :application.get_key(:zen_websocket, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__api__, 0),
        entry <- module.__api__(),
        {name, meta} <- entry[:hints][:params] || %{} do
      {module, entry.name, name, meta}
    end
  end

  defp inbound_or_state?(description) when is_binary(description) do
    Regex.match?(@inbound_or_state, description)
  end

  defp inbound_or_state?(_description), do: false

  defp public_api_names(moduledoc) do
    case Regex.run(~r/## Public API\n(.*?)(?=\n## |\z)/s, moduledoc) do
      [_, section] ->
        ~r/`?([a-z_]+)\/\d+`?/
        |> Regex.scan(section)
        |> Enum.map(fn [_, name] -> name end)
        |> Enum.uniq()
        |> Enum.sort()

      nil ->
        flunk("Client @moduledoc is missing a ## Public API section")
    end
  end
end
