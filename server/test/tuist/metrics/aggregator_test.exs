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
      labels = {"acme/app", "App", "false", "success"}
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
      labels = {"acme/app", "App", "false", "success"}
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
        {"acme/app", "App", "false", "success"},
        1.0
      )

      _ = :sys.get_state(Aggregator)
      assert Aggregator.snapshot(1) != []

      Aggregator.reset()
      assert Aggregator.snapshot(1) == []
    end
  end

  describe "table_info" do
    test "reports size + memory in words and bytes once the table has entries" do
      assert %{size: 0, memory_words: words, memory_bytes: bytes} = Aggregator.table_info()
      assert is_integer(words) and words >= 0
      assert is_integer(bytes) and bytes == words * :erlang.system_info(:wordsize)

      Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})

      info = Aggregator.table_info()
      assert info.size >= 1
      assert info.memory_words > 0
      assert info.memory_bytes == info.memory_words * :erlang.system_info(:wordsize)
    end
  end

  describe "eviction of stale accounts" do
    setup do
      ref = make_ref()
      test_pid = self()
      event = Aggregator.eviction_event()
      handler_id = {__MODULE__, :eviction, ref}

      :telemetry.attach(
        handler_id,
        event,
        fn ^event, measurements, metadata, _ ->
          send(test_pid, {ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, ref: ref}
    end

    test "does not touch accounts scraped within the staleness window", %{ref: ref} do
      Aggregator.increment_counter(1, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})
      # Refresh its scrape marker before the sweep fires.
      Aggregator.record_scrape(1)

      send(Process.whereis(Aggregator), :evict_stale)

      refute_receive {^ref, _, _}, 200
      assert Aggregator.snapshot(1) != []
    end

    test "drops counters and histograms for accounts whose scrape stopped", %{ref: ref} do
      Aggregator.increment_counter(2, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})

      Aggregator.observe_histogram(
        2,
        "tuist_xcode_build_run_duration_seconds",
        {"acme/app", "App", "false", "success"},
        1.0
      )

      _ = :sys.get_state(Aggregator)

      # Rewind the account's last-seen timestamp past the staleness cutoff
      # rather than sleeping, keeping the test fast and deterministic.
      :ets.insert(:tuist_metrics_last_scrape, {2, System.monotonic_time(:millisecond) - to_timeout(hour: 1)})

      send(Process.whereis(Aggregator), :evict_stale)

      assert_receive {^ref, %{accounts: 1, rows: rows}, _meta}, 1_000
      assert rows >= 1

      assert Aggregator.snapshot(2) == []
    end
  end

  describe "periodic stats telemetry" do
    test "emits a stats event with size and memory measurements" do
      ref = make_ref()
      test_pid = self()
      event = Aggregator.stats_event()
      handler_id = {__MODULE__, ref}

      :telemetry.attach(
        handler_id,
        event,
        fn ^event, measurements, metadata, _ ->
          send(test_pid, {ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Aggregator.increment_counter(7, "tuist_cli_invocations_total", {"acme/app", "generate", "false", "success"})

      # Drive the handler directly — the periodic timer uses a 60s interval,
      # which won't fire inside a unit test run. Sending :emit_stats exercises
      # the same code path the timer does.
      send(Process.whereis(Aggregator), :emit_stats)

      assert_receive {^ref, %{size: size, memory_bytes: memory_bytes, memory_words: memory_words}, _meta}, 1_000
      assert size >= 1
      assert memory_words > 0
      assert memory_bytes == memory_words * :erlang.system_info(:wordsize)
    end
  end
end
