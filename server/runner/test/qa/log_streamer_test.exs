defmodule Runner.QA.LogStreamerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Slipstream.Socket

  alias Runner.QA.LogStreamer

  defp create_socket(run_id) do
    assign(Slipstream.new_socket(), :run_id, run_id)
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

  describe "init/1" do
    test "initializes socket with run_id and connects" do
      config = [uri: "ws://localhost:4000/socket/websocket?token=test"]
      init_args = %{run_id: "test-run-id"}

      stub(Slipstream, :connect!, fn socket, ^config ->
        socket
      end)

      {:ok, socket} = LogStreamer.init({config, init_args})

      assert socket.assigns.run_id == "test-run-id"
    end
  end

  describe "handle_connect/1" do
    test "joins the QA logs topic" do
      socket = create_socket("test-run-id")

      {:ok, updated_socket} = LogStreamer.handle_connect(socket)

      assert updated_socket == socket
    end
  end

  describe "handle_join/3" do
    test "logs successful join" do
      socket = create_socket("test-run-id")
      topic = "qa_logs:test-run-id"

      {:ok, updated_socket} = LogStreamer.handle_join(topic, %{}, socket)

      assert updated_socket == socket
    end
  end

  describe "handle_cast/2" do
    test "attempts to send log message" do
      socket = create_socket("test-run-id")
      timestamp = DateTime.utc_now()

      {:noreply, updated_socket} =
        LogStreamer.handle_cast({:stream_log, "test message", "info", timestamp}, socket)

      # Socket should remain unchanged since push will fail (not joined)
      assert updated_socket == socket
    end
  end

  describe "handle_disconnect/2" do
    test "attempts to reconnect" do
      socket = create_socket("test-run-id")

      result = LogStreamer.handle_disconnect(:normal, socket)

      assert match?({:ok, _socket}, result) or match?({:stop, _reason, _socket}, result)
    end
  end

  describe "handle_topic_close/3" do
    test "attempts to rejoin topic" do
      socket = create_socket("test-run-id")
      topic = "qa_logs:test-run-id"

      result = LogStreamer.handle_topic_close(topic, :normal, socket)

      assert match?({:ok, _socket}, result) or match?({:stop, _reason, _socket}, result)
    end
  end
end
