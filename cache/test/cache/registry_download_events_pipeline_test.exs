defmodule Cache.RegistryDownloadEventsPipelineTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.RegistryDownloadEventsPipeline

  setup do
    stub(Cache.Authentication, :server_url, fn -> "http://localhost:4000" end)
    :ok
  end

  describe "async_push/1" do
    test "does not crash when pushing a valid event" do
      event = %{
        scope: "apple",
        name: "swift-argument-parser",
        version: "1.0.0"
      }

      assert :ok = RegistryDownloadEventsPipeline.async_push(event)
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

      result = RegistryDownloadEventsPipeline.handle_message(:default, message, %{})

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
        RegistryDownloadEventsPipeline.handle_batch(
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

      expect(Req, :request, fn options ->
        assert options[:url] == "http://localhost:4000/webhooks/registry"
        assert options[:method] == :post

        body = options[:body]
        decoded_body = Jason.decode!(body)
        assert length(decoded_body["events"]) == 2

        first = Enum.at(decoded_body["events"], 0)
        assert first["scope"] == "apple"
        assert first["name"] == "swift-argument-parser"
        assert first["version"] == "1.0.0"

        second = Enum.at(decoded_body["events"], 1)
        assert second["scope"] == "pointfreeco"
        assert second["name"] == "swift-composable-architecture"
        assert second["version"] == "0.52.0"

        headers = options[:headers]
        assert {"content-type", "application/json"} in headers
        assert Enum.any?(headers, fn {key, _value} -> key == "x-cache-signature" end)

        {:ok, %{status: 202, body: ""}}
      end)

      result =
        RegistryDownloadEventsPipeline.handle_batch(
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

      expect(Req, :request, fn options ->
        body = options[:body]

        expected_signature =
          :hmac
          |> :crypto.mac(:sha256, secret, body)
          |> Base.encode16(case: :lower)

        headers = options[:headers]
        {_, actual_signature} = Enum.find(headers, fn {key, _} -> key == "x-cache-signature" end)
        assert actual_signature == expected_signature

        {:ok, %{status: 200, body: ""}}
      end)

      RegistryDownloadEventsPipeline.handle_batch(
        :http,
        messages,
        %{batch_key: :default},
        %{}
      )
    end
  end
end
