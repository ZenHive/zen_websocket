defmodule ZenWebsocket.Examples.Docs.ErrorHandling do
  @moduledoc """
  Error handling and retry patterns from Examples.md
  """

  use GenServer

  alias ZenWebsocket.Client

  require Logger

  @type state :: %{
          client: pid() | nil,
          url: String.t(),
          opts: keyword(),
          retry_count: non_neg_integer()
        }

  @doc """
  Starts a GenServer that manages a WebSocket connection with automatic retry.

  ## Parameters
  - `url` - WebSocket URL to connect to
  - `opts` - Connection options

  ## Returns
  `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(url, opts \\ []) do
    GenServer.start_link(__MODULE__, {url, opts}, name: __MODULE__)
  end

  @impl true
  @spec init({String.t(), keyword()}) :: {:ok, state()}
  def init({url, opts}) do
    case Client.connect(url, opts) do
      {:ok, client} ->
        {:ok, %{client: client, url: url, opts: opts, retry_count: 0}}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :retry_connect, 5_000)
        {:ok, %{client: nil, url: url, opts: opts, retry_count: 1}}
    end
  end

  @impl true
  @spec handle_info(term(), state()) :: {:noreply, state()}
  def handle_info(:retry_connect, %{url: url, opts: opts, retry_count: count} = state) do
    case Client.connect(url, opts) do
      {:ok, client} ->
        Logger.info("Reconnected successfully after #{count} attempts")
        {:noreply, %{state | client: client, retry_count: 0}}

      {:error, _reason} ->
        Process.send_after(self(), :retry_connect, 5_000)
        {:noreply, %{state | retry_count: count + 1}}
    end
  end

  def handle_info({:websocket_message, message}, state) do
    # Process incoming messages
    process_message(message)
    {:noreply, state}
  end

  def handle_info({:websocket_protocol_error, error}, state) do
    Logger.error("WebSocket protocol error: #{inspect(error)}")
    {:noreply, state}
  end

  def handle_info({:websocket_frame_error, error}, state) do
    Logger.error("WebSocket frame error: #{inspect(error)}")
    {:noreply, state}
  end

  def handle_info({:websocket_error, error}, state) do
    Logger.error("WebSocket error: #{inspect(error)}")
    {:noreply, state}
  end

  # Public API

  @doc """
  Sends a message through the WebSocket connection.

  ## Parameters
  - `message` - Message to send (must be a binary — use `Jason.encode!/1` for maps)

  ## Returns
  - `:ok` on success
  - `{:error, :not_connected}` if not connected
  - `{:error, {:not_connected, reason}}` if client is disconnected or process is down
  """
  @spec send_message(binary()) :: :ok | {:ok, map()} | {:error, term()}
  def send_message(message) when is_binary(message) do
    GenServer.call(__MODULE__, {:send_message, message})
  end

  @doc """
  Returns the current state of the error handler.

  ## Returns
  The internal state map including connection status and retry count.
  """
  @spec get_state() :: state()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), state()) :: {:reply, term(), state()}
  def handle_call({:send_message, _message}, _from, %{client: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_message, message}, _from, %{client: client} = state) do
    result = Client.send_message(client, message)
    {:reply, result, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Helper functions

  @spec process_message(term()) :: :ok
  defp process_message(message) do
    Logger.debug("Processing message: #{inspect(message)}")
    # Application-specific message processing
    :ok
  end
end
