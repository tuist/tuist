defmodule Cache.Xcode.EventsPipelineTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]

  alias Cache.Xcode.EventsPipeline

  @server_url "http://localhost:4000"
  @webhook_url "#{@server_url}/webhooks/cache"

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker

  setup do
    stub(Cache.Authentication, :server_url, fn -> @server_url end)
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

      result = EventsPipeline.handle_message(:default, message, %{})

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
        EventsPipeline.handle_batch(
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

      expect(Req, :request, fn request ->
        assert to_string(request.url) == @webhook_url
        assert request.method == :post

        body = request.body
        decoded_body = JSON.decode!(body)
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
