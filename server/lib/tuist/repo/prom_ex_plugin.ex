defmodule Tuist.Repo.PromExPlugin do
  @moduledoc ~s"""
  A prom_ex plugin that exposes metrics around the DB repo.
  """
  use PromEx.Plugin

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
            description: "The total number of queries that are in the queue waiting to be checked out",
            measurement: :checkout_queue_length
          ),
          last_value(
            [:tuist, :repo, :pool, :ready_conn, :count],
            event_name: Telemetry.event_name_repo_pool_metrics(),
            description: "The number of connections that are available to run queries.",
            measurement: :ready_conn_count
          )
        ]
      )
    ]
  end

  def execute_tuist_repo_pool_metrics_event do
    if Tuist.Repo.running?() do
      :telemetry.execute(
        Telemetry.event_name_repo_pool_metrics(),
        Tuist.Repo.connection_pool_metrics(),
        %{}
      )
    end
  end
end
