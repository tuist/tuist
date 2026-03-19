defmodule Cache.Repo.PromExPlugin do
  @moduledoc """
  PromEx plugin for Cache DB pool metrics.
  """
  use PromEx.Plugin

  alias TuistCommon.Repo.PoolMetrics

  @pool_metrics_event [:cache, :repo, :pool, :metrics]
  @repos [
    {Cache.Repo, %{repo: "cache", database: "sqlite"}},
    {Cache.KeyValueRepo, %{repo: "key_value", database: "sqlite"}}
  ]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :cache_repo_pool_event_metrics,
        [
          counter(
            [:cache, :repo, :pool, :db_connection, :connected],
            event_name: [:db_connection, :connected],
            tags: [:tag],
            description: "The number of pool connections that have been established.",
            measurement: :count
          ),
          counter(
            [:cache, :repo, :pool, :db_connection, :disconnected],
            event_name: [:db_connection, :disconnected],
            tags: [:tag],
            description: "The number of pool connections that have been dropped.",
            measurement: :count
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 100)

    [
      Polling.build(
        :cache_repo_pool_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_cache_repo_pool_metrics_event, []},
        [
          last_value(
            [:cache, :repo, :pool, :checkout_queue, :length],
            event_name: @pool_metrics_event,
            tags: [:repo, :database],
            description: "The total number of requests waiting for a DB connection checkout.",
            measurement: :checkout_queue_length
          ),
          last_value(
            [:cache, :repo, :pool, :ready_conn, :count],
            event_name: @pool_metrics_event,
            tags: [:repo, :database],
            description: "The number of connections that are available to run queries.",
            measurement: :ready_conn_count
          ),
          last_value(
            [:cache, :repo, :pool, :size],
            event_name: @pool_metrics_event,
            tags: [:repo, :database],
            description: "The configured number of connections in the pool.",
            measurement: :pool_size
          )
        ]
      )
    ]
  end

  def execute_cache_repo_pool_metrics_event do
    Enum.each(@repos, fn {repo, metadata} -> emit_pool_metrics(repo, metadata) end)
  end

  defp emit_pool_metrics(repo, metadata) do
    if PoolMetrics.running?(repo) do
      case PoolMetrics.connection_pool_metrics(repo) do
        nil ->
          :ok

        measurements ->
          :telemetry.execute(@pool_metrics_event, measurements, metadata)
      end
    end
  end
end
