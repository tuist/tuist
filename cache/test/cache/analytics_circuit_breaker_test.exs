defmodule Cache.AnalyticsCircuitBreakerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Cache.AnalyticsCircuitBreakerTestHelpers, only: [setup_analytics_circuit_breaker: 1]

  @webhook_url "http://localhost:4000/webhooks/test"

  setup :set_mimic_from_context
  setup :setup_analytics_circuit_breaker

  setup do
    stub(Cache.Config, :analytics_failure_threshold, fn -> 2 end)
    stub(Cache.Config, :analytics_cooldown_ms, fn -> 25 end)
    :ok
  end

  test "stops accepting events while the fuse is blown and resumes after cooldown" do
    name = Cache.AnalyticsCircuitBreaker.req_fuse_options(@webhook_url)[:fuse_name]

    :ok = :fuse.melt(name)
    :ok = :fuse.melt(name)

    refute Cache.AnalyticsCircuitBreaker.accept_event?(@webhook_url)

    Process.sleep(30)

    assert Cache.AnalyticsCircuitBreaker.accept_event?(@webhook_url)
  end

  test "record_success resets accumulated failures" do
    name = Cache.AnalyticsCircuitBreaker.req_fuse_options(@webhook_url)[:fuse_name]

    :ok = :fuse.melt(name)
    :ok = Cache.AnalyticsCircuitBreaker.record_success(@webhook_url)
    :ok = :fuse.melt(name)

    assert Cache.AnalyticsCircuitBreaker.accept_event?(@webhook_url)
  end
end
