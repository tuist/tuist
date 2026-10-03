defmodule Tuist.Marketing.Workers.CacheGlobeRefreshWorker do
  @moduledoc """
  Singleton writer for the public cache-globe snapshot.

  Only one incomplete job of this worker may exist cluster-wide (Oban unique).
  Cron on the web leader inserts it about once a minute; web `Stats` pollers
  only *read* the cached snapshot and never take a Redis lock around the
  ClickHouse query. That avoids the multi-replica lock stampede that forced
  the emergency revert of the booth TV page.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker], period: :infinity, states: :incomplete]

  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe

  @cache_key [:marketing, :cache_globe]
  # Longer than the cron interval so readers always have a value between refreshes.
  @cache_ttl to_timeout(second: 120)

  @impl Oban.Worker
  def perform(_job) do
    snapshot = CacheGlobe.snapshot()

    KeyValueStore.put(@cache_key, snapshot,
      persist_across_deployments: true,
      ttl: @cache_ttl
    )

    :ok
  end
end
