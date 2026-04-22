defmodule Cache.WebhookClientTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]

  alias Cache.WebhookClient

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker

  setup do
    stub(Cache.Config, :api_key, fn -> "test-api-key-secret" end)
    stub(Cache.Config, :cache_endpoint, fn -> "cache-eu-north.tuist.dev" end)
    stub(Cache.Config, :analytics_failure_threshold, fn -> 2 end)
    stub(Cache.Config, :analytics_cooldown_ms, fn -> 25 end)
    stub(Cache.Config, :analytics_receive_timeout_ms, fn -> 2_000 end)
    stub(Cache.Config, :analytics_pool_timeout_ms, fn -> 1_000 end)

    :ok
  end

  describe "signed_post/3" do
    test "uses bounded request timeouts" do
      url = unique_url()

      expect(Req, :request, fn request ->
        assert request.options[:receive_timeout] == 2_000
        assert request.options[:pool_timeout] == 1_000
        {:ok, %Req.Response{status: 202, body: ""}}
      end)

      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
    end

    test "opens the circuit after repeated failures and skips subsequent requests" do
      url = unique_url()

      expect(Req, :request, 2, fn _options ->
        {:ok, %Req.Response{status: 502, body: "error code: 502"}}
      end)

      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
      assert Cache.AnalyticsCircuitBreaker.accept_event?(url)

      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
      refute Cache.AnalyticsCircuitBreaker.accept_event?(url)

      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
    end

    test "allows a successful probe request after the cooldown window" do
      url = unique_url()

      Process.put(:req_request_count, 0)

      expect(Req, :request, 3, fn _options ->
        request_count = Process.get(:req_request_count, 0) + 1
        Process.put(:req_request_count, request_count)

        case request_count do
          1 -> {:ok, %Req.Response{status: 502, body: "error code: 502"}}
          2 -> {:ok, %Req.Response{status: 502, body: "error code: 502"}}
          3 -> {:ok, %Req.Response{status: 202, body: ""}}
        end
      end)

      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
      refute Cache.AnalyticsCircuitBreaker.accept_event?(url)

      Process.sleep(30)

      assert Cache.AnalyticsCircuitBreaker.accept_event?(url)
      assert :ok = WebhookClient.signed_post(url, "{}", "analytics test")
      assert Cache.AnalyticsCircuitBreaker.accept_event?(url)
    end
  end

  defp unique_url do
    "http://localhost:4000/webhooks/test-#{System.unique_integer([:positive])}"
  end
end
