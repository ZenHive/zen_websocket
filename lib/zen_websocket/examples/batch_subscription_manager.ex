defmodule ZenWebsocket.Examples.BatchSubscriptionManager do
  @moduledoc """
  Simple batch subscription manager for efficiently subscribing to multiple channels.

  Prevents overwhelming the API by batching subscription requests with configurable
  batch size and delay between batches.
  """

  use GenServer

  alias ZenWebsocket.Examples.DeribitAdapter

  require Logger

  @type batch_status :: %{
          completed: non_neg_integer(),
          pending: non_neg_integer(),
          total: non_neg_integer(),
          failed: boolean(),
          error: term() | nil
        }

  ## Public API (exactly 5 functions)

  @doc """
  Starts the batch subscription manager.

  ## Options
  - `:adapter` - The Deribit adapter process (required)
  - `:batch_size` - Number of channels per batch (default: 10)
  - `:batch_delay` - Delay between batches in ms (default: 200)

  ## Returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Subscribes to multiple channels in batches.

  ## Parameters
  - `manager` - The batch manager process
  - `channels` - List of channel names to subscribe to

  ## Returns
  `{:ok, request_id}` where request_id can be used to track progress.
  """
  @spec subscribe_batch(pid(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def subscribe_batch(manager, channels) when is_list(channels) do
    GenServer.call(manager, {:subscribe_batch, channels})
  end

  @doc """
  Gets the status of a batch subscription request.

  ## Parameters
  - `manager` - The batch manager process
  - `request_id` - The request ID returned by subscribe_batch/2

  ## Returns
  - `{:ok, status}` with completed/pending/total counts
  - `{:error, :not_found}` if request_id is invalid
  """
  @spec get_status(pid(), String.t()) :: {:ok, batch_status()} | {:error, :not_found}
  def get_status(manager, request_id) do
    GenServer.call(manager, {:get_status, request_id})
  end

  @doc """
  Cancels a batch subscription request.

  ## Parameters
  - `manager` - The batch manager process
  - `request_id` - The request ID to cancel

  ## Returns
  - `:ok` if cancelled successfully
  - `{:error, :not_found}` if request_id is invalid
  """
  @spec cancel_batch(pid(), String.t()) :: :ok | {:error, :not_found}
  def cancel_batch(manager, request_id) do
    GenServer.call(manager, {:cancel_batch, request_id})
  end

  @doc """
  Gets the status of all batch requests.

  ## Returns
  `{:ok, statuses}` where statuses is a map of request_id => status.
  """
  @spec get_all_statuses(pid()) :: {:ok, map()}
  def get_all_statuses(manager) do
    GenServer.call(manager, :get_all_statuses)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    state = %{
      adapter: Keyword.fetch!(opts, :adapter),
      batch_size: Keyword.get(opts, :batch_size, 10),
      batch_delay: Keyword.get(opts, :batch_delay, 200),
      requests: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe_batch, channels}, _from, state) do
    request_id = "req_#{[:positive] |> :erlang.unique_integer() |> Integer.to_string(16)}"
    total = length(channels)

    # Start processing immediately
    send(self(), {:process_batch, request_id, channels, 0})

    # Store request status
    state =
      put_in(state.requests[request_id], %{
        completed: 0,
        pending: total,
        total: total,
        cancelled: false,
        failed: false,
        error: nil
      })

    {:reply, {:ok, request_id}, state}
  end

  @impl true
  def handle_call({:get_status, request_id}, _from, state) do
    case state.requests[request_id] do
      nil -> {:reply, {:error, :not_found}, state}
      status -> {:reply, {:ok, Map.take(status, [:completed, :pending, :total, :failed, :error])}, state}
    end
  end

  @impl true
  def handle_call({:cancel_batch, request_id}, _from, state) do
    case state.requests[request_id] do
      nil -> {:reply, {:error, :not_found}, state}
      _ -> {:reply, :ok, put_in(state.requests[request_id][:cancelled], true)}
    end
  end

  @impl true
  def handle_call(:get_all_statuses, _from, state) do
    statuses =
      Map.new(state.requests, fn {id, status} ->
        {id, Map.take(status, [:completed, :pending, :total, :failed, :error])}
      end)

    {:reply, {:ok, statuses}, state}
  end

  @impl true
  def handle_info({:process_batch, request_id, channels, processed}, state) do
    if state.requests[request_id][:cancelled] or state.requests[request_id][:failed] or
         processed >= length(channels) do
      {:noreply, state}
    else
      batch = Enum.slice(channels, processed, state.batch_size)
      {:noreply, process_batch(state, request_id, batch, processed, channels)}
    end
  end

  # Attempts to subscribe a batch. On success, updates adapter and schedules
  # the next batch. On failure, marks the request as failed and stops.
  defp process_batch(state, request_id, batch, processed, channels) do
    case DeribitAdapter.subscribe(state.adapter, batch) do
      {:ok, updated_adapter} ->
        completed = min(processed + length(batch), length(channels))
        state = advance_batch(state, request_id, updated_adapter, completed)

        if completed < length(channels) do
          Process.send_after(self(), {:process_batch, request_id, channels, completed}, state.batch_delay)
        end

        state

      {:error, reason} ->
        Logger.warning("Batch subscribe failed for #{request_id}: #{inspect(reason)}")

        state
        |> put_in([:requests, request_id, :failed], true)
        |> put_in([:requests, request_id, :error], reason)
    end
  end

  # Updates state after a successful batch subscription
  defp advance_batch(state, request_id, updated_adapter, completed) do
    state
    |> Map.put(:adapter, updated_adapter)
    |> put_in([:requests, request_id, :completed], completed)
    |> update_in([:requests, request_id], &%{&1 | pending: &1.total - completed})
  end
end
