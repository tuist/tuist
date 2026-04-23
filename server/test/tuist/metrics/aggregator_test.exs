defmodule Tuist.Metrics.AggregatorTest do
  use ExUnit.Case, async: false

  alias Tuist.Metrics.Aggregator

  setup do
    Aggregator.reset()
    :ok
  end

  describe "counter atomicity" do
    test "concurrent increments land every bump" do
      for_result =
        for _ <- 1..200 do
          Task.async(fn ->
            Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})
          end)
        end

      Task.await_many(for_result)
      snapshot = Aggregator.snapshot(1)
      counter = Enum.find(snapshot, &(&1.metric == "tuist_cli_invocations_total"))
      assert counter.value == 200
    end

    test "increments for distinct label tuples are tracked separately" do
      Aggregator.increment_counter(1, "tuist_xcode_cache_events_total", {"acme/app", "miss"}, 3)
      Aggregator.increment_counter(1, "tuist_xcode_cache_events_total", {"acme/app", "local_hit"}, 5)

      snapshot = Aggregator.snapshot(1)

      miss = Enum.find(snapshot, &(&1.labels == {"acme/app", "miss"}))
      hit = Enum.find(snapshot, &(&1.labels == {"acme/app", "local_hit"}))

      assert miss.value == 3
      assert hit.value == 5
    end
  end

  describe "histogram observations" do
    test "accumulates count, sum, and bucket distribution" do
      labels = {"acme/app", "App", "false", "success", "15.0", "14.0"}
      metric = "tuist_xcode_build_run_duration_seconds"

      Aggregator.observe_histogram(1, metric, labels, 0.25)
      Aggregator.observe_histogram(1, metric, labels, 1.5)
      Aggregator.observe_histogram(1, metric, labels, 45.0)

      _ = :sys.get_state(Aggregator)

      snapshot = Aggregator.snapshot(1)
      histogram = Enum.find(snapshot, &(&1.metric == metric))

      assert histogram.count == 3
      assert_in_delta histogram.sum, 46.75, 0.001

      # Bucket counts are cumulative: the 0.25 observation hits every bucket
      # from 0.5 onward; 1.5 hits from 2 onward; 45 hits only the 60+ buckets.
      bucket_counts = Map.new(histogram.buckets)
      assert Map.fetch!(bucket_counts, 0.5) == 1
      assert Map.fetch!(bucket_counts, 2) == 2
      assert Map.fetch!(bucket_counts, 60) == 3
    end

    test "observations after an account snapshot still land in later snapshots" do
      labels = {"acme/app", "App", "false", "success", "15.0", "14.0"}
      metric = "tuist_xcode_build_run_duration_seconds"

      Aggregator.observe_histogram(1, metric, labels, 1.0)
      _ = :sys.get_state(Aggregator)
      first = 1 |> Aggregator.snapshot() |> Enum.find(&(&1.metric == metric))
      assert first.count == 1

      Aggregator.observe_histogram(1, metric, labels, 2.0)
      _ = :sys.get_state(Aggregator)
      second = 1 |> Aggregator.snapshot() |> Enum.find(&(&1.metric == metric))
      assert second.count == 2
    end
  end

  describe "account isolation" do
    test "counters under different accounts do not leak into each other" do
      Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})
      Aggregator.increment_counter(2, "tuist_cli_invocations_total", {"beta/app", "test", "true", "failure"}, 4)

      assert [entry_1] =
               1 |> Aggregator.snapshot() |> Enum.filter(&(&1.metric == "tuist_cli_invocations_total"))

      assert [entry_2] =
               2 |> Aggregator.snapshot() |> Enum.filter(&(&1.metric == "tuist_cli_invocations_total"))

      assert entry_1.value == 1
      assert entry_2.value == 4
    end
  end

  describe "reset" do
    test "clears all counters and histograms" do
      Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})

      Aggregator.observe_histogram(
        1,
        "tuist_xcode_build_run_duration_seconds",
        {"acme/app", "App", "false", "success", "15.0", "14.0"},
        1.0
      )

      _ = :sys.get_state(Aggregator)
      assert Aggregator.snapshot(1) != []

      Aggregator.reset()
      assert Aggregator.snapshot(1) == []
    end
  end

  describe "table_info" do
    test "reports a positive size and memory once the table has entries" do
      assert %{size: 0, memory_words: words} = Aggregator.table_info()
      assert is_integer(words) and words >= 0

      Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})

      info = Aggregator.table_info()
      assert info.size >= 1
      assert info.memory_words > 0
    end
  end
end
