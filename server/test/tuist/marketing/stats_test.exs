defmodule Tuist.Marketing.StatsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Marketing.Stats

  setup :set_mimic_global

  setup do
    stub(Tuist.Cache, :last_24h_artifacts_count, fn -> 100 end)
    stub(Tuist.Builds, :last_24h_build_count, fn -> 200 end)
    stub(Tuist.Tests, :last_24h_test_case_run_count, fn -> 300 end)
    stub(Tuist.Tests, :last_24h_test_run_count, fn -> 400 end)
    stub(Tuist.Tests, :last_24h_flaky_test_case_run_count, fn -> 50 end)

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

  test "followers retain broadcast snapshots and resume polling after leader departure", %{stats_pid: pid} do
    leader =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    :global.unregister_name({Stats, :poller})
    assert :global.register_name({Stats, :poller}, leader) == :yes

    on_exit(fn ->
      send(leader, :stop)
      :global.unregister_name({Stats, :poller})
    end)

    stub(Tuist.Cache, :last_24h_artifacts_count, fn -> raise "Follower polled the database" end)
    send(pid, {:marketing_stats_updated, %{cache_artifacts_last_24h: 900}})
    send(pid, :poll)
    assert Stats.get_stats() == %{cache_artifacts_last_24h: 900}
    ref = Process.monitor(leader)
    send(leader, :stop)
    assert_receive {:DOWN, ^ref, :process, ^leader, :normal}
    :global.sync()
    stub(Tuist.Cache, :last_24h_artifacts_count, fn -> 901 end)
    send(pid, :poll)
    assert Stats.get_stats().cache_artifacts_last_24h == 901
  end
end
