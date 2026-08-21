defmodule ZenWebsocket.ClientCorrelation do
  @moduledoc """
  JSON-RPC response and timeout correlation for `ZenWebsocket.Client`.
  """

  alias ZenWebsocket.LatencyStats
  alias ZenWebsocket.RequestCorrelator
  alias ZenWebsocket.SubscriptionManager

  @doc """
  Applies the pending-request pin checks for Erlang and legacy correlation timeouts.
  """
  @spec handle_timeout_message(map(), term()) :: {:noreply, map()}
  def handle_timeout_message(state, {:timeout, timeout_ref, {:correlation_timeout, request_id}}) do
    case Map.get(state.pending_requests, request_id) do
      {_from, ^timeout_ref, _start_time} ->
        handle_timeout(state, request_id)

      _other ->
        {:noreply, state}
    end
  end

  def handle_timeout_message(state, {:correlation_timeout, request_id}) do
    case Map.get(state.pending_requests, request_id) do
      {_from, _timeout_ref, _start_time} ->
        handle_timeout(state, request_id)

      _other ->
        {:noreply, state}
    end
  end

  @doc """
  Replies `{:error, :timeout}` to the caller waiting on `request_id`.
  """
  @spec handle_timeout(map(), term()) :: {:noreply, map()}
  def handle_timeout(state, request_id) do
    case RequestCorrelator.timeout(state, request_id) do
      {nil, state} ->
        {:noreply, state}

      {{from, _timeout_ref, _start_time}, new_state} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, new_state}
    end
  end

  @doc """
  Resolves a JSON-RPC response and records its round-trip latency.
  """
  @spec handle_response(map(), map()) :: map()
  def handle_response(%{"id" => id} = response, state) do
    state = SubscriptionManager.handle_message(response, state)

    case RequestCorrelator.resolve(state, id) do
      {nil, state} ->
        state.handler.({:unmatched_response, response})
        state

      {{from, _timeout_ref, start_time}, new_state} ->
        GenServer.reply(from, {:ok, response})

        round_trip_ms = System.monotonic_time(:millisecond) - start_time
        updated_latency_stats = LatencyStats.add(new_state.latency_stats, round_trip_ms)
        %{new_state | latency_stats: updated_latency_stats}
    end
  end
end
