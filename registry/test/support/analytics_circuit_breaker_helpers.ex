defmodule TuistRegistry.AnalyticsCircuitBreakerTestHelpers do
  @moduledoc false

  import Mimic

  def setup_analytics_circuit_breaker(context \\ %{}) do
    breaker_name = {:test, System.unique_integer([:positive])}

    stub(TuistRegistry.AnalyticsCircuitBreaker, :accept_event?, fn key ->
      TuistRegistry.AnalyticsCircuitBreaker.accept_event?(key, breaker_name)
    end)

    stub(TuistRegistry.AnalyticsCircuitBreaker, :allow_request?, fn key ->
      TuistRegistry.AnalyticsCircuitBreaker.allow_request?(key, breaker_name)
    end)

    stub(TuistRegistry.AnalyticsCircuitBreaker, :record_success, fn key ->
      TuistRegistry.AnalyticsCircuitBreaker.record_success(key, breaker_name)
    end)

    stub(TuistRegistry.AnalyticsCircuitBreaker, :record_failure, fn key, label, reason ->
      TuistRegistry.AnalyticsCircuitBreaker.record_failure(key, label, reason, breaker_name)
    end)

    stub(TuistRegistry.AnalyticsCircuitBreaker, :req_fuse_options, fn key ->
      TuistRegistry.AnalyticsCircuitBreaker.req_fuse_options(key, breaker_name)
    end)

    stub(TuistRegistry.AnalyticsCircuitBreaker, :reset, fn key ->
      TuistRegistry.AnalyticsCircuitBreaker.reset(key, breaker_name)
    end)

    Map.put(context, :analytics_circuit_breaker_name, breaker_name)
  end
end
