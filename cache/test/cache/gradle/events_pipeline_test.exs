defmodule Cache.Gradle.EventsPipelineTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Gradle.EventsPipeline

  setup :set_mimic_from_context

  setup do
    stub(Cache.Authentication, :server_url, fn -> "http://localhost:4000" end)
    :ok
  end

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
        EventsPipeline.handle_batch(
          :http,
          [message],
          %{batch_key: :default},
          %{}
        )

      assert result == [message]
    end

    test "sends batch of events to the gradle-cache webhook" do
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

      expect(Cache.WebhookClient, :signed_post, fn url, body, log_label ->
        assert url == "http://localhost:4000/webhooks/gradle-cache"
        assert log_label == "Gradle cache analytics"

        decoded_body = JSON.decode!(body)

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

        :ok
      end)

      result =
        EventsPipeline.handle_batch(
          :http,
          messages,
          %{batch_key: :default},
          %{}
        )

      assert result == messages
    end
  end
end
