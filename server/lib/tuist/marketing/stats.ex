defmodule Tuist.Marketing.Stats do
  @moduledoc """
  A GenServer that periodically polls ClickHouse for marketing page statistics
  and broadcasts updates via PubSub. LiveViews subscribe to receive fresh values
  without each page visit hitting the database.

  The last polled stats live in a protected ETS table so readers never wait on
  a poll that is stuck on slow ClickHouse queries.
  """

  use GenServer

  @topic "marketing_stats"
  @poll_interval to_timeout(second: 5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @default_stats %{
    cache_artifacts_last_24h: 0,
    builds_last_24h: 0,
    test_case_runs_last_24h: 0,
    test_runs_last_24h: 0,
    flaky_tests_last_24h: 0
  }

  def get_stats do
    case :ets.lookup(__MODULE__, :stats) do
      [{:stats, stats}] -> stats
      [] -> @default_stats
    end
  rescue
    ArgumentError -> @default_stats
  end

  def subscribe do
    Tuist.PubSub.subscribe(@topic)
  end

  @impl true
  def init(_) do
    :ets.new(__MODULE__, [:named_table, :protected, read_concurrency: true])
    send(self(), :poll)
    {:ok, nil}
  end

  @impl true
  def handle_info(:poll, state) do
    stats = %{
      cache_artifacts_last_24h: Tuist.Cache.last_24h_artifacts_count(),
      builds_last_24h: Tuist.Builds.last_24h_build_count(),
      test_case_runs_last_24h: Tuist.Tests.last_24h_test_case_run_count(),
      test_runs_last_24h: Tuist.Tests.last_24h_test_run_count(),
      flaky_tests_last_24h: Tuist.Tests.last_24h_flaky_test_case_run_count()
    }

    :ets.insert(__MODULE__, {:stats, stats})
    Tuist.PubSub.broadcast(stats, @topic, :marketing_stats_updated)
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, state}
  end
end
