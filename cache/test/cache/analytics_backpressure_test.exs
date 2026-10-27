defmodule Cache.AnalyticsBackpressureTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]
  import Cache.BufferTestHelpers, only: [setup_xcode_events_buffer: 1]

  @server_url "http://localhost:4000"
  @webhook_url "#{@server_url}/webhooks/cache"

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker
  setup :setup_xcode_events_buffer

  setup do
    stub(Cache.Authentication, :server_url, fn -> @server_url end)
    stub(Cache.Config, :analytics_failure_threshold, fn -> 2 end)
    stub(Cache.Config, :analytics_cooldown_ms, fn -> 60_000 end)
    stub(Cache.Config, :analytics_receive_timeout_ms, fn -> 2_000 end)
    stub(Cache.Config, :analytics_pool_timeout_ms, fn -> 1_000 end)

    :ok
  end

  test "drops xcode analytics telemetry while the upstream circuit is open", %{
    xcode_events_buffer_name: xcode_events_buffer_name
  } do
    parent = self()
    request_ref = make_ref()

    stub(Req, :request, fn request ->
      send(parent, {:analytics_request, request_ref, to_string(request.url)})
      {:ok, %Req.Response{status: 502, body: "error code: 502"}}
    end)

    assert :ok = Cache.WebhookClient.signed_post(@webhook_url, "{}", "Xcode cache analytics")
    assert :ok = Cache.WebhookClient.signed_post(@webhook_url, "{}", "Xcode cache analytics")

    refute Cache.AnalyticsCircuitBreaker.accept_event?(@webhook_url)

    for index <- 1..1_000 do
      :telemetry.execute(
        [:cache, :xcode, :upload, :success],
        %{size: 1024},
        %{
          cas_id: "cas-#{index}",
          account_handle: "test-account",
          project_handle: "test-project"
        }
      )
    end

    assert OffBroadwayMemory.Buffer.length(xcode_events_buffer_name) == 0

    requests = collect_requests(request_ref, 100)

    assert requests == [@webhook_url, @webhook_url]
  end

  defp collect_requests(request_ref, timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_collect_requests(request_ref, deadline_ms, [])
  end

  defp do_collect_requests(request_ref, deadline_ms, acc) do
    remaining_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:analytics_request, ^request_ref, url} ->
        do_collect_requests(request_ref, deadline_ms, [url | acc])
    after
      remaining_ms ->
        Enum.reverse(acc)
    end
  end
end
