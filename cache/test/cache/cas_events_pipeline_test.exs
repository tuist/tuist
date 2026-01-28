defmodule Cache.CASEventsPipelineTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.CASEventsPipeline

  setup do
    stub(Cache.Authentication, :server_url, fn -> "http://localhost:4000" end)
    :ok
  end

  describe "handle_message/3" do
    test "sends events to http batcher with default batch key" do
      event = %{
        action: "upload",
        size: 1024,
        cas_id: "abc123",
        account_handle: "test-account",
        project_handle: "test-project"
      }

      message = %Broadway.Message{
        data: event,
        acknowledger: {Broadway.CallerAcknowledger, {self(), make_ref()}, :ok}
      }

      result = CASEventsPipeline.handle_message(:default, message, %{})

      assert result.batch_key == :default
      assert result.batcher == :http
      assert result.data == event
    end
  end

  describe "handle_batch/4" do
    test "skips sending events when API key is not configured" do
      stub(Cache.Config, :api_key, fn -> nil end)

      events = [
        %{
          action: "upload",
          size: 1024,
          cas_id: "abc123",
          account_handle: "test-account",
          project_handle: "test-project"
        }
      ]

      messages =
        Enum.map(events, fn event ->
          %Broadway.Message{
            data: event,
            acknowledger: {Broadway.CallerAcknowledger, {self(), make_ref()}, :ok}
          }
        end)

      reject(&Req.request/1)

      result =
        CASEventsPipeline.handle_batch(
          :http,
          messages,
          %{batch_key: :default},
          %{}
        )

      assert result == messages
    end

    test "sends batch of events to the cache webhook successfully" do
      account_handle = "test-account"
      project_handle = "test-project"

      events = [
        %{
          action: "upload",
          size: 1024,
          cas_id: "abc123",
          account_handle: account_handle,
          project_handle: project_handle
        },
        %{
          action: "download",
          size: 2048,
          cas_id: "def456",
          account_handle: account_handle,
          project_handle: project_handle
        }
      ]

      messages =
        Enum.map(events, fn event ->
          %Broadway.Message{
            data: event,
            acknowledger: {Broadway.CallerAcknowledger, {self(), make_ref()}, :ok}
          }
        end)

      expect(Req, :request, fn options ->
        assert options[:url] == "http://localhost:4000/webhooks/cache"
        assert options[:method] == :post

        body = options[:body]
        decoded_body = Jason.decode!(body)
        assert length(decoded_body["events"]) == 2

        # Verify first event includes handles
        assert Enum.at(decoded_body["events"], 0)["account_handle"] == account_handle
        assert Enum.at(decoded_body["events"], 0)["project_handle"] == project_handle
        assert Enum.at(decoded_body["events"], 0)["action"] == "upload"
        assert Enum.at(decoded_body["events"], 0)["size"] == 1024
        assert Enum.at(decoded_body["events"], 0)["cas_id"] == "abc123"

        # Verify second event includes handles
        assert Enum.at(decoded_body["events"], 1)["account_handle"] == account_handle
        assert Enum.at(decoded_body["events"], 1)["project_handle"] == project_handle
        assert Enum.at(decoded_body["events"], 1)["action"] == "download"
        assert Enum.at(decoded_body["events"], 1)["size"] == 2048
        assert Enum.at(decoded_body["events"], 1)["cas_id"] == "def456"

        headers = options[:headers]
        assert {"content-type", "application/json"} in headers
        assert Enum.any?(headers, fn {key, _value} -> key == "x-cache-signature" end)

        {:ok, %{status: 202, body: ""}}
      end)

      result =
        CASEventsPipeline.handle_batch(
          :http,
          messages,
          %{batch_key: :default},
          %{}
        )

      assert result == messages
    end
  end
end
