defmodule SwiftRegistry.AnalyticsCircuitBreakerTestHelpers do
  @moduledoc false

  import Mimic

  def setup_analytics_circuit_breaker(context \\ %{}) do
    breaker_name = {:test, System.unique_integer([:positive])}

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :accept_event?, fn key ->
      SwiftRegistry.AnalyticsCircuitBreaker.accept_event?(key, breaker_name)
    end)

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :allow_request?, fn key ->
      SwiftRegistry.AnalyticsCircuitBreaker.allow_request?(key, breaker_name)
    end)

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :record_success, fn key ->
      SwiftRegistry.AnalyticsCircuitBreaker.record_success(key, breaker_name)
    end)

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :record_failure, fn key, label, reason ->
      SwiftRegistry.AnalyticsCircuitBreaker.record_failure(key, label, reason, breaker_name)
    end)

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :req_fuse_options, fn key ->
      SwiftRegistry.AnalyticsCircuitBreaker.req_fuse_options(key, breaker_name)
    end)

    stub(SwiftRegistry.AnalyticsCircuitBreaker, :reset, fn key ->
      SwiftRegistry.AnalyticsCircuitBreaker.reset(key, breaker_name)
    end)

    Map.put(context, :analytics_circuit_breaker_name, breaker_name)
  end
end
