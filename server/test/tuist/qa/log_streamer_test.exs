defmodule Tuist.QA.LogStreamerTest do
  use ExUnit.Case, async: true

  alias Tuist.QA.LogStreamer

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
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 0
      }

      {:ok, new_state} = LogStreamer.handle_connect(nil, state)
      assert new_state == state
    end
  end

  describe "handle_info/2" do
    test "sends join message for QA logs channel on :join_channel" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 0
      }

      {:reply, {:text, message}, new_state} = LogStreamer.handle_info(:join_channel, state)

      decoded_message = Jason.decode!(message)

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
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: true,
        ref_counter: 1
      }

      timestamp = DateTime.utc_now()

      {:reply, {:text, message}, new_state} =
        LogStreamer.handle_cast({:stream_log, "test message", "info", timestamp}, state)

      decoded_message = Jason.decode!(message)

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

    test "drops log message when channel is not joined" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 1
      }

      timestamp = DateTime.utc_now()

      {:ok, new_state} =
        LogStreamer.handle_cast({:stream_log, "test message", "info", timestamp}, state)

      assert new_state == state
    end
  end

  describe "handle_frame/2" do
    test "marks channel as joined on successful reply" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 1
      }

      reply_message = %{
        "event" => "phx_reply",
        "payload" => %{"status" => "ok"}
      }

      {:ok, new_state} = LogStreamer.handle_frame({:text, Jason.encode!(reply_message)}, state)

      assert new_state.channel_joined == true
    end

    test "ignores other messages" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 1
      }

      other_message = %{
        "event" => "other_event",
        "payload" => %{}
      }

      {:ok, new_state} = LogStreamer.handle_frame({:text, Jason.encode!(other_message)}, state)

      assert new_state == state
    end

    test "handles invalid JSON gracefully" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: false,
        ref_counter: 1
      }

      {:ok, new_state} = LogStreamer.handle_frame({:text, "invalid json"}, state)

      assert new_state == state
    end
  end

  describe "handle_disconnect/2" do
    test "logs disconnection reason" do
      state = %{
        run_id: "test-run-id",
        auth_token: "test-token",
        channel_joined: true,
        ref_counter: 1
      }

      {:ok, new_state} = LogStreamer.handle_disconnect(%{reason: :normal}, state)

      assert new_state == state
    end
  end
end
