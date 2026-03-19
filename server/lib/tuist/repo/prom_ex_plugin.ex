defmodule Tuist.Repo.PromExPlugin do
  @moduledoc ~s"""
  A prom_ex plugin that exposes metrics around the DB repo.
  """
  use PromEx.Plugin

  alias Tuist.Repo.PoolMetrics
  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_repo_pool_event_metrics,
        [
          counter(
            [:tuist, :repo, :pool, :db_connection, :connected],
            event_name: [:db_connection, :connected],
            tags: [:tag],
            description: "The number of pool connections that have been established.",
            measurement: :count
          ),
          counter(
            [:tuist, :repo, :pool, :db_connection, :disconnected],
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
        :tuist_repo_pool_manual_metrics,
        poll_rate,
        {__MODULE__, :execute_tuist_repo_pool_metrics_event, []},
        [
          last_value(
            [:tuist, :repo, :pool, :checkout_queue, :length],
            event_name: Telemetry.event_name_repo_pool_metrics(),
            tags: [:repo, :database],
            description: "The total number of queries that are in the queue waiting to be checked out",
            measurement: :checkout_queue_length
          ),
          last_value(
            [:tuist, :repo, :pool, :ready_conn, :count],
            event_name: Telemetry.event_name_repo_pool_metrics(),
            tags: [:repo, :database],
            description: "The number of connections that are available to run queries.",
            measurement: :ready_conn_count
          ),
          last_value(
            [:tuist, :repo, :pool, :size],
            event_name: Telemetry.event_name_repo_pool_metrics(),
            tags: [:repo, :database],
            description: "The configured number of connections in the pool.",
            measurement: :pool_size
          )
        ]
      )
    ]
  end

  def execute_tuist_repo_pool_metrics_event do
    Enum.each(PoolMetrics.repos(), &emit_pool_metrics/1)
  end

  defp emit_pool_metrics(repo) do
    if PoolMetrics.running?(repo) do
      case PoolMetrics.connection_pool_metrics(repo) do
        nil ->
          :ok

        measurements ->
          :telemetry.execute(
            Telemetry.event_name_repo_pool_metrics(),
            measurements,
            PoolMetrics.telemetry_metadata(repo)
          )
      end
    end
  end
end
