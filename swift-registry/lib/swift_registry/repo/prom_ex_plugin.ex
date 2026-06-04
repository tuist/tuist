defmodule SwiftRegistry.Repo.PromExPlugin do
  @moduledoc false

  use TuistCommon.Repo.PromExPlugin,
    name: :swift_registry,
    metrics_prefix: [:swift_registry, :repo, :pool],
    pool_metrics_event_name: [:swift_registry, :repo, :pool, :metrics],
    repos: [
      {SwiftRegistry.Repo, %{repo: "swift_registry", database: "sqlite"}}
    ]
end
