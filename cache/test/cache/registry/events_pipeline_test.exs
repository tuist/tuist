defmodule Cache.Registry.EventsPipelineTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]

  alias Cache.Registry.EventsPipeline

  @server_url "http://localhost:4000"
  @webhook_url "#{@server_url}/webhooks/registry"

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker

  setup do
    stub(Cache.Authentication, :server_url, fn -> @server_url end)
    :ok
  end

  describe "async_push/1" do
    test "does not crash when pushing a valid event" do
      event = %{
        scope: "apple",
        name: "swift-argument-parser",
        version: "1.0.0"
      }

      assert :ok = EventsPipeline.async_push(event)
    end
  end

  describe "handle_message/3" do
    test "sends events to http batcher with default batch key" do
      event = %{
        scope: "apple",
        name: "swift-argument-parser",
        version: "1.0.0"
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
        %{scope: "apple", name: "swift-argument-parser", version: "1.0.0"}
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

    test "sends batch of events to the registry webhook with correct payload shape" do
      events = [
        %{scope: "apple", name: "swift-argument-parser", version: "1.0.0"},
        %{scope: "pointfreeco", name: "swift-composable-architecture", version: "0.52.0"}
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

        first = Enum.at(decoded_body["events"], 0)
        assert first["scope"] == "apple"
        assert first["name"] == "swift-argument-parser"
        assert first["version"] == "1.0.0"

        second = Enum.at(decoded_body["events"], 1)
        assert second["scope"] == "pointfreeco"
        assert second["name"] == "swift-composable-architecture"
        assert second["version"] == "0.52.0"

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

    test "computes correct HMAC-SHA256 signature" do
      secret = "test-api-key-secret"
      stub(Cache.Config, :api_key, fn -> secret end)

      events = [
        %{scope: "apple", name: "swift-argument-parser", version: "1.0.0"}
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

        body = request.body

        expected_signature =
          :hmac
          |> :crypto.mac(:sha256, secret, body)
          |> Base.encode16(case: :lower)

        headers = request.headers
        [actual_signature] = headers["x-cache-signature"]
        assert actual_signature == expected_signature

        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      EventsPipeline.handle_batch(
        :http,
        messages,
        %{batch_key: :default},
        %{}
      )
    end
  end
end
