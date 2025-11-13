defmodule Cache.CasEventsPipelineTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.CasEventsPipeline

  setup do
    stub(Cache.Authentication, :server_url, fn -> "http://localhost:4000" end)
    :ok
  end

  describe "handle_message/3" do
    test "batches events by account_handle and project_handle" do
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

      result = CasEventsPipeline.handle_message(:default, message, %{})

      assert result.batch_key == {"test-account", "test-project"}
      assert result.batcher == :http
      assert result.data == event
    end
  end

  describe "handle_batch/4" do
    test "sends batch of events to the server successfully" do
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
        assert options[:url] ==
                 "http://localhost:4000/api/projects/#{account_handle}/#{project_handle}/cache/cas/events"

        assert options[:method] == :post

        body = options[:body]
        decoded_body = Jason.decode!(body)
        assert length(decoded_body["events"]) == 2
        assert Enum.at(decoded_body["events"], 0)["action"] == "upload"
        assert Enum.at(decoded_body["events"], 0)["size"] == 1024
        assert Enum.at(decoded_body["events"], 0)["cas_id"] == "abc123"
        assert Enum.at(decoded_body["events"], 1)["action"] == "download"
        assert Enum.at(decoded_body["events"], 1)["size"] == 2048
        assert Enum.at(decoded_body["events"], 1)["cas_id"] == "def456"

        headers = options[:headers]
        assert {"content-type", "application/json"} in headers
        assert Enum.any?(headers, fn {key, _value} -> key == "x-signature" end)

        {:ok, %{status: 200, body: ""}}
      end)

      result =
        CasEventsPipeline.handle_batch(
          :http,
          messages,
          %{batch_key: {account_handle, project_handle}},
          %{}
        )

      assert result == messages
    end
  end
end
