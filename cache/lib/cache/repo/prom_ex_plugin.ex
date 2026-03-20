defmodule Cache.Repo.PromExPlugin do
  @moduledoc false

  use TuistCommon.Repo.PromExPlugin,
    name: :cache,
    metrics_prefix: [:cache, :repo, :pool],
    pool_metrics_event_name: [:cache, :repo, :pool, :metrics],
    repos: [
      {Cache.Repo, %{repo: "cache", database: "sqlite"}},
      {Cache.KeyValueRepo, %{repo: "key_value", database: "sqlite"}}
    ]
end
