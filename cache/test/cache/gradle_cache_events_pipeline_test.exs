defmodule Cache.GradleCacheEventsPipelineTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.GradleCacheEventsPipeline

  describe "handle_batch/4" do
    test "skips sending events when API key is not configured" do
      stub(Cache.Config, :api_key, fn -> nil end)

      event = %{
        action: "upload",
        size: 1024,
        cache_key: "gradle-cache-key-123",
        account_handle: "test-account",
        project_handle: "test-project"
      }

      message = %Broadway.Message{
        data: event,
        acknowledger: {Broadway.CallerAcknowledger, {self(), make_ref()}, :ok}
      }

      reject(&Req.request/1)

      result =
        GradleCacheEventsPipeline.handle_batch(
          :http,
          [message],
          %{batch_key: :default},
          %{}
        )

      assert result == [message]
    end

    test "sends batch of events to the gradle-cache webhook" do
      stub(Cache.Authentication, :server_url, fn -> "http://localhost:4000" end)

      account_handle = "test-account"
      project_handle = "test-project"

      events = [
        %{
          action: "upload",
          size: 1024,
          cache_key: "gradle-cache-key-123",
          account_handle: account_handle,
          project_handle: project_handle
        },
        %{
          action: "download",
          size: 2048,
          cache_key: "gradle-cache-key-456",
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
        assert options[:url] == "http://localhost:4000/webhooks/gradle-cache"
        assert options[:method] == :post

        decoded_body = Jason.decode!(options[:body])

        assert decoded_body["events"] == [
                 %{
                   "account_handle" => account_handle,
                   "project_handle" => project_handle,
                   "action" => "upload",
                   "size" => 1024,
                   "cache_key" => "gradle-cache-key-123"
                 },
                 %{
                   "account_handle" => account_handle,
                   "project_handle" => project_handle,
                   "action" => "download",
                   "size" => 2048,
                   "cache_key" => "gradle-cache-key-456"
                 }
               ]

        headers = options[:headers]
        assert {"content-type", "application/json"} in headers
        assert Enum.any?(headers, fn {key, _value} -> key == "x-cache-signature" end)

        {:ok, %{status: 202, body: ""}}
      end)

      result =
        GradleCacheEventsPipeline.handle_batch(
          :http,
          messages,
          %{batch_key: :default},
          %{}
        )

      assert result == messages
    end
  end
end
