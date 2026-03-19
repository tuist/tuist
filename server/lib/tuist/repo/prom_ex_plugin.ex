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
end
