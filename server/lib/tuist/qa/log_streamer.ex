defmodule Tuist.QA.LogStreamer do
  @moduledoc """
  WebSocket client for streaming QA logs to the server using WebSockex.
  """
  use WebSockex

  require Logger

  def start_link(%{server_url: server_url, run_id: run_id, auth_token: auth_token}) do
    ws_url = build_websocket_url(server_url, auth_token)

    state = %{
      server_url: server_url,
      run_id: run_id,
      auth_token: auth_token,
      channel_joined: false,
      ref_counter: 0,
      message_buffer: [],
      reconnect_attempts: 0,
      max_reconnect_attempts: 5,
      reconnect_delay: 1000
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

    {:reply, {:text, JSON.encode!(join_payload)}, %{state | ref_counter: state.ref_counter + 1}}
  end

  def handle_info(:reconnect, state) do
    ws_url = build_websocket_url(state.server_url, state.auth_token)
    {:reconnect, ws_url, state}
  end

  def handle_cast({:stream_log, message, level, timestamp}, state) do
    log_message = {message, level, timestamp}

    if state.channel_joined do
      send_log_message(log_message, state)
    else
      buffered_state = %{state | message_buffer: [log_message | state.message_buffer]}
      {:ok, buffered_state}
    end
  end

  def handle_frame({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"event" => "phx_reply", "payload" => %{"status" => "ok"}}} ->
        new_state = %{state | channel_joined: true, reconnect_attempts: 0}
        replay_buffered_messages(new_state)

      {:ok, _other} ->
        {:ok, state}

      {:error, _} ->
        {:ok, state}
    end
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.debug("WebSocket disconnected: #{inspect(reason)}")

    new_state = %{state | channel_joined: false}

    if new_state.reconnect_attempts < new_state.max_reconnect_attempts do
      delay = new_state.reconnect_delay * :math.pow(2, new_state.reconnect_attempts)
      Process.send_after(self(), :reconnect, trunc(delay))

      Logger.debug("Scheduling reconnection attempt #{new_state.reconnect_attempts + 1} in #{trunc(delay)}ms")
      {:ok, %{new_state | reconnect_attempts: new_state.reconnect_attempts + 1}}
    else
      Logger.warning("Max reconnection attempts reached, giving up")
      {:ok, new_state}
    end
  end

  def build_websocket_url(server_url, auth_token) do
    ws_protocol = if String.starts_with?(server_url, "https"), do: "wss", else: "ws"

    server_url
    |> String.replace(~r/^https?/, ws_protocol)
    |> Kernel.<>("/socket/websocket?token=#{auth_token}")
  end

  defp send_log_message({message, level, timestamp}, state) do
    log_payload = %{
      "topic" => "qa_logs:#{state.run_id}",
      "event" => "log",
      "payload" => %{
        "message" => message,
        "level" => level,
        "timestamp" => DateTime.to_iso8601(timestamp)
      },
      "ref" => next_ref(state)
    }

    {:reply, {:text, JSON.encode!(log_payload)}, %{state | ref_counter: state.ref_counter + 1}}
  end

  defp replay_buffered_messages(state) do
    case state.message_buffer do
      [] ->
        {:ok, state}

      messages ->
        reversed_messages = Enum.reverse(messages)
        Logger.debug("Replaying #{length(reversed_messages)} buffered messages")

        {:ok, %{state | message_buffer: []}}
    end
  end

  defp next_ref(state), do: state.ref_counter + 1
end
