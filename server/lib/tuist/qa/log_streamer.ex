defmodule Tuist.QA.LogStreamer do
  @moduledoc """
  WebSocket client for streaming QA logs to the server using WebSockex.
  """
  use WebSockex

  require Logger

  def start_link(%{server_url: server_url, run_id: run_id, auth_token: auth_token}) do
    ws_url = build_websocket_url(server_url, auth_token)

    state = %{
      run_id: run_id,
      auth_token: auth_token,
      channel_joined: false,
      ref_counter: 0
    }

    WebSockex.start_link(ws_url, __MODULE__, state)
  end

  def stream_log(pid, %{message: message, level: level, timestamp: timestamp}) do
    WebSockex.cast(pid, {:stream_log, message, level, timestamp})
  end

  def handle_connect(_conn, state) do
    send(self(), :join_channel)
    {:ok, state}
  end

  def handle_info(:join_channel, state) do
    join_payload = %{
      "topic" => "qa_logs:#{state.run_id}",
      "event" => "phx_join",
      "payload" => %{},
      "ref" => next_ref(state)
    }

    {:reply, {:text, Jason.encode!(join_payload)}, %{state | ref_counter: state.ref_counter + 1}}
  end

  def handle_cast({:stream_log, message, level, timestamp}, state) do
    if state.channel_joined do
      log_payload = %{
        "topic" => "qa_logs:#{state.run_id}",
        "event" => "log",
        "payload" => %{
          "message" => message,
          "level" => level,
          "timestamp" => timestamp
        },
        "ref" => next_ref(state)
      }

      {:reply, {:text, Jason.encode!(log_payload)}, %{state | ref_counter: state.ref_counter + 1}}
    else
      {:ok, state}
    end
  end

  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"event" => "phx_reply", "payload" => %{"status" => "ok"}}} ->
        {:ok, %{state | channel_joined: true}}

      {:ok, _other} ->
        {:ok, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.debug("WebSocket disconnected: #{inspect(reason)}")
    {:ok, state}
  end

  def build_websocket_url(server_url, auth_token) do
    ws_protocol = if String.starts_with?(server_url, "https"), do: "wss", else: "ws"

    server_url
    |> String.replace(~r/^https?/, ws_protocol)
    |> Kernel.<>("/socket/websocket?token=#{auth_token}")
  end

  defp next_ref(state), do: state.ref_counter + 1
end
