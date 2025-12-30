defmodule Runner.QA.LogStreamer do
  @moduledoc """
  WebSocket client for streaming QA logs to the server using Slipstream.
  """
  use Slipstream

  require Logger

  @topic_prefix "qa_logs:"

  def start_link(%{server_url: server_url, run_id: run_id, auth_token: auth_token}) do
    config = [
      uri: build_websocket_url(server_url, auth_token),
      reconnect_after_msec: [1000, 2000, 4000, 8000, 16_000]
    ]

    init_args = %{run_id: run_id}

    Slipstream.start_link(__MODULE__, {config, init_args})
  end

  def stream_log(pid, %{data: data, type: type, timestamp: timestamp}) do
    GenServer.cast(pid, {:stream_log, data, type, timestamp})
  end

  @impl Slipstream
  def init({config, init_args}) do
    socket = assign(new_socket(), :run_id, init_args.run_id)

    {:ok, connect!(socket, config)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    topic = @topic_prefix <> socket.assigns.run_id
    {:ok, join(socket, topic)}
  end

  @impl Slipstream
  def handle_join(topic, _join_response, socket) do
    Logger.debug("Successfully joined topic: #{topic}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_cast({:stream_log, data, type, timestamp}, socket) do
    topic = @topic_prefix <> socket.assigns.run_id

    payload = %{
      "data" => data,
      "type" => type,
      "timestamp" => DateTime.to_iso8601(timestamp)
    }

    case push(socket, topic, "log", payload) do
      {:ok, _ref} ->
        {:noreply, socket}

      {:error, :not_joined} ->
        Logger.debug("Cannot send log message: not joined to topic #{topic}")
        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to send log message: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.debug("WebSocket disconnected: #{inspect(reason)}")

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  @impl Slipstream
  def handle_topic_close(topic, reason, socket) do
    Logger.debug("Topic #{topic} closed: #{inspect(reason)}")

    case rejoin(socket, topic) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  def build_websocket_url(server_url, auth_token) do
    ws_protocol = if String.starts_with?(server_url, "https"), do: "wss", else: "ws"

    server_url
    |> String.replace(~r/^https?/, ws_protocol)
    |> Kernel.<>("/socket/websocket?token=#{auth_token}")
  end
end
