defmodule Tuist.Marketing.StatsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.Stats

  setup :set_mimic_global

  setup do
    stub(Tuist.Cache, :last_24h_artifacts_count, fn -> 100 end)
    stub(Tuist.Builds, :last_24h_build_count, fn -> 200 end)
    stub(Tuist.Tests, :last_24h_test_case_run_count, fn -> 300 end)
    stub(Tuist.Tests, :last_24h_test_run_count, fn -> 400 end)
    stub(Tuist.Tests, :last_24h_flaky_test_case_run_count, fn -> 50 end)
    stub(CacheGlobe, :snapshot, fn -> CacheGlobe.empty() end)
    stub(Tuist.KeyValueStore, :get_or_update, fn [:marketing, :cache_globe], _opts, fun -> fun.() end)

    start_supervised!({Task.Supervisor, name: Stats.TaskSupervisor})

    pid = start_supervised!(Stats)
    # Wait for the initial poll to complete
    Process.sleep(50)

    %{stats_pid: pid}
  end

  describe "get_stats/0" do
    test "returns the current stats after polling" do
      stats = Stats.get_stats()

      assert stats.cache_artifacts_last_24h == 100
      assert stats.builds_last_24h == 200
      assert stats.test_case_runs_last_24h == 300
      assert stats.test_runs_last_24h == 400
      assert stats.flaky_tests_last_24h == 50
    end
  end

  describe "subscribe/0" do
    test "receives marketing_stats_updated messages after polling" do
      Stats.subscribe()

      send(Stats, :poll)

      assert_receive {:marketing_stats_updated, stats}, 1000
      assert stats.cache_artifacts_last_24h == 100
      assert stats.builds_last_24h == 200
      assert stats.test_case_runs_last_24h == 300
      assert stats.test_runs_last_24h == 400
      assert stats.flaky_tests_last_24h == 50
    end
  end

  test "globe updates use a separate topic from existing marketing pages" do
    Stats.subscribe()
    Stats.subscribe_globe()
    snapshot = %{CacheGlobe.empty() | downloads: 123, status: :available}
    stub(CacheGlobe, :snapshot, fn -> snapshot end)

    send(Stats, :poll_globe)

    assert_receive {:cache_globe_updated, ^snapshot}, 1000
    assert Stats.get_globe() == snapshot
    refute Map.has_key?(Stats.get_stats(), :globe)
  end

  test "a failed globe query keeps the last snapshot and the poller alive" do
    Stats.subscribe_globe()
    stub(CacheGlobe, :snapshot, fn -> raise "query unavailable" end)

    send(Stats, :poll_globe)

    assert_receive {:cache_globe_updated, %{status: :unavailable}}, 1000
    assert Stats.get_stats().cache_artifacts_last_24h == 100
  end
end
