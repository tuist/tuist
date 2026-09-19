defmodule Tuist.IngestRepo.Migrations.CreateRunnerConcurrencySessions do
  use Ecto.Migration

  # Analytics replica of the Postgres `runner_sessions` rows, holding
  # the interval each runner occupied its account's concurrency budget.
  # Feeds the Concurrency card on the runners dashboard.
  #
  # ClickHouse (not Postgres) because the read is an analytical sweep:
  # every session an account held across a 30-day window, expanded into
  # start/stop resource events, running-summed and bucketed. Postgres
  # served it in 43ms for the busiest account's 19k sessions but 798ms
  # at 100k, and it is the control-plane primary that the dispatch and
  # claim transactions run on.
  #
  # `started_at` leads the order key because every query is an
  # account-scoped window over it. `id` carries the Postgres primary key
  # so the RMT collapses re-ingests of the same session; it closes the
  # order key rather than leading it so the window prefix stays usable.
  #
  # The replicating tailer is at-least-once, so a session can land more
  # than once. `ingested_at` versions those: the later ingest read a
  # fresher Postgres row, so highest wins. Reads must still dedup with
  # `argMax(…, ingested_at) GROUP BY id` — before a merge runs, two rows
  # for one session would otherwise both count and double its
  # resources.
  #
  # `source_updated_at` mirrors the Postgres row's `updated_at` and is
  # what the tailer resumes from, so the replica needs no cursor of its
  # own: `max(source_updated_at)` is where it got to, and an empty table
  # backfills from the beginning.
  def up do
    create table(:runner_concurrency_sessions,
             primary_key: false,
             engine: "ReplacingMergeTree(ingested_at)",
             options: "PARTITION BY toYYYYMM(started_at) ORDER BY (account_id, started_at, id)"
           ) do
      add :id, :Int64, null: false
      add :account_id, :Int64, null: false

      # Resolved when the row is replicated, not when it is read: the
      # fleet-name fallback for sessions predating the resource columns
      # lives in `Tuist.Runners.Catalog` and matches on prefixes, which
      # is Elixir's job rather than the query's.
      add :platform, :"LowCardinality(String)", null: false
      add :vcpus, :Int32, null: false, default: 0
      add :memory_gb, :Int32, null: false, default: 0

      # The claim's interval. `released_at` is the moment the slot was
      # freed, or the runner-session ceiling past which it cannot still
      # be held — a session still open resolves to the latter, so the
      # reader needs no branch for one.
      add :started_at, :"DateTime64(6, 'UTC')", null: false
      add :released_at, :"DateTime64(6, 'UTC')", null: false

      add :source_updated_at, :"DateTime64(6, 'UTC')", null: false
      add :ingested_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("now64(6)")
    end
  end

  def down do
    drop table(:runner_concurrency_sessions)
  end
end
