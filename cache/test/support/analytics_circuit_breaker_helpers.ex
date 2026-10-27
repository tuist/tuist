defmodule Cache.AnalyticsCircuitBreakerTestHelpers do
  @moduledoc false

  import Mimic

  def setup_analytics_circuit_breaker(context \\ %{}) do
    breaker_name = {:test, System.unique_integer([:positive])}

    stub(Cache.AnalyticsCircuitBreaker, :accept_event?, fn key ->
      Cache.AnalyticsCircuitBreaker.accept_event?(key, breaker_name)
    end)

    stub(Cache.AnalyticsCircuitBreaker, :allow_request?, fn key ->
      Cache.AnalyticsCircuitBreaker.allow_request?(key, breaker_name)
    end)

    stub(Cache.AnalyticsCircuitBreaker, :record_success, fn key ->
      Cache.AnalyticsCircuitBreaker.record_success(key, breaker_name)
    end)

    stub(Cache.AnalyticsCircuitBreaker, :record_failure, fn key, label, reason ->
      Cache.AnalyticsCircuitBreaker.record_failure(key, label, reason, breaker_name)
    end)

    stub(Cache.AnalyticsCircuitBreaker, :req_fuse_options, fn key ->
      Cache.AnalyticsCircuitBreaker.req_fuse_options(key, breaker_name)
    end)

    stub(Cache.AnalyticsCircuitBreaker, :reset, fn key ->
      Cache.AnalyticsCircuitBreaker.reset(key, breaker_name)
    end)

    Map.put(context, :analytics_circuit_breaker_name, breaker_name)
  end
end
