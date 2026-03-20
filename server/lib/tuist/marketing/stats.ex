defmodule Tuist.Marketing.Stats do
  @moduledoc """
  A GenServer that periodically polls ClickHouse for marketing page statistics
  and broadcasts updates via PubSub. LiveViews subscribe to receive fresh values
  without each page visit hitting the database.
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
    if GenServer.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :get_stats)
    else
      @default_stats
    end
  end

  def subscribe do
    Tuist.PubSub.subscribe(@topic)
  end

  @impl true
  def init(_) do
    stats = %{
      cache_artifacts_last_24h: 0,
      builds_last_24h: 0,
      test_case_runs_last_24h: 0,
      test_runs_last_24h: 0,
      flaky_tests_last_24h: 0
    }

    send(self(), :poll)
    {:ok, stats}
  end

  @impl true
  def handle_call(:get_stats, _from, stats) do
    {:reply, stats, stats}
  end

  @impl true
  def handle_info(:poll, _stats) do
    stats = %{
      cache_artifacts_last_24h: Tuist.Cache.last_24h_artifacts_count(),
      builds_last_24h: Tuist.Builds.last_24h_build_count(),
      test_case_runs_last_24h: Tuist.Tests.last_24h_test_case_run_count(),
      test_runs_last_24h: Tuist.Tests.last_24h_test_run_count(),
      flaky_tests_last_24h: Tuist.Tests.last_24h_flaky_test_case_run_count()
    }

    Tuist.PubSub.broadcast(stats, @topic, :marketing_stats_updated)
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, stats}
  end
end
