defmodule TuistRegistry.Repo.PromExPlugin do
  @moduledoc false

  use TuistCommon.Repo.PromExPlugin,
    name: :tuist_registry,
    metrics_prefix: [:tuist_registry, :repo, :pool],
    pool_metrics_event_name: [:tuist_registry, :repo, :pool, :metrics],
    repos: [
      {TuistRegistry.Repo, %{repo: "tuist_registry", database: "sqlite"}}
    ]
end
