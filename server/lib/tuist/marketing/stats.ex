defmodule Tuist.Marketing.Stats do
  @moduledoc """
  A GenServer that periodically polls ClickHouse for marketing page statistics
  and broadcasts updates via PubSub. LiveViews subscribe to receive fresh values
  without each page visit hitting the database.

  The cache-globe snapshot is **read-only** here: a single Oban worker
  (`Tuist.Marketing.Workers.CacheGlobeRefreshWorker`) refreshes ClickHouse into
  `KeyValueStore`, and every web replica only GETs that cache and broadcasts
  locally over PubSub.
  """

  use GenServer

  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe

  require Logger

  @topic "marketing_stats"
  @globe_topic "cache_globe"
  @poll_interval to_timeout(second: 5)
  @globe_poll_interval to_timeout(second: 30)
  @globe_cache_key [:marketing, :cache_globe]
  @globe_cache_opts [persist_across_deployments: true]

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

  def get_globe do
    if GenServer.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :get_globe)
    else
      CacheGlobe.empty()
    end
  end

  def subscribe_globe do
    Tuist.PubSub.subscribe(@globe_topic)
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
    send(self(), :poll_globe)
    {:ok, Map.put(stats, :globe, CacheGlobe.empty())}
  end

  @impl true
  def handle_call(:get_stats, _from, stats) do
    {:reply, Map.take(stats, Map.keys(@default_stats)), stats}
  end

  def handle_call(:get_globe, _from, stats) do
    {:reply, stats.globe, stats}
  end

  @impl true
  def handle_info(:poll, previous_stats) do
    stats = %{
      cache_artifacts_last_24h: Tuist.Cache.last_24h_artifacts_count(),
      builds_last_24h: Tuist.Builds.last_24h_build_count(),
      test_case_runs_last_24h: Tuist.Tests.last_24h_test_case_run_count(),
      test_runs_last_24h: Tuist.Tests.last_24h_test_run_count(),
      flaky_tests_last_24h: Tuist.Tests.last_24h_flaky_test_case_run_count(),
      globe: previous_stats.globe
    }

    stats = Map.merge(previous_stats, stats)
    Tuist.PubSub.broadcast(Map.take(stats, Map.keys(@default_stats)), @topic, :marketing_stats_updated)
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, stats}
  end

  def handle_info(:poll_globe, stats) do
    # Read-only: the Oban unique worker is the sole ClickHouse refresher.
    # Never call CacheGlobe.snapshot/0 or take a cross-replica Redis lock here.
    globe =
      case KeyValueStore.get(@globe_cache_key, @globe_cache_opts) do
        nil -> stats.globe
        cached -> cached
      end

    Tuist.PubSub.broadcast(globe, @globe_topic, :cache_globe_updated)
    Process.send_after(self(), :poll_globe, @globe_poll_interval)
    {:noreply, Map.put(stats, :globe, globe)}
  rescue
    error ->
      Logger.warning("Cache globe cache read unavailable: #{inspect(error)}")
      globe = %{stats.globe | status: :unavailable}
      Tuist.PubSub.broadcast(globe, @globe_topic, :cache_globe_updated)
      Process.send_after(self(), :poll_globe, @globe_poll_interval)
      {:noreply, Map.put(stats, :globe, globe)}
  end
end
