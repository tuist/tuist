defmodule Cache.Gradle.EventsPipelineTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]

  alias Cache.Gradle.EventsPipeline

  @server_url "http://localhost:4000"
  @webhook_url "#{@server_url}/webhooks/gradle-cache"

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker

  setup do
    stub(Cache.Authentication, :server_url, fn -> @server_url end)
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

      expect(Req, :request, fn request ->
        assert to_string(request.url) == @webhook_url
        assert request.method == :post

        decoded_body = JSON.decode!(request.body)

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

        headers = request.headers
        assert headers["content-type"] == ["application/json"]
        assert is_list(headers["x-cache-signature"])
        assert is_list(headers["x-cache-endpoint"])

        {:ok, %Req.Response{status: 202, body: ""}}
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
