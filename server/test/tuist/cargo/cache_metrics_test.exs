defmodule Tuist.Cargo.CacheMetricsTest do
  use ExUnit.Case, async: true

  alias Tuist.Cargo.CacheMetrics

  test "task misses and hit rate measure cache reuse, including cold and verification compilations" do
    metrics = %{version: 1, hits: 6, misses: 1, unconsulted: 2, verifications: 1}

    assert CacheMetrics.task_misses(metrics) == 4
    assert CacheMetrics.hit_rate(metrics) == 60.0
    assert {:ok, json} = CacheMetrics.encode(metrics)
    assert %{hits: 6, misses: 1, unconsulted: 2, verifications: 1} = CacheMetrics.read(%{cache_metrics: json})
  end

  test "a cold build has a zero hit rate, not an unavailable hit rate" do
    metrics = %{hits: 0, misses: 0, unconsulted: 20}
    assert CacheMetrics.task_misses(metrics) == 20
    assert CacheMetrics.hit_rate(metrics) == 0.0
  end

  test "verification rebuilds do not count as cache reuse" do
    assert CacheMetrics.hit_rate(%{hits: 0, verifications: 2}) == 0.0
    assert CacheMetrics.task_misses(%{verifications: 2, divergences: 1}) == 2
  end

  test "legacy counters remain usable and unrelated operations do not invent task outcomes" do
    assert CacheMetrics.hit_rate(%{hits: 19, misses: 1}) == 95.0
    assert CacheMetrics.hit_rate(%{hits: 0, misses: 0, downloaded_bytes: 100, prefetched_actions: 1}) == nil
    assert CacheMetrics.hit_rate(nil) == nil
    assert CacheMetrics.task_misses(%{}) == 0
  end
end
