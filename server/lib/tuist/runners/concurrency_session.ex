defmodule Tuist.Runners.ConcurrencySession do
  @moduledoc """
  ClickHouse replica of the interval a runner session occupied its
  account's concurrency budget.

  Written only by `Tuist.Runners.SessionReplication`, which reads the
  authoritative Postgres `runner_sessions` row. Nothing else may insert
  here: a writer that carried a ClickHouse row forward instead would
  re-assert whatever state the replica happened to hold, which is how
  `runner_jobs` ended up with 1249 rows stuck non-terminal.

  See `priv/ingest_repo/migrations/20260821090000_create_runner_concurrency_sessions.exs`
  for the engine and order-key rationale.
  """
  use Ecto.Schema

  @primary_key false

  schema "runner_concurrency_sessions" do
    field :id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :platform, Ch, type: "LowCardinality(String)"
    field :vcpus, Ch, type: "Int32"
    field :memory_gb, Ch, type: "Int32"
    field :started_at, Ch, type: "DateTime64(6, 'UTC')"
    field :released_at, Ch, type: "DateTime64(6, 'UTC')"
    field :source_updated_at, Ch, type: "DateTime64(6, 'UTC')"
    field :ingested_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
