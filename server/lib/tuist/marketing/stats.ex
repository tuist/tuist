defmodule Tuist.Marketing.Stats do
  @moduledoc """
  A GenServer that periodically polls ClickHouse for marketing page statistics
  and broadcasts updates via PubSub. LiveViews subscribe to receive fresh values
  without each page visit hitting the database.
  """

  use GenServer

  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe

  require Logger

  @topic "marketing_stats"
  @globe_topic "cache_globe"
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

  def handle_info(:poll_globe, %{globe_task: _ref} = stats), do: {:noreply, stats}

  def handle_info(:poll_globe, stats) do
    # Keep the public snapshot readable while the bounded query runs. One task
    # per poller, independent of the number of open conference displays.
    task =
      Task.Supervisor.async_nolink(__MODULE__.TaskSupervisor, fn ->
        KeyValueStore.get_or_update([:marketing, :cache_globe], [ttl: to_timeout(second: 25)], &CacheGlobe.snapshot/0)
      end)

    {:noreply, Map.put(stats, :globe_task, task.ref)}
  end

  def handle_info({ref, globe}, %{globe_task: ref} = stats) do
    Process.demonitor(ref, [:flush])
    Tuist.PubSub.broadcast(globe, @globe_topic, :cache_globe_updated)
    Process.send_after(self(), :poll_globe, to_timeout(second: 30))
    {:noreply, stats |> Map.put(:globe, globe) |> Map.delete(:globe_task)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{globe_task: ref} = stats) do
    Logger.warning("Cache globe statistics unavailable: #{inspect(reason)}")
    globe = %{stats.globe | status: :unavailable}
    Tuist.PubSub.broadcast(globe, @globe_topic, :cache_globe_updated)
    Process.send_after(self(), :poll_globe, to_timeout(second: 30))
    {:noreply, stats |> Map.put(:globe, globe) |> Map.delete(:globe_task)}
  end
end
