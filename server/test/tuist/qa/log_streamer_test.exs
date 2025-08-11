defmodule Tuist.QA.LogStreamerTest do
  use ExUnit.Case, async: true

  alias Tuist.QA.LogStreamer

  defp default_state(overrides \\ %{}) do
    Map.merge(
      %{
        server_url: "http://localhost:4000",
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 0,
        message_buffer: [],
        reconnect_attempts: 0,
        max_reconnect_attempts: 5,
        reconnect_delay: 1000
      },
      overrides
    )
  end

  describe "build_websocket_url/2" do
    test "converts http to ws" do
      url = LogStreamer.build_websocket_url("http://localhost:4000", "token123")
      assert url == "ws://localhost:4000/socket/websocket?token=token123"
    end

    test "converts https to wss" do
      url = LogStreamer.build_websocket_url("https://api.tuist.dev", "token123")
      assert url == "wss://api.tuist.dev/socket/websocket?token=token123"
    end
  end

  describe "handle_connect/2" do
    test "returns ok and schedules channel join" do
      state = default_state()

      {:ok, new_state} = LogStreamer.handle_connect(nil, state)
      assert new_state == state
    end
  end

  describe "handle_info/2" do
    test "sends join message for QA logs channel on :join_channel" do
      state = default_state()

      {:reply, {:text, message}, new_state} = LogStreamer.handle_info(:join_channel, state)

      decoded_message = JSON.decode!(message)

      assert decoded_message == %{
               "topic" => "qa_logs:test-run-id",
               "event" => "phx_join",
               "payload" => %{},
               "ref" => 1
             }

      assert new_state.ref_counter == 1
    end
  end

  describe "handle_cast/2" do
    test "sends log message when channel is joined" do
      state = default_state(%{channel_joined: true, ref_counter: 1})

      timestamp = DateTime.utc_now()

      {:reply, {:text, message}, new_state} =
        LogStreamer.handle_cast({:stream_log, "test message", "info", timestamp}, state)

      decoded_message = JSON.decode!(message)

      assert decoded_message == %{
               "topic" => "qa_logs:test-run-id",
               "event" => "log",
               "payload" => %{
                 "message" => "test message",
                 "level" => "info",
                 "timestamp" => DateTime.to_iso8601(timestamp)
               },
               "ref" => 2
             }

      assert new_state.ref_counter == 2
    end

    test "buffers log message when channel is not joined" do
      state = default_state(%{ref_counter: 1})

      timestamp = DateTime.utc_now()

      {:ok, new_state} =
        LogStreamer.handle_cast({:stream_log, "test message", "info", timestamp}, state)

      assert new_state.message_buffer == [{"test message", "info", timestamp}]
      assert new_state.ref_counter == 1
    end
  end

  describe "handle_frame/2" do
    test "marks channel as joined on successful reply" do
      state = default_state(%{ref_counter: 1})

      reply_message = %{
        "event" => "phx_reply",
        "payload" => %{"status" => "ok"}
      }

      {:ok, new_state} = LogStreamer.handle_frame({:text, JSON.encode!(reply_message)}, state)

      assert new_state.channel_joined == true
      assert new_state.reconnect_attempts == 0
    end

    test "ignores other messages" do
      state = default_state(%{ref_counter: 1})

      other_message = %{
        "event" => "other_event",
        "payload" => %{}
      }

      {:ok, new_state} = LogStreamer.handle_frame({:text, JSON.encode!(other_message)}, state)

      assert new_state == state
    end

    test "handles invalid JSON gracefully" do
      state = default_state(%{ref_counter: 1})

      {:ok, new_state} = LogStreamer.handle_frame({:text, "invalid json"}, state)

      assert new_state == state
    end
  end

  describe "handle_disconnect/2" do
    test "schedules reconnection and updates state" do
      state = default_state(%{channel_joined: true, ref_counter: 1})

      {:ok, new_state} = LogStreamer.handle_disconnect(%{reason: :normal}, state)

      assert new_state.channel_joined == false
      assert new_state.reconnect_attempts == 1
    end

    test "gives up after max reconnection attempts" do
      state =
        default_state(%{
          channel_joined: true,
          ref_counter: 1,
          reconnect_attempts: 5
        })

      {:ok, new_state} = LogStreamer.handle_disconnect(%{reason: :normal}, state)

      assert new_state.channel_joined == false
      assert new_state.reconnect_attempts == 5
    end
  end
end
