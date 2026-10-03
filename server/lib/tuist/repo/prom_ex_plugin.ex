defmodule Tuist.Repo.PromExPlugin do
  @moduledoc false

  use TuistCommon.Repo.PromExPlugin,
    name: :tuist,
    metrics_prefix: [:tuist, :repo, :pool],
    pool_metrics_event_name: Tuist.Telemetry.event_name_repo_pool_metrics(),
    repos: [
      {Tuist.Repo, %{repo: "postgres", database: "postgres"}},
      {Tuist.ClickHouseRepo, %{repo: "clickhouse_read", database: "clickhouse"}},
      {Tuist.IngestRepo, %{repo: "clickhouse_write", database: "clickhouse"}}
    ]

  @query_repos [
    {[:tuist, :repo, :query], "postgres"},
    {[:tuist, :click_house_repo, :query], "clickhouse_read"},
    {[:tuist, :ingest_repo, :query], "clickhouse_write"}
  ]
  @duration_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 15_000, 30_000]
  @query_event [:tuist, :database, :query]

  defoverridable event_metrics: 1, polling_metrics: 1

  def attach do
    :telemetry.attach_many(__MODULE__, Enum.map(@query_repos, &elem(&1, 0)), &__MODULE__.handle_query/4, @query_event)
  end

  def handle_query(event, measurements, metadata, target_event) do
    {_event, repo} = List.keyfind(@query_repos, event, 0)
    :telemetry.execute(target_event, measurements, %{repo: repo, result: query_result(metadata.result)})
  end

  @impl true
  def event_metrics(opts) do
    tags = [
      event_name: @query_event,
      tags: [:repo, :result]
    ]

    metrics = [
      counter(
        [:tuist, :repo, :query, :count],
        tags ++ [description: "Database query attempts, including failures before execution."]
      )
      | Enum.map([:total_time, :queue_time, :query_time, :decode_time], fn measurement ->
          distribution(
            [:tuist, :repo, :query, measurement, :milliseconds],
            tags ++
              [
                measurement: measurement,
                unit: {:native, :millisecond},
                reporter_options: [buckets: @duration_buckets],
                description: "Database #{measurement} in milliseconds; absent measurements are not recorded."
              ]
          )
        end)
    ]

    with_workload(super(opts) ++ [Event.build(:tuist_database_query_metrics, metrics)])
  end

  @impl true
  def polling_metrics(opts) do
    with_workload(super(opts))
  end

  defp with_workload(groups) do
    workload = to_string(Tuist.Environment.mode())

    Enum.map(groups, fn group ->
      metrics =
        Enum.map(group.metrics, fn metric ->
          tag_values = metric.tag_values

          %{
            metric
            | tags: metric.tags ++ [:workload],
              tag_values: fn metadata -> Map.put(tag_values.(metadata), :workload, workload) end
          }
        end)

      %{group | metrics: metrics}
    end)
  end

  defp query_result({:ok, _}), do: "ok"
  defp query_result({:error, %DBConnection.ConnectionError{reason: :queue_timeout}}), do: "queue_timeout"
  defp query_result({:error, %DBConnection.ConnectionError{}}), do: "connection_error"
  defp query_result({:error, _}), do: "error"
end
