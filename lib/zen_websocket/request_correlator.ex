defmodule ZenWebsocket.RequestCorrelator do
  @moduledoc """
  Manages request/response correlation for JSON-RPC WebSocket connections.

  Pure functional module - state ownership stays with Client GenServer.
  Tracks pending requests with timeouts and matches responses by ID.

  ## Telemetry Events

  The following telemetry events are emitted:

  * `[:zen_websocket, :request_correlator, :track]` - Emitted when a request is tracked.
    * Measurements: `%{count: 1}`
    * Metadata: `%{id: id, timeout_ms: timeout}`

  * `[:zen_websocket, :request_correlator, :resolve]` - Emitted when a response is matched.
    * Measurements: `%{count: 1}`
    * Metadata: `%{id: id}`

  * `[:zen_websocket, :request_correlator, :timeout]` - Emitted when a request times out.
    * Measurements: `%{count: 1}`
    * Metadata: `%{id: id}`
  """

  @typedoc "Client state map containing pending_requests field (subset of Client.state)"
  @type state :: %{
          :pending_requests => %{optional(term()) => {GenServer.from(), reference()}},
          optional(atom()) => term()
        }

  @doc """
  Extracts the request ID from a JSON message.

  Returns `{:ok, id}` if the message contains a non-nil ID field,
  or `:no_id` if no ID is present, the message is not valid JSON,
  or the ID is nil.
  """
  @spec extract_id(binary()) :: {:ok, term()} | :no_id
  def extract_id(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, %{"id" => id}} when not is_nil(id) -> {:ok, id}
      _ -> :no_id
    end
  end

  def extract_id(_), do: :no_id

  @doc """
  Tracks a pending request with a timeout timer.

  Creates a timer that will send `{:correlation_timeout, id}` to `self()`
  after the specified timeout. Must be called from within a GenServer context.
  """
  @spec track(state(), term(), GenServer.from(), pos_integer()) :: state()
  def track(state, id, from, timeout_ms) do
    timeout_ref = Process.send_after(self(), {:correlation_timeout, id}, timeout_ms)
    pending = Map.put(state.pending_requests, id, {from, timeout_ref})

    :telemetry.execute(
      [:zen_websocket, :request_correlator, :track],
      %{count: 1},
      %{id: id, timeout_ms: timeout_ms}
    )

    %{state | pending_requests: pending}
  end

  @doc """
  Resolves a pending request by ID, returning the caller info.

  Cancels the timeout timer and removes the request from pending.
  Returns `{entry, new_state}` where entry is `{from, timeout_ref}` or `nil`.
  """
  @spec resolve(state(), term()) :: {{GenServer.from(), reference()} | nil, state()}
  def resolve(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {{_from, timeout_ref} = entry, new_pending} ->
        Process.cancel_timer(timeout_ref)

        :telemetry.execute(
          [:zen_websocket, :request_correlator, :resolve],
          %{count: 1},
          %{id: id}
        )

        {entry, %{state | pending_requests: new_pending}}
    end
  end

  @doc """
  Handles a timeout for a pending request.

  Removes the request from pending and returns the caller info.
  Returns `{entry, new_state}` where entry is `{from, timeout_ref}` or `nil`.
  """
  @spec timeout(state(), term()) :: {{GenServer.from(), reference()} | nil, state()}
  def timeout(state, id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        {nil, state}

      {entry, new_pending} ->
        :telemetry.execute(
          [:zen_websocket, :request_correlator, :timeout],
          %{count: 1},
          %{id: id}
        )

        {entry, %{state | pending_requests: new_pending}}
    end
  end

  @doc """
  Returns the count of pending requests.
  """
  @spec pending_count(state()) :: non_neg_integer()
  def pending_count(state) do
    map_size(state.pending_requests)
  end
end
