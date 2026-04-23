defmodule Tuist.MetricsTest do
  use ExUnit.Case, async: false

  alias Tuist.Metrics
  alias Tuist.Metrics.Aggregator

  setup do
    Aggregator.reset()
    :ok
  end

  describe "counter recording" do
    test "increments a counter and snapshots it" do
      Metrics.increment_counter(42, "tuist_xcode_cache_events_total", {"acme/app", "local_hit"})
      Metrics.increment_counter(42, "tuist_xcode_cache_events_total", {"acme/app", "local_hit"})

      snapshot = Metrics.snapshot(42)

      assert Enum.any?(snapshot, fn entry ->
               entry.type == :counter and
                 entry.metric == "tuist_xcode_cache_events_total" and
                 entry.labels == {"acme/app", "local_hit"} and
                 entry.value == 2
             end)
    end

    test "keeps counters isolated across accounts" do
      Metrics.increment_counter(1, "tuist_xcode_cache_events_total", {"acme/app", "miss"})
      Metrics.increment_counter(2, "tuist_xcode_cache_events_total", {"acme/app", "miss"})

      assert length(Metrics.snapshot(1)) == 1
      assert length(Metrics.snapshot(2)) == 1
    end
  end

  describe "histogram recording" do
    test "counts observations and accumulates sum and buckets" do
      labels = {"acme/app", "App", "false", "success", "15.0", "14.0"}

      Metrics.observe_histogram(1, "tuist_xcode_build_run_duration_seconds", labels, 0.3)
      Metrics.observe_histogram(1, "tuist_xcode_build_run_duration_seconds", labels, 2.0)

      # Wait for cast to be processed.
      _ = :sys.get_state(Aggregator)

      [entry] =
        1
        |> Metrics.snapshot()
        |> Enum.filter(&(&1.metric == "tuist_xcode_build_run_duration_seconds"))

      assert entry.count == 2
      assert_in_delta entry.sum, 2.3, 1.0e-6

      # 0.3 falls in the first bucket (0.5), 2.0 falls in 2+ buckets.
      bucket_map = Map.new(entry.buckets)
      assert Map.get(bucket_map, 0.5) == 1
      assert Map.get(bucket_map, 1) == 1
      assert Map.get(bucket_map, 2) == 2
      assert Map.get(bucket_map, 5) == 2
    end
  end

  describe "merge/2" do
    test "adds counter values for the same labels" do
      a = [%{metric: "m", type: :counter, labels: {"p"}, value: 3}]
      b = [%{metric: "m", type: :counter, labels: {"p"}, value: 5}]

      assert [%{value: 8}] = Metrics.merge(a, b)
    end

    test "keeps distinct label sets separate" do
      a = [%{metric: "m", type: :counter, labels: {"p1"}, value: 3}]
      b = [%{metric: "m", type: :counter, labels: {"p2"}, value: 5}]

      merged = a |> Metrics.merge(b) |> Enum.sort_by(& &1.labels)
      assert [%{labels: {"p1"}, value: 3}, %{labels: {"p2"}, value: 5}] = merged
    end

    test "adds histogram sums and bucket counts" do
      a = %{
        metric: "h",
        type: :histogram,
        labels: {"p"},
        count: 2,
        sum: 1.5,
        buckets: [{0.5, 1}, {1, 1}, {2, 2}]
      }

      b = %{
        metric: "h",
        type: :histogram,
        labels: {"p"},
        count: 3,
        sum: 4.0,
        buckets: [{0.5, 0}, {1, 1}, {2, 3}]
      }

      [merged] = Metrics.merge([a], [b])

      assert merged.count == 5
      assert merged.sum == 5.5
      assert merged.buckets == [{0.5, 1}, {1, 2}, {2, 5}]
    end

    test "merges histograms whose bucket layouts differ" do
      # This can happen during a rolling deploy that changes the schema — one
      # node still reports the old bucket set while another has the new one.
      # Merging by bound (not by list position) keeps both nodes' bucket
      # counts rather than silently dropping the tail of the longer list.
      a = %{
        metric: "h",
        type: :histogram,
        labels: {"p"},
        count: 3,
        sum: 2.0,
        buckets: [{0.5, 1}, {1, 2}, {5, 3}]
      }

      b = %{
        metric: "h",
        type: :histogram,
        labels: {"p"},
        count: 4,
        sum: 3.0,
        buckets: [{0.5, 0}, {1, 1}, {2, 3}, {5, 4}, {10, 4}]
      }

      [merged] = Metrics.merge([a], [b])

      assert merged.count == 7
      assert merged.sum == 5.0

      bucket_map = Map.new(merged.buckets)
      # Bounds present in both sides are summed:
      assert Map.fetch!(bucket_map, 0.5) == 1
      assert Map.fetch!(bucket_map, 1) == 3
      assert Map.fetch!(bucket_map, 5) == 7
      # Bounds only on one side are preserved (not truncated away):
      assert Map.fetch!(bucket_map, 2) == 3
      assert Map.fetch!(bucket_map, 10) == 4
      # Bounds stay sorted.
      assert merged.buckets == Enum.sort_by(merged.buckets, &elem(&1, 0))
    end
  end
end
